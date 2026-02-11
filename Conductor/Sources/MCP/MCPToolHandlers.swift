import Foundation

/// Implements MCP tool handlers that call EventKit and Database directly.
/// Checks DB preferences before each tool call (server-side gating).
final class MCPToolHandlers: Sendable {

    // MARK: - Safety Limits

    private static let maxDateRangeDays = 30
    private static let maxItemsPerCall = 50

    // MARK: - Tool Definitions

    static func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "conductor_get_calendar",
                "description": "Get calendar events for a date range. Defaults to today if no dates specified.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "start_date": [
                            "type": "string",
                            "description": "Start date in ISO 8601 format (YYYY-MM-DD). Defaults to today."
                        ],
                        "end_date": [
                            "type": "string",
                            "description": "End date in ISO 8601 format (YYYY-MM-DD). Defaults to end of start_date."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_reminders",
                "description": "Get upcoming incomplete reminders.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of reminders to return (default 20, max 50)."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_goals",
                "description": "Get today's goals with completion status and overdue count.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_notes",
                "description": "Get recent notes.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of notes to return (default 5, max 50)."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_emails",
                "description": "Get important/VIP emails from Apple Mail.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "filter": [
                            "type": "string",
                            "description": "Optional filter string to match against sender or subject."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_create_agent_task",
                "description": "Create a background agent task that runs autonomously at a specified time or on a schedule. Use this when the user asks you to remind them, follow up, check on something later, or schedule any recurring action.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Short name for the task (e.g. 'Follow up with John')"
                        ],
                        "prompt": [
                            "type": "string",
                            "description": "The instruction for the agent to execute when the task fires"
                        ],
                        "trigger_type": [
                            "type": "string",
                            "enum": ["time", "recurring", "checkin", "manual"],
                            "description": "When to trigger: 'time' for one-shot at specific time, 'recurring' for repeated, 'checkin' for check-in phases, 'manual' for on-demand"
                        ],
                        "fire_at": [
                            "type": "string",
                            "description": "ISO 8601 datetime for one-shot tasks (e.g. '2025-01-15T14:00:00')"
                        ],
                        "interval_minutes": [
                            "type": "integer",
                            "description": "Repeat interval in minutes for recurring tasks"
                        ],
                        "cron_hour": [
                            "type": "integer",
                            "description": "Hour (0-23) for daily recurring tasks"
                        ],
                        "cron_minute": [
                            "type": "integer",
                            "description": "Minute (0-59) for daily recurring tasks"
                        ],
                        "checkin_phase": [
                            "type": "string",
                            "enum": ["morning", "midmorning", "afternoon", "winddown", "evening"],
                            "description": "Which check-in phase triggers this task"
                        ],
                        "context_needs": [
                            "type": "array",
                            "items": ["type": "string", "enum": ["calendar", "reminders", "goals", "email", "notes", "tasks"]],
                            "description": "What context the agent needs when running"
                        ],
                        "max_runs": [
                            "type": "integer",
                            "description": "Maximum number of times to run (null = unlimited for recurring)"
                        ]
                    ],
                    "required": ["name", "prompt", "trigger_type"]
                ]
            ],
            [
                "name": "conductor_list_agent_tasks",
                "description": "List all agent tasks (background tasks, reminders, scheduled actions).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "status": [
                            "type": "string",
                            "enum": ["active", "paused", "completed", "all"],
                            "description": "Filter by status. Default: 'active'"
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_themes",
                "description": "Get active themes with task counts. Themes group related tasks, goals, and notes.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "include_archived": [
                            "type": "boolean",
                            "description": "Include archived themes (default false)"
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_create_theme",
                "description": "Create a new theme to group related tasks, goals, and notes. Use this when the user wants to organize work around a topic, project, or area of focus.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Theme name (e.g. 'ViTok-v2 arxiv', '3D Vision Class')"
                        ],
                        "color": [
                            "type": "string",
                            "enum": ["red", "orange", "yellow", "green", "blue", "purple", "pink", "gray", "indigo", "teal"],
                            "description": "Theme color (default: blue)"
                        ],
                        "description": [
                            "type": "string",
                            "description": "Optional description of what this theme covers"
                        ],
                        "keywords": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Calendar event keywords for auto-matching events to this theme"
                        ]
                    ],
                    "required": ["name"]
                ]
            ],
            [
                "name": "conductor_cancel_agent_task",
                "description": "Cancel, pause, or resume an agent task.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": [
                            "type": "string",
                            "description": "ID of the agent task"
                        ],
                        "action": [
                            "type": "string",
                            "enum": ["cancel", "pause", "resume"],
                            "description": "Action to take on the task"
                        ]
                    ],
                    "required": ["task_id", "action"]
                ]
            ]
        ]
    }

    // MARK: - Tool Dispatch

    func handleToolCall(name: String, arguments: [String: Any]) async -> [String: Any] {
        switch name {
        case "conductor_get_calendar":
            return await handleGetCalendar(arguments)
        case "conductor_get_reminders":
            return await handleGetReminders(arguments)
        case "conductor_get_goals":
            return await handleGetGoals(arguments)
        case "conductor_get_notes":
            return await handleGetNotes(arguments)
        case "conductor_get_emails":
            return await handleGetEmails(arguments)
        case "conductor_create_agent_task":
            return await handleCreateAgentTask(arguments)
        case "conductor_list_agent_tasks":
            return await handleListAgentTasks(arguments)
        case "conductor_get_themes":
            return await handleGetThemes(arguments)
        case "conductor_create_theme":
            return await handleCreateTheme(arguments)
        case "conductor_cancel_agent_task":
            return await handleCancelAgentTask(arguments)
        default:
            return mcpError("Unknown tool: \(name)")
        }
    }

    // MARK: - Calendar

    private func handleGetCalendar(_ args: [String: Any]) async -> [String: Any] {
        // Server-side gating: check DB preference
        guard (try? Database.shared.getPreference(key: "calendar_read_enabled")) != "false" else {
            return mcpError("Calendar access is disabled in Conductor Settings. The user can enable it in Settings > Security & Permissions.")
        }

        guard EventKitManager.shared.calendarAuthorizationStatus() == .fullAccess else {
            return mcpError("Calendar permission not granted. The user needs to grant Full Access in System Settings > Privacy & Security > Calendars.")
        }

        let calendar = Calendar.current
        let now = Date()

        // Parse start date
        let startDate: Date
        if let startStr = args["start_date"] as? String, let parsed = parseDate(startStr) {
            startDate = calendar.startOfDay(for: parsed)
        } else {
            startDate = calendar.startOfDay(for: now)
        }

        // Parse end date
        let endDate: Date
        if let endStr = args["end_date"] as? String, let parsed = parseDate(endStr) {
            // End of the specified day
            endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: parsed)) ?? parsed
        } else {
            // Default: end of start date
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }

        // Safety: cap date range
        let daysBetween = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        guard daysBetween <= Self.maxDateRangeDays else {
            return mcpError("Date range too large. Maximum is \(Self.maxDateRangeDays) days.")
        }

        let events = await EventKitManager.shared.getEvents(from: startDate, to: endDate)
        let capped = Array(events.prefix(Self.maxItemsPerCall))

        let eventDicts: [[String: Any]] = capped.map { event in
            var dict: [String: Any] = [
                "title": event.title,
                "start_time": SharedDateFormatters.iso8601.string(from: event.startDate),
                "end_time": SharedDateFormatters.iso8601.string(from: event.endDate),
                "time": event.time,
                "duration": event.duration,
                "is_all_day": event.isAllDay
            ]
            if let location = event.location, !location.isEmpty {
                dict["location"] = location
            }
            return dict
        }

        let text: String
        if eventDicts.isEmpty {
            let dateDesc = SharedDateFormatters.fullDate.string(from: startDate)
            text = "No calendar events found for \(dateDesc)."
        } else {
            let lines = capped.map { event -> String in
                var line = "- \(event.time): \(event.title) (\(event.duration))"
                if let location = event.location, !location.isEmpty {
                    line += " @ \(location)"
                }
                return line
            }
            text = "Found \(capped.count) event(s):\n" + lines.joined(separator: "\n")
        }

        return mcpSuccess(text)
    }

    // MARK: - Reminders

    private func handleGetReminders(_ args: [String: Any]) async -> [String: Any] {
        guard (try? Database.shared.getPreference(key: "reminders_read_enabled")) != "false" else {
            return mcpError("Reminders access is disabled in Conductor Settings. The user can enable it in Settings > Security & Permissions.")
        }

        guard EventKitManager.shared.remindersAuthorizationStatus() == .fullAccess else {
            return mcpError("Reminders permission not granted. The user needs to grant Full Access in System Settings > Privacy & Security > Reminders.")
        }

        let limit = min(args["limit"] as? Int ?? 20, Self.maxItemsPerCall)
        let reminders = await EventKitManager.shared.getUpcomingReminders(limit: limit)

        let text: String
        if reminders.isEmpty {
            text = "No pending reminders found."
        } else {
            let lines = reminders.map { r -> String in
                var line = "- \(r.title)"
                if let due = r.dueDate {
                    line += " (due: \(due))"
                }
                if r.priority > 0 {
                    line += " [priority: \(r.priority)]"
                }
                return line
            }
            text = "Found \(reminders.count) reminder(s):\n" + lines.joined(separator: "\n")
        }

        return mcpSuccess(text)
    }

    // MARK: - Goals

    private func handleGetGoals(_ args: [String: Any]) async -> [String: Any] {
        guard (try? Database.shared.getPreference(key: "planning_enabled")) != "false" else {
            return mcpError("Daily planning is disabled in Conductor Settings. The user can enable it in Settings > Daily Planning.")
        }

        let today = DailyPlanningService.todayDateString
        let goals = (try? Database.shared.getGoalsForDate(today)) ?? []
        let completionRate = (try? Database.shared.getGoalCompletionRate(forDays: 7)) ?? 0
        let overdueGoals = (try? Database.shared.getIncompleteGoals(before: today)) ?? []

        let text: String
        if goals.isEmpty && overdueGoals.isEmpty {
            text = "No goals set for today and no overdue goals."
        } else {
            var lines: [String] = []

            if !goals.isEmpty {
                lines.append("Today's goals:")
                for goal in goals {
                    let status = goal.isCompleted ? "[done]" : "[pending]"
                    lines.append("- \(status) \(goal.goalText) (priority: \(goal.priority))")
                }
            }

            if !overdueGoals.isEmpty {
                lines.append("\nOverdue goals (\(overdueGoals.count)):")
                for goal in overdueGoals.prefix(10) {
                    lines.append("- \(goal.goalText) (from \(goal.date))")
                }
            }

            lines.append("\n7-day completion rate: \(Int(completionRate * 100))%")

            text = lines.joined(separator: "\n")
        }

        return mcpSuccess(text)
    }

    // MARK: - Notes

    private func handleGetNotes(_ args: [String: Any]) async -> [String: Any] {
        let limit = min(args["limit"] as? Int ?? 5, Self.maxItemsPerCall)

        guard let notes = try? Database.shared.loadNotes(limit: limit), !notes.isEmpty else {
            return mcpSuccess("No notes found.")
        }

        let lines = notes.map { note -> String in
            let preview = String(note.content.prefix(200))
            return "- \(note.title): \(preview)"
        }
        let text = "Found \(notes.count) note(s):\n" + lines.joined(separator: "\n")

        return mcpSuccess(text)
    }

    // MARK: - Emails

    private func handleGetEmails(_ args: [String: Any]) async -> [String: Any] {
        guard (try? Database.shared.getPreference(key: "email_integration_enabled")) == "true" else {
            return mcpError("Email integration is disabled in Conductor Settings. The user can enable it in Settings > Security & Permissions.")
        }

        let emailContext = await MailService.shared.buildEmailContext()
        let filter = args["filter"] as? String

        var emails = emailContext.importantEmails
        if let filter, !filter.isEmpty {
            emails = emails.filter { email in
                email.sender.localizedCaseInsensitiveContains(filter) ||
                email.subject.localizedCaseInsensitiveContains(filter)
            }
        }

        let capped = Array(emails.prefix(Self.maxItemsPerCall))

        let text: String
        if capped.isEmpty {
            text = filter != nil
                ? "No emails matching '\(filter!)' found."
                : "No important emails found. Unread count: \(emailContext.unreadCount)."
        } else {
            let lines = capped.map { email -> String in
                let readStatus = email.isRead ? "" : " (unread)"
                return "- From \(email.sender): \(email.subject)\(readStatus)"
            }
            text = "Unread: \(emailContext.unreadCount). Important emails (\(capped.count)):\n" + lines.joined(separator: "\n")
        }

        return mcpSuccess(text)
    }

    // MARK: - Agent Tasks

    private func handleCreateAgentTask(_ args: [String: Any]) async -> [String: Any] {
        guard let name = args["name"] as? String,
              let prompt = args["prompt"] as? String,
              let triggerTypeStr = args["trigger_type"] as? String,
              let triggerType = AgentTask.TriggerType(rawValue: triggerTypeStr) else {
            return mcpError("Missing required fields: name, prompt, trigger_type")
        }

        var triggerConfig = TriggerConfig()

        if let fireAtStr = args["fire_at"] as? String {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: fireAtStr) {
                triggerConfig.fireAt = date
            } else if let date = SharedDateFormatters.databaseDate.date(from: fireAtStr) {
                triggerConfig.fireAt = date
            }
        }

        if let interval = args["interval_minutes"] as? Int {
            triggerConfig.intervalMinutes = interval
        }
        if let cronHour = args["cron_hour"] as? Int {
            triggerConfig.cronHour = cronHour
        }
        if let cronMinute = args["cron_minute"] as? Int {
            triggerConfig.cronMinute = cronMinute
        }
        if let phase = args["checkin_phase"] as? String {
            triggerConfig.checkinPhase = phase
        }

        let contextNeedStrings = args["context_needs"] as? [String] ?? []
        let contextNeeds = contextNeedStrings.compactMap(AgentContextNeed.init(rawValue:))

        let maxRuns = args["max_runs"] as? Int

        // Calculate next run
        var nextRun: Date?
        switch triggerType {
        case .time:
            nextRun = triggerConfig.fireAt
        case .recurring:
            if let interval = triggerConfig.intervalMinutes {
                nextRun = Date().addingTimeInterval(Double(interval) * 60)
            } else if let hour = triggerConfig.cronHour {
                let minute = triggerConfig.cronMinute ?? 0
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = hour
                components.minute = minute
                if let todayRun = calendar.date(from: components), todayRun > Date() {
                    nextRun = todayRun
                } else if let todayRun = calendar.date(from: components) {
                    nextRun = calendar.date(byAdding: .day, value: 1, to: todayRun)
                }
            }
        case .checkin, .event, .manual:
            nextRun = nil
        }

        let task = AgentTask(
            name: name,
            prompt: prompt,
            triggerType: triggerType,
            triggerConfig: triggerConfig,
            contextNeeds: contextNeeds,
            createdBy: .chat,
            nextRun: nextRun,
            maxRuns: maxRuns
        )

        do {
            try Database.shared.createAgentTask(task)

            var text = "Agent task created: \"\(name)\" (ID: \(task.id))\n"
            text += "Trigger: \(triggerTypeStr)"
            if let nextRun {
                text += "\nNext run: \(SharedDateFormatters.fullDateTime.string(from: nextRun))"
            }
            if triggerType == .checkin, let phase = triggerConfig.checkinPhase {
                text += "\nPhase: \(phase)"
            }

            return mcpSuccess(text)
        } catch {
            return mcpError("Failed to create agent task: \(error.localizedDescription)")
        }
    }

    private func handleListAgentTasks(_ args: [String: Any]) async -> [String: Any] {
        let statusFilter = args["status"] as? String ?? "active"

        do {
            let tasks: [AgentTask]
            if statusFilter == "all" {
                tasks = try Database.shared.getAllAgentTasks()
            } else {
                tasks = try Database.shared.getActiveAgentTasks()
            }

            guard !tasks.isEmpty else {
                return mcpSuccess("No \(statusFilter) agent tasks found.")
            }

            let lines = tasks.map { task -> String in
                var line = "- [\(task.status.rawValue)] \(task.name) (ID: \(task.id))"
                line += "\n  Trigger: \(task.triggerType.rawValue)"
                if let nextRun = task.nextRun {
                    line += " | Next: \(SharedDateFormatters.fullDateTime.string(from: nextRun))"
                }
                if task.runCount > 0 {
                    line += " | Runs: \(task.runCount)"
                    if let maxRuns = task.maxRuns {
                        line += "/\(maxRuns)"
                    }
                }
                return line
            }

            return mcpSuccess("Agent tasks (\(tasks.count)):\n" + lines.joined(separator: "\n"))
        } catch {
            return mcpError("Failed to list agent tasks: \(error.localizedDescription)")
        }
    }

    private func handleCancelAgentTask(_ args: [String: Any]) async -> [String: Any] {
        guard let taskId = args["task_id"] as? String,
              let action = args["action"] as? String else {
            return mcpError("Missing required fields: task_id, action")
        }

        do {
            guard var task = try Database.shared.getAgentTask(id: taskId) else {
                return mcpError("Agent task not found: \(taskId)")
            }

            switch action {
            case "cancel":
                task.status = .completed
                try Database.shared.updateAgentTask(task)
                return mcpSuccess("Agent task cancelled: \"\(task.name)\"")
            case "pause":
                task.status = .paused
                try Database.shared.updateAgentTask(task)
                return mcpSuccess("Agent task paused: \"\(task.name)\"")
            case "resume":
                task.status = .active
                try Database.shared.updateAgentTask(task)
                return mcpSuccess("Agent task resumed: \"\(task.name)\"")
            default:
                return mcpError("Invalid action: \(action). Use 'cancel', 'pause', or 'resume'.")
            }
        } catch {
            return mcpError("Failed to \(action) agent task: \(error.localizedDescription)")
        }
    }

    // MARK: - Themes

    private func handleGetThemes(_ args: [String: Any]) async -> [String: Any] {
        let includeArchived = args["include_archived"] as? Bool ?? false

        do {
            let themes = try Database.shared.getThemes(includeArchived: includeArchived)

            guard !themes.isEmpty else {
                return mcpSuccess("No themes found. Create themes to group related tasks, goals, and notes.")
            }

            let lines = try themes.map { theme -> String in
                let taskCount = try Database.shared.getTaskCountForTheme(id: theme.id)
                let keywords = try Database.shared.getThemeKeywords(forTheme: theme.id)
                var line = "- \(theme.name) [\(theme.color)]"
                if taskCount > 0 {
                    line += " (\(taskCount) tasks)"
                }
                if let desc = theme.themeDescription {
                    line += " — \(desc)"
                }
                if !keywords.isEmpty {
                    line += "\n  Calendar keywords: \(keywords.joined(separator: ", "))"
                }
                if theme.isArchived {
                    line += " [archived]"
                }
                return line
            }

            return mcpSuccess("Themes (\(themes.count)):\n" + lines.joined(separator: "\n"))
        } catch {
            return mcpError("Failed to get themes: \(error.localizedDescription)")
        }
    }

    private func handleCreateTheme(_ args: [String: Any]) async -> [String: Any] {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return mcpError("Missing required field: name")
        }

        let validColors = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "gray", "indigo", "teal"]
        let color = (args["color"] as? String).flatMap { validColors.contains($0) ? $0 : nil } ?? "blue"
        let description = args["description"] as? String
        let keywords = args["keywords"] as? [String] ?? []

        let theme = Theme(
            id: UUID().uuidString,
            name: name,
            color: color,
            themeDescription: description,
            isArchived: false,
            sortOrder: 0,
            createdAt: Date()
        )

        do {
            try Database.shared.createTheme(theme)

            for keyword in keywords {
                let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try Database.shared.addThemeKeyword(trimmed, toTheme: theme.id)
                }
            }

            var text = "Theme created: \"\(name)\" [\(color)] (ID: \(theme.id))"
            if let description { text += "\nDescription: \(description)" }
            if !keywords.isEmpty { text += "\nKeywords: \(keywords.joined(separator: ", "))" }
            return mcpSuccess(text)
        } catch {
            return mcpError("Failed to create theme: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func parseDate(_ string: String) -> Date? {
        // Try ISO 8601 date-only format first (YYYY-MM-DD)
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        if let date = dateOnly.date(from: string) {
            return date
        }

        // Try full ISO 8601
        return SharedDateFormatters.iso8601.date(from: string)
    }

    private func mcpSuccess(_ text: String) -> [String: Any] {
        [
            "content": [
                ["type": "text", "text": text]
            ],
            "isError": false
        ]
    }

    private func mcpError(_ message: String) -> [String: Any] {
        [
            "content": [
                ["type": "text", "text": message]
            ],
            "isError": true
        ]
    }
}
