import Foundation

/// The Blink Engine: a quiet AI monitor that polls periodically,
/// checks context, and only bothers the user when something needs attention.
actor BlinkEngine {
    static let shared = BlinkEngine()

    private var timerTask: Task<Void, Never>?
    private var isRunning = false

    private let db: AppDatabase
    private let intervalProvider: () -> TimeInterval

    init(
        db: AppDatabase = .shared,
        intervalProvider: @escaping () -> TimeInterval = {
            let minutes = (try? PreferenceRepository(db: .shared).getInt("blink_interval_minutes", default: 15)) ?? 15
            return TimeInterval(max(minutes, 1) * 60)
        }
    ) {
        self.db = db
        self.intervalProvider = intervalProvider
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Log.blink.info("Blink Engine started")

        timerTask = Task { [weak self] in
            // Initial delay: wait 2 minutes before first blink
            try? await Task.sleep(for: .seconds(120))

            while !Task.isCancelled {
                guard let self else { break }
                await self.performBlink()

                let interval = self.intervalProvider()
                Log.blink.info("Next blink in \(Int(interval))s")
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
        Log.blink.info("Blink Engine stopped")
    }

    /// Trigger a blink manually (for testing or on-demand)
    func triggerBlink() async {
        await performBlink()
    }

    private func performBlink() async {
        Log.blink.info("Blink cycle starting...")

        let projectRepo = ProjectRepository(db: db)
        let blinkRepo = BlinkRepository(db: db)

        // Gather context
        let calendarEvents = await EventKitManager.shared.getTodayEvents()
        let openTodos = (try? projectRepo.allOpenTodos()) ?? []
        let runningAgents = (try? blinkRepo.runningAgentRuns()) ?? []
        let recentBlinks = (try? blinkRepo.recentBlinks(limit: 3)) ?? []
        let unreadEmails = await MailService.shared.getUnreadCount()
        let recentEmails = await MailService.shared.getRecentEmails(hoursBack: 12)

        // Build prompt
        let prompt = BlinkPromptBuilder.build(
            calendarEvents: calendarEvents,
            openTodos: openTodos,
            runningAgents: runningAgents,
            recentBlinks: recentBlinks,
            unreadEmailCount: unreadEmails,
            recentEmails: recentEmails
        )

        do {
            let response = try await ClaudeService.shared.executeBlinkPrompt(prompt)

            // Parse JSON decision from response
            let decision = parseBlinkDecision(from: response.result)

            // Log the blink
            let log = BlinkLog(
                decision: decision.decision,
                contextSummary: decision.reasoning ?? "No reasoning provided",
                notificationTitle: decision.notificationTitle,
                notificationBody: decision.notificationBody,
                agentTodoId: decision.agentTodoId,
                agentPrompt: decision.agentPrompt,
                costUsd: response.totalCostUsd,
                createdAt: Date()
            )
            try? blinkRepo.logBlink(log)

            // Act on decision
            switch decision.decision {
            case .silent:
                Log.blink.info("Blink: silent")

            case .notify:
                if let title = decision.notificationTitle, let body = decision.notificationBody {
                    Log.blink.info("Blink: notify — \(title, privacy: .public)")
                    await NotificationManager.shared.sendNotification(
                        title: title,
                        body: body,
                        suggestedPrompt: decision.suggestedPrompt
                    )
                }

            case .agent:
                if let todoId = decision.agentTodoId, let prompt = decision.agentPrompt {
                    Log.blink.info("Blink: agent dispatch for TODO \(todoId)")
                    let run = try blinkRepo.createAgentRun(todoId: todoId, prompt: prompt)
                    Task.detached {
                        await AgentDispatcher.shared.execute(runId: run.id!, todoId: todoId, prompt: prompt)
                    }
                }
            }

            Log.blink.info("Blink cycle complete (cost: \(response.totalCostUsd ?? 0))")

        } catch {
            Log.blink.error("Blink cycle failed: \(error.localizedDescription, privacy: .public)")

            // Log failed blink
            let failedLog = BlinkLog(
                decision: .silent,
                contextSummary: "Error: \(error.localizedDescription)",
                costUsd: nil,
                createdAt: Date()
            )
            try? blinkRepo.logBlink(failedLog)
        }
    }

    // MARK: - Parse Response

    struct BlinkDecisionResult {
        let decision: BlinkDecision
        let notificationTitle: String?
        let notificationBody: String?
        let suggestedPrompt: String?
        let agentTodoId: Int64?
        let agentPrompt: String?
        let reasoning: String?
    }

    private func parseBlinkDecision(from text: String) -> BlinkDecisionResult {
        // Try to extract JSON from the response
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try direct JSON parse
        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return extractDecision(from: json)
        }

        // Try to find JSON in markdown code blocks
        if let jsonRange = cleaned.range(of: "\\{[^{}]*\\}", options: .regularExpression) {
            let jsonStr = String(cleaned[jsonRange])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return extractDecision(from: json)
            }
        }

        // Fallback: silent
        Log.blink.warning("Could not parse blink response, defaulting to silent")
        return BlinkDecisionResult(
            decision: .silent,
            notificationTitle: nil,
            notificationBody: nil,
            suggestedPrompt: nil,
            agentTodoId: nil,
            agentPrompt: nil,
            reasoning: "Parse failure: \(cleaned.prefix(200))"
        )
    }

    private func extractDecision(from json: [String: Any]) -> BlinkDecisionResult {
        let decisionStr = json["decision"] as? String ?? "silent"
        let decision: BlinkDecision
        switch decisionStr {
        case "notify": decision = .notify
        case "agent": decision = .agent
        default: decision = .silent
        }

        return BlinkDecisionResult(
            decision: decision,
            notificationTitle: json["notification_title"] as? String,
            notificationBody: json["notification_body"] as? String,
            suggestedPrompt: json["suggested_prompt"] as? String,
            agentTodoId: json["agent_todo_id"] as? Int64,
            agentPrompt: json["agent_prompt"] as? String,
            reasoning: json["reasoning"] as? String
        )
    }
}
