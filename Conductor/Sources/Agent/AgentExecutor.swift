import Foundation
import os

/// Executes agent tasks using a dedicated ClaudeService instance (separate from chat).
/// Runs tasks serially (max 1 concurrent CLI call) to control cost and resource usage.
actor AgentExecutor {
    static let shared = AgentExecutor()

    private let claudeService: ClaudeService
    private let database = Database.shared
    private var taskQueue: [AgentTask] = []
    private var isExecuting = false
    private var currentTaskId: String?

    var currentlyExecutingTaskId: String? { currentTaskId }

    init(claudeService: ClaudeService? = nil) {
        // Dedicated ClaudeService instance — separate from chat
        self.claudeService = claudeService ?? ClaudeService()
    }

    // MARK: - Queue Management

    func enqueue(_ task: AgentTask) {
        taskQueue.append(task)
        Task { await processNextIfIdle() }
    }

    func enqueueBatch(_ tasks: [AgentTask]) {
        taskQueue.append(contentsOf: tasks)
        Task { await processNextIfIdle() }
    }

    var queueCount: Int { taskQueue.count }

    // MARK: - Execution

    private func processNextIfIdle() async {
        guard !isExecuting, !taskQueue.isEmpty else { return }

        isExecuting = true
        let task = taskQueue.removeFirst()
        currentTaskId = task.id

        await MainActor.run {
            AppState.shared.logActivity(.scheduler, "Agent executing: \(task.name)")
        }

        await executeTask(task)

        currentTaskId = nil
        isExecuting = false

        // Process next if queue is not empty
        if !taskQueue.isEmpty {
            await processNextIfIdle()
        }
    }

    private func executeTask(_ task: AgentTask) async {
        // Check budget before executing
        if CostTracker.shared.isDailyBudgetExceeded {
            await MainActor.run {
                AppState.shared.logActivity(.error, "Agent task skipped (budget exceeded): \(task.name)")
            }
            return
        }

        let startTime = Date()

        do {
            // 1. Build context from task's contextNeeds
            let contextText = await buildContextForTask(task)

            // 2. Compose prompt: task prompt + formatted context
            let fullPrompt = composeAgentPrompt(task: task, context: contextText)

            // 3. Call Claude via dedicated instance (fresh session, no --resume)
            let response = try await claudeService.executeAgentPrompt(
                fullPrompt,
                modelOverride: "opus"
            )

            // 4. Parse actions from response
            let parseResult = ActionParser.extractActions(from: response.result)

            // 5. Process actions
            var executedActions: [ExecutedAction] = []
            var pendingApproval = false

            for action in parseResult.actions {
                let isSafe = ActionExecutor.safeActionTypes.contains(action.type)
                    && task.allowedActions.contains(action.type)
                    && !action.requiresUserApproval

                if isSafe {
                    let success = await ActionExecutor.shared.execute(action)
                    executedActions.append(ExecutedAction(
                        actionId: action.id,
                        type: action.type,
                        title: action.title,
                        approved: success
                    ))
                } else {
                    pendingApproval = true
                }
            }

            // 6. Save result
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let resultStatus: AgentTaskResult.ResultStatus = pendingApproval ? .pendingApproval : .success

            let result = AgentTaskResult(
                taskId: task.id,
                output: parseResult.cleanText,
                actionsProposed: parseResult.actions,
                actionsExecuted: executedActions,
                costUsd: response.totalCostUsd,
                status: resultStatus,
                durationMs: durationMs
            )

            try database.saveAgentTaskResult(result)

            // 7. Update task state
            let now = Date()
            let newRunCount = task.runCount + 1
            let nextRunDate = calculateNextRun(for: task, after: now)
            var newStatus = task.status

            // Complete one-shot tasks or tasks that hit maxRuns
            if task.isOneShot || (task.maxRuns != nil && newRunCount >= task.maxRuns!) {
                newStatus = .completed
            }

            var updated = task
            updated.lastRun = now
            updated.nextRun = nextRunDate
            updated.runCount = newRunCount
            updated.status = newStatus
            try database.updateAgentTask(updated)

            // 8. Log cost
            if let cost = response.totalCostUsd {
                do {
                    try database.logCost(amount: cost, sessionId: nil)
                } catch {
                    Log.agent.error("Failed to log agent cost: \(error.localizedDescription, privacy: .public)")
                }
            }

            // 9. Update UI
            await MainActor.run {
                AppState.shared.logActivity(.scheduler, "Agent completed: \(task.name)")
                if let cost = response.totalCostUsd {
                    AppState.shared.logActivity(.ai, "Agent cost: \(String(format: "$%.4f", cost))")
                }
                if pendingApproval {
                    AppState.shared.pendingApprovalCount += parseResult.actions.filter {
                        !ActionExecutor.safeActionTypes.contains($0.type) || $0.requiresUserApproval
                    }.count
                }
                AppState.shared.loadCostData()
            }

        } catch {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

            // Save failed result
            let result = AgentTaskResult(
                taskId: task.id,
                output: "Error: \(error.localizedDescription)",
                status: .failed,
                durationMs: durationMs
            )
            do {
                try database.saveAgentTaskResult(result)
            } catch {
                Log.agent.error("Failed to save error result for task \(task.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            await MainActor.run {
                AppState.shared.logActivity(.error, "Agent failed: \(task.name) - \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Context Building

    private func buildContextForTask(_ task: AgentTask) async -> String {
        var contextParts: [String] = []

        for need in task.contextNeeds {
            switch need {
            case .calendar:
                let events = await EventKitManager.shared.getTodayEvents()
                if !events.isEmpty {
                    contextParts.append("## Today's Calendar:\n" + events.map {
                        "- \($0.time): \($0.title) (\($0.duration))"
                    }.joined(separator: "\n"))
                }
            case .reminders:
                let reminders = await EventKitManager.shared.getUpcomingReminders(limit: 10)
                if !reminders.isEmpty {
                    contextParts.append("## Reminders:\n" + reminders.map {
                        "- \($0.title)" + ($0.dueDate.map { " (due: \($0))" } ?? "")
                    }.joined(separator: "\n"))
                }
            case .goals:
                let today = DailyPlanningService.todayDateString
                let goals = (try? database.getGoalsForDate(today)) ?? []
                if !goals.isEmpty {
                    contextParts.append("## Today's Goals:\n" + goals.map {
                        "- [\($0.isCompleted ? "x" : " ")] \($0.goalText)"
                    }.joined(separator: "\n"))
                }
            case .email:
                let emailContext = await MailService.shared.buildEmailContext()
                if !emailContext.importantEmails.isEmpty {
                    contextParts.append("## Important Emails (\(emailContext.unreadCount) unread):\n" +
                        emailContext.importantEmails.prefix(10).map {
                            "- From \($0.sender): \($0.subject)\($0.isRead ? "" : " (unread)")"
                        }.joined(separator: "\n"))
                }
            case .notes:
                if let notes = try? database.loadNotes(limit: 5) {
                    contextParts.append("## Recent Notes:\n" + notes.map {
                        "- \($0.title): \(String($0.content.prefix(100)))"
                    }.joined(separator: "\n"))
                }
            case .tasks:
                let tasks = (try? database.getTodayTasks(includeCompleted: false)) ?? []
                if !tasks.isEmpty {
                    contextParts.append("## TODO Tasks:\n" + tasks.map {
                        "- \($0.title)" + ($0.dueDate.map { " (due: \(SharedDateFormatters.shortMonthDay.string(from: $0)))" } ?? "")
                    }.joined(separator: "\n"))
                }
            }
        }

        return contextParts.isEmpty ? "No context available." : contextParts.joined(separator: "\n\n")
    }

    private func composeAgentPrompt(task: AgentTask, context: String) -> String {
        """
        \(task.prompt)

        ---
        Context:
        \(context)
        """
    }

    // MARK: - Scheduling

    private func calculateNextRun(for task: AgentTask, after date: Date) -> Date? {
        switch task.triggerType {
        case .time, .manual:
            return nil // One-shot, no next run
        case .recurring:
            if let interval = task.triggerConfig.intervalMinutes {
                return date.addingTimeInterval(Double(interval) * 60)
            }
            if let hour = task.triggerConfig.cronHour {
                let minute = task.triggerConfig.cronMinute ?? 0
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                components.hour = hour
                components.minute = minute
                guard let todayRun = calendar.date(from: components) else { return nil }
                return todayRun > date ? todayRun : calendar.date(byAdding: .day, value: 1, to: todayRun)
            }
            return date.addingTimeInterval(3600) // Default: 1 hour
        case .event:
            return nil // Event-triggered, no fixed schedule
        case .checkin:
            return nil // Triggered by check-in phases
        }
    }
}
