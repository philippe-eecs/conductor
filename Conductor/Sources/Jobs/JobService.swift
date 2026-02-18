import Foundation
import os

struct ConductorJob: Identifiable {
    let id: String
    var name: String
    var promptTemplate: String
    var triggerType: AgentTask.TriggerType
    var contextNeeds: [AgentContextNeed]
    var allowedActions: [AssistantActionRequest.ActionType]
    var status: AgentTask.Status
    var nextRun: Date?
    var runCount: Int
    var maxRuns: Int?

    init(from task: AgentTask) {
        id = task.id
        name = task.name
        promptTemplate = task.prompt
        triggerType = task.triggerType
        contextNeeds = task.contextNeeds
        allowedActions = task.allowedActions
        status = task.status
        nextRun = task.nextRun
        runCount = task.runCount
        maxRuns = task.maxRuns
    }

    func toAgentTask(createdBy: AgentTask.CreatedBy = .chat) -> AgentTask {
        AgentTask(
            id: id,
            name: name,
            prompt: promptTemplate,
            triggerType: triggerType,
            triggerConfig: TriggerConfig(),
            contextNeeds: contextNeeds,
            allowedActions: allowedActions,
            status: status,
            createdBy: createdBy,
            nextRun: nextRun,
            runCount: runCount,
            maxRuns: maxRuns
        )
    }
}

/// Single scheduling primitive for background jobs.
/// Compatibility layer over existing agent-task persistence/execution.
final class JobService {
    static let shared = JobService()

    private var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        AgentTaskScheduler.shared.start()
        Task { @MainActor in
            AppState.shared.logActivity(.scheduler, "Jobs engine started")
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        AgentTaskScheduler.shared.stop()
    }

    func create(_ job: ConductorJob) {
        do {
            try Database.shared.createAgentTask(job.toAgentTask())
        } catch {
            Log.scheduler.error("Failed to create job '\(job.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }

    func list(status: AgentTask.Status? = nil) -> [ConductorJob] {
        let tasks = (try? Database.shared.getAllAgentTasks()) ?? []
        return tasks
            .filter { status == nil || $0.status == status }
            .map(ConductorJob.init(from:))
    }

    func cancel(jobId: String) {
        do {
            guard var task = try Database.shared.getAgentTask(id: jobId) else { return }
            task.status = .completed
            try Database.shared.updateAgentTask(task)
        } catch {
            Log.scheduler.error("Failed to cancel job \(jobId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func pause(jobId: String) {
        do {
            guard var task = try Database.shared.getAgentTask(id: jobId) else { return }
            task.status = .paused
            try Database.shared.updateAgentTask(task)
        } catch {
            Log.scheduler.error("Failed to pause job \(jobId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func resume(jobId: String) {
        do {
            guard var task = try Database.shared.getAgentTask(id: jobId) else { return }
            task.status = .active
            try Database.shared.updateAgentTask(task)
        } catch {
            Log.scheduler.error("Failed to resume job \(jobId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
