import Foundation

/// Timer-based scheduler that polls for due agent tasks and feeds them to AgentExecutor.
final class AgentTaskScheduler {
    static let shared = AgentTaskScheduler()

    private var pollTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.conductor.agent-scheduler", qos: .utility)
    private let database = Database.shared
    private var isRunning = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        pollTimer = DispatchSource.makeTimerSource(queue: queue)
        pollTimer?.schedule(deadline: .now() + 10, repeating: 60) // Poll every 60s, first check after 10s
        pollTimer?.setEventHandler { [weak self] in
            self?.pollForDueTasks()
        }
        pollTimer?.resume()

        Log.agent.info("AgentTaskScheduler started (polling every 60s)")
        Task { @MainActor in
            AppState.shared.logActivity(.scheduler, "Agent task scheduler started")
        }
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        isRunning = false
        Log.agent.info("AgentTaskScheduler stopped")
    }

    // MARK: - Polling

    private func pollForDueTasks() {
        guard let dueTasks = try? database.getDueAgentTasks(), !dueTasks.isEmpty else {
            return
        }

        Log.agent.info("Found \(dueTasks.count) due task(s)")

        Task {
            await AgentExecutor.shared.enqueueBatch(dueTasks)
        }
    }

    // MARK: - Check-in Integration

    /// Called by EventScheduler during check-in triggers.
    /// Runs all active agent tasks that match the given check-in phase.
    func runCheckinTasks(phase: String) {
        guard let tasks = try? database.getCheckinAgentTasks(phase: phase), !tasks.isEmpty else {
            return
        }

        Log.agent.info("Running \(tasks.count) check-in task(s) for phase: \(phase, privacy: .public)")

        Task {
            await AgentExecutor.shared.enqueueBatch(tasks)
        }
    }

    // MARK: - Manual Trigger

    /// Manually trigger a specific agent task by ID.
    func triggerTask(id taskId: String) {
        guard let task = try? database.getAgentTask(id: taskId), task.status == .active else {
            Log.agent.warning("Task not found or not active: \(taskId, privacy: .public)")
            return
        }

        Task {
            await AgentExecutor.shared.enqueue(task)
        }
    }
}
