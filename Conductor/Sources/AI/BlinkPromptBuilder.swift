import Foundation

enum BlinkPromptBuilder {
    /// Builds the prompt for a blink cycle.
    /// Gathers context (calendar, open TODOs, deliverable status, running agents, recent blinks)
    /// and asks the model to decide: silent, notify, or agent.
    static func build(
        calendarEvents: [EventKitManager.CalendarEvent],
        openTodos: [Todo],
        runningAgents: [AgentRun],
        recentBlinks: [BlinkLog],
        unreadEmailCount: Int,
        recentEmails: [MailService.EmailSummary]
    ) -> String {
        let now = Date()
        let timeStr = SharedDateFormatters.fullDateTime.string(from: now)

        var sections: [String] = []

        // Time context
        sections.append("Current time: \(timeStr)")

        // Calendar
        if calendarEvents.isEmpty {
            sections.append("Calendar: No upcoming events today.")
        } else {
            let eventLines = calendarEvents.map { event in
                let time = event.isAllDay ? "All day" : "\(SharedDateFormatters.shortTime.string(from: event.startDate)) - \(SharedDateFormatters.shortTime.string(from: event.endDate))"
                return "- \(time): \(event.title)"
            }.joined(separator: "\n")
            sections.append("Calendar today:\n\(eventLines)")
        }

        // Active project context: check if current time falls within a calendar block
        let currentBlock = calendarEvents.first { event in
            !event.isAllDay && event.startDate <= now && event.endDate > now
        }
        if let block = currentBlock {
            sections.append("Currently in calendar block: \"\(block.title)\"")
        }

        // TODOs
        if openTodos.isEmpty {
            sections.append("Open TODOs: None")
        } else {
            let todoLines = openTodos.prefix(15).map { todo in
                let priority = todo.priority > 0 ? " [P\(todo.priority)]" : ""
                let due = todo.dueDate.map { " (due \(SharedDateFormatters.shortMonthDay.string(from: $0)))" } ?? ""
                return "- \(todo.title)\(priority)\(due)"
            }.joined(separator: "\n")
            sections.append("Open TODOs (\(openTodos.count) total):\n\(todoLines)")
        }

        // Running agents
        if !runningAgents.isEmpty {
            let agentLines = runningAgents.map { run in
                "- Agent run #\(run.id ?? 0) on TODO #\(run.todoId ?? 0): running since \(SharedDateFormatters.shortTime.string(from: run.startedAt))"
            }.joined(separator: "\n")
            sections.append("Running agents:\n\(agentLines)")
        }

        // Email
        if unreadEmailCount > 0 {
            sections.append("Unread emails: \(unreadEmailCount)")
        }
        if !recentEmails.isEmpty {
            let lines = recentEmails.prefix(5).map { email in
                let state = email.isRead ? "read" : "unread"
                return "- [\(state)] \(email.sender): \(email.subject)"
            }.joined(separator: "\n")
            sections.append("Recent emails:\n\(lines)")
        }

        // Recent blink history (for anti-repetition)
        if !recentBlinks.isEmpty {
            let blinkLines = recentBlinks.map { blink in
                let time = SharedDateFormatters.shortTime.string(from: blink.createdAt)
                var line = "- \(time): \(blink.decision.rawValue)"
                if let title = blink.notificationTitle { line += " — \"\(title)\"" }
                return line
            }.joined(separator: "\n")
            sections.append("Last \(recentBlinks.count) blink decisions:\n\(blinkLines)")
        }

        let context = sections.joined(separator: "\n\n")

        return """
        You are the Blink Engine for Conductor, a personal productivity assistant.
        Your job is to review the user's current context and decide ONE of three actions:

        1. "silent" — Everything looks fine. No action needed. This should be your DEFAULT.
        2. "notify" — Something genuinely needs the user's attention RIGHT NOW. Examples:
           - A meeting starts in 10 minutes and they might not know
           - A high-priority TODO is overdue
           - An important email just arrived
        3. "agent" — A TODO could benefit from AI agent work. Only suggest if:
           - The TODO is specific and actionable
           - No agent is already running on it
           - The work doesn't require user input

        IMPORTANT RULES:
        - Default to "silent". Only notify when genuinely necessary.
        - Do NOT repeat notifications from recent blinks.
        - Do NOT notify about things the user likely already knows.
        - If the notification is about an important email, include a practical "suggested_prompt" the user can run in chat to draft a reply.
        - If in doubt, choose "silent".

        Context:
        \(context)

        Respond with ONLY a JSON object (no markdown, no explanation):
        {
          "decision": "silent" | "notify" | "agent",
          "notification_title": "...",  // only if decision is "notify"
          "notification_body": "...",    // only if decision is "notify"
          "suggested_prompt": "...",     // optional prompt to prefill chat when opening notification
          "agent_todo_id": 123,          // only if decision is "agent"
          "agent_prompt": "...",         // only if decision is "agent"
          "reasoning": "..."             // brief explanation for the log
        }
        """
    }
}
