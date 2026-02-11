import Foundation
import SQLite

struct AgentTaskStore: DatabaseStore {
    let database: Database

    // MARK: - Table Definitions

    private static let agentTasks = Table("agent_tasks")
    private static let agentTaskResults = Table("agent_task_results")

    // agent_tasks columns
    private static let id = Expression<String>("id")
    private static let name = Expression<String>("name")
    private static let prompt = Expression<String>("prompt")
    private static let triggerType = Expression<String>("trigger_type")
    private static let triggerConfig = Expression<String>("trigger_config")
    private static let contextNeeds = Expression<String>("context_needs")
    private static let allowedActions = Expression<String>("allowed_actions")
    private static let status = Expression<String>("status")
    private static let createdBy = Expression<String>("created_by")
    private static let createdAt = Expression<Double>("created_at")
    private static let lastRun = Expression<Double?>("last_run")
    private static let nextRun = Expression<Double?>("next_run")
    private static let runCount = Expression<Int>("run_count")
    private static let maxRuns = Expression<Int?>("max_runs")

    // agent_task_results columns
    private static let resultId = Expression<String>("id")
    private static let taskId = Expression<String>("task_id")
    private static let timestamp = Expression<Double>("timestamp")
    private static let output = Expression<String>("output")
    private static let actionsProposed = Expression<String>("actions_proposed")
    private static let actionsExecuted = Expression<String>("actions_executed")
    private static let costUsd = Expression<Double?>("cost_usd")
    private static let resultStatus = Expression<String>("status")
    private static let durationMs = Expression<Int?>("duration_ms")

    // MARK: - Table Creation

    static func createTables(in db: Connection) throws {
        try db.run(agentTasks.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(name)
            t.column(prompt)
            t.column(triggerType)
            t.column(triggerConfig, defaultValue: "{}")
            t.column(contextNeeds, defaultValue: "[]")
            t.column(allowedActions, defaultValue: "[]")
            t.column(status, defaultValue: "active")
            t.column(createdBy, defaultValue: "chat")
            t.column(createdAt)
            t.column(lastRun)
            t.column(nextRun)
            t.column(runCount, defaultValue: 0)
            t.column(maxRuns)
        })

        try db.run(agentTaskResults.create(ifNotExists: true) { t in
            t.column(resultId, primaryKey: true)
            t.column(taskId)
            t.column(timestamp)
            t.column(output)
            t.column(actionsProposed, defaultValue: "[]")
            t.column(actionsExecuted, defaultValue: "[]")
            t.column(costUsd)
            t.column(resultStatus, defaultValue: "success")
            t.column(durationMs)
        })
    }

    // MARK: - Agent Task CRUD

    func createAgentTask(_ task: AgentTask) throws {
        let contextNeedsJSON = encodeJSON(task.contextNeeds.map(\.rawValue))
        let actionsJSON = encodeJSON(task.allowedActions.map(\.rawValue))

        try perform { db in
            try db.run(Self.agentTasks.insert(or: .replace,
                Self.id <- task.id,
                Self.name <- task.name,
                Self.prompt <- task.prompt,
                Self.triggerType <- task.triggerType.rawValue,
                Self.triggerConfig <- task.triggerConfig.json,
                Self.contextNeeds <- contextNeedsJSON,
                Self.allowedActions <- actionsJSON,
                Self.status <- task.status.rawValue,
                Self.createdBy <- task.createdBy.rawValue,
                Self.createdAt <- task.createdAt.timeIntervalSince1970,
                Self.lastRun <- task.lastRun?.timeIntervalSince1970,
                Self.nextRun <- task.nextRun?.timeIntervalSince1970,
                Self.runCount <- task.runCount,
                Self.maxRuns <- task.maxRuns
            ))
        }
    }

    func getAgentTask(id taskId: String) throws -> AgentTask? {
        try perform { db in
            guard let row = try db.pluck(Self.agentTasks.filter(Self.id == taskId)) else {
                return nil
            }
            return parseAgentTask(from: row)
        }
    }

    func getActiveAgentTasks() throws -> [AgentTask] {
        try perform { db in
            try db.prepare(
                Self.agentTasks.filter(Self.status == AgentTask.Status.active.rawValue)
                    .order(Self.nextRun)
            ).compactMap(parseAgentTask)
        }
    }

    func getAllAgentTasks() throws -> [AgentTask] {
        try perform { db in
            try db.prepare(
                Self.agentTasks.order(Self.createdAt.desc)
            ).compactMap(parseAgentTask)
        }
    }

    func getDueTasks() throws -> [AgentTask] {
        let now = Date().timeIntervalSince1970
        return try perform { db in
            try db.prepare(
                Self.agentTasks
                    .filter(Self.status == AgentTask.Status.active.rawValue)
                    .filter(Self.nextRun != nil && Self.nextRun <= now)
                    .order(Self.nextRun)
            ).compactMap(parseAgentTask)
        }
    }

    func getCheckinTasks(phase: String) throws -> [AgentTask] {
        try perform { db in
            try db.prepare(
                Self.agentTasks
                    .filter(Self.status == AgentTask.Status.active.rawValue)
                    .filter(Self.triggerType == AgentTask.TriggerType.checkin.rawValue)
            ).compactMap(parseAgentTask).filter { task in
                task.triggerConfig.checkinPhase == phase
            }
        }
    }

    func updateAgentTask(_ task: AgentTask) throws {
        let contextNeedsJSON = encodeJSON(task.contextNeeds.map(\.rawValue))
        let actionsJSON = encodeJSON(task.allowedActions.map(\.rawValue))

        try perform { db in
            try db.run(Self.agentTasks.filter(Self.id == task.id).update(
                Self.name <- task.name,
                Self.prompt <- task.prompt,
                Self.triggerType <- task.triggerType.rawValue,
                Self.triggerConfig <- task.triggerConfig.json,
                Self.contextNeeds <- contextNeedsJSON,
                Self.allowedActions <- actionsJSON,
                Self.status <- task.status.rawValue,
                Self.lastRun <- task.lastRun?.timeIntervalSince1970,
                Self.nextRun <- task.nextRun?.timeIntervalSince1970,
                Self.runCount <- task.runCount,
                Self.maxRuns <- task.maxRuns
            ))
        }
    }

    func updateTaskAfterRun(id taskId: String, lastRun: Date, nextRun: Date?, runCount: Int, status: AgentTask.Status) throws {
        try perform { db in
            try db.run(Self.agentTasks.filter(Self.id == taskId).update(
                Self.lastRun <- lastRun.timeIntervalSince1970,
                Self.nextRun <- nextRun?.timeIntervalSince1970,
                Self.runCount <- runCount,
                Self.status <- status.rawValue
            ))
        }
    }

    func deleteAgentTask(id taskId: String) throws {
        try perform { db in
            try db.run(Self.agentTasks.filter(Self.id == taskId).delete())
        }
    }

    // MARK: - Agent Task Results

    func saveResult(_ result: AgentTaskResult) throws {
        let proposedJSON = encodeJSON(result.actionsProposed)
        let executedJSON = encodeJSON(result.actionsExecuted)

        try perform { db in
            try db.run(Self.agentTaskResults.insert(or: .replace,
                Self.resultId <- result.id,
                Self.taskId <- result.taskId,
                Self.timestamp <- result.timestamp.timeIntervalSince1970,
                Self.output <- result.output,
                Self.actionsProposed <- proposedJSON,
                Self.actionsExecuted <- executedJSON,
                Self.costUsd <- result.costUsd,
                Self.resultStatus <- result.status.rawValue,
                Self.durationMs <- result.durationMs
            ))
        }
    }

    func getRecentResults(limit: Int = 20) throws -> [AgentTaskResult] {
        try perform { db in
            try db.prepare(
                Self.agentTaskResults
                    .order(Self.timestamp.desc)
                    .limit(limit)
            ).compactMap(parseAgentTaskResult)
        }
    }

    func getResultsForTask(id taskId: String, limit: Int = 10) throws -> [AgentTaskResult] {
        try perform { db in
            try db.prepare(
                Self.agentTaskResults
                    .filter(Self.taskId == taskId)
                    .order(Self.timestamp.desc)
                    .limit(limit)
            ).compactMap(parseAgentTaskResult)
        }
    }

    func getPendingApprovalResults() throws -> [AgentTaskResult] {
        try perform { db in
            try db.prepare(
                Self.agentTaskResults
                    .filter(Self.resultStatus == AgentTaskResult.ResultStatus.pendingApproval.rawValue)
                    .order(Self.timestamp.desc)
            ).compactMap(parseAgentTaskResult)
        }
    }

    // MARK: - Parsing

    private func parseAgentTask(from row: Row) -> AgentTask {
        let contextNeedsArray = decodeJSON([String].self, from: row[Self.contextNeeds]) ?? []
        let actionsArray = decodeJSON([String].self, from: row[Self.allowedActions]) ?? []

        return AgentTask(
            id: row[Self.id],
            name: row[Self.name],
            prompt: row[Self.prompt],
            triggerType: AgentTask.TriggerType(rawValue: row[Self.triggerType]) ?? .manual,
            triggerConfig: TriggerConfig.fromJSON(row[Self.triggerConfig]),
            contextNeeds: contextNeedsArray.compactMap(AgentContextNeed.init(rawValue:)),
            allowedActions: actionsArray.compactMap(AssistantActionRequest.ActionType.init(rawValue:)),
            status: AgentTask.Status(rawValue: row[Self.status]) ?? .active,
            createdBy: AgentTask.CreatedBy(rawValue: row[Self.createdBy]) ?? .chat,
            createdAt: Date(timeIntervalSince1970: row[Self.createdAt]),
            lastRun: row[Self.lastRun].map(Date.init(timeIntervalSince1970:)),
            nextRun: row[Self.nextRun].map(Date.init(timeIntervalSince1970:)),
            runCount: row[Self.runCount],
            maxRuns: row[Self.maxRuns]
        )
    }

    private func parseAgentTaskResult(from row: Row) -> AgentTaskResult {
        let proposed = decodeJSON([AssistantActionRequest].self, from: row[Self.actionsProposed]) ?? []
        let executed = decodeJSON([ExecutedAction].self, from: row[Self.actionsExecuted]) ?? []

        return AgentTaskResult(
            id: row[Self.resultId],
            taskId: row[Self.taskId],
            timestamp: Date(timeIntervalSince1970: row[Self.timestamp]),
            output: row[Self.output],
            actionsProposed: proposed,
            actionsExecuted: executed,
            costUsd: row[Self.costUsd],
            status: AgentTaskResult.ResultStatus(rawValue: row[Self.resultStatus]) ?? .success,
            durationMs: row[Self.durationMs]
        )
    }

    // MARK: - JSON Helpers

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
