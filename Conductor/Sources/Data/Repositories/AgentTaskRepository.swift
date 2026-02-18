import Foundation
import GRDB

struct AgentTaskRepository: Sendable {
    let db: GRDBDatabase

    // MARK: - Agent Tasks

    func createAgentTask(_ task: AgentTask) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO agent_tasks
                    (id, name, prompt, trigger_type, trigger_config, context_needs,
                     allowed_actions, status, created_by, created_at, last_run, next_run,
                     run_count, max_runs, linked_todo_task_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    task.id, task.name, task.prompt,
                    task.triggerType.rawValue,
                    Self.encodeJSON(task.triggerConfig) ?? "{}",
                    Self.encodeJSON(task.contextNeeds) ?? "[]",
                    Self.encodeJSON(task.allowedActions) ?? "[]",
                    task.status.rawValue,
                    task.createdBy.rawValue,
                    task.createdAt.timeIntervalSince1970,
                    task.lastRun?.timeIntervalSince1970,
                    task.nextRun?.timeIntervalSince1970,
                    task.runCount,
                    task.maxRuns,
                    task.linkedTodoTaskId,
                ]
            )
        }
    }

    func getAgentTask(id: String) throws -> AgentTask? {
        try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM agent_tasks WHERE id = ?", arguments: [id])
            else { return nil }
            return Self.parseAgentTask(from: row)
        }
    }

    func getActiveAgentTasks() throws -> [AgentTask] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM agent_tasks WHERE status = 'active' ORDER BY created_at DESC"
            ).map { Self.parseAgentTask(from: $0) }
        }
    }

    func getAllAgentTasks() throws -> [AgentTask] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM agent_tasks ORDER BY created_at DESC"
            ).map { Self.parseAgentTask(from: $0) }
        }
    }

    func getDueTasks() throws -> [AgentTask] {
        try db.read { db in
            let now = Date().timeIntervalSince1970
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM agent_tasks
                    WHERE status = 'active' AND next_run IS NOT NULL AND next_run <= ?
                    ORDER BY next_run ASC
                    """,
                arguments: [now]
            )
            return rows.map { Self.parseAgentTask(from: $0) }
        }
    }

    func getCheckinTasks(phase: String) throws -> [AgentTask] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM agent_tasks
                    WHERE status = 'active' AND trigger_type = 'checkin'
                    ORDER BY created_at ASC
                    """
            )
            return rows.map { Self.parseAgentTask(from: $0) }
                .filter { $0.triggerConfig.checkinPhase == phase }
        }
    }

    func updateAgentTask(_ task: AgentTask) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE agent_tasks SET
                    name = ?, prompt = ?, trigger_type = ?, trigger_config = ?,
                    context_needs = ?, allowed_actions = ?, status = ?,
                    last_run = ?, next_run = ?, run_count = ?, max_runs = ?,
                    linked_todo_task_id = ?
                    WHERE id = ?
                    """,
                arguments: [
                    task.name, task.prompt,
                    task.triggerType.rawValue,
                    Self.encodeJSON(task.triggerConfig) ?? "{}",
                    Self.encodeJSON(task.contextNeeds) ?? "[]",
                    Self.encodeJSON(task.allowedActions) ?? "[]",
                    task.status.rawValue,
                    task.lastRun?.timeIntervalSince1970,
                    task.nextRun?.timeIntervalSince1970,
                    task.runCount,
                    task.maxRuns,
                    task.linkedTodoTaskId,
                    task.id,
                ]
            )
        }
    }

    func deleteAgentTask(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM agent_task_results WHERE task_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM agent_tasks WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Agent Task Results

    func saveResult(_ result: AgentTaskResult) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO agent_task_results
                    (id, task_id, timestamp, output, actions_proposed, actions_executed,
                     cost_usd, status, duration_ms)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    result.id,
                    result.taskId,
                    result.timestamp.timeIntervalSince1970,
                    result.output,
                    Self.encodeJSON(result.actionsProposed) ?? "[]",
                    Self.encodeJSON(result.actionsExecuted) ?? "[]",
                    result.costUsd,
                    result.status.rawValue,
                    result.durationMs,
                ]
            )
        }
    }

    func getRecentResults(limit: Int = 20) throws -> [AgentTaskResult] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM agent_task_results ORDER BY timestamp DESC LIMIT ?",
                arguments: [limit]
            ).map { Self.parseResult(from: $0) }
        }
    }

    func getPendingApprovalResults() throws -> [AgentTaskResult] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM agent_task_results WHERE status = 'pending_approval' ORDER BY timestamp DESC"
            ).map { Self.parseResult(from: $0) }
        }
    }

    // MARK: - Parsing

    private static func parseAgentTask(from row: Row) -> AgentTask {
        let lastRunVal: Double? = row["last_run"]
        let nextRunVal: Double? = row["next_run"]

        let triggerConfig: TriggerConfig
        if let configJson: String = row["trigger_config"] {
            triggerConfig = TriggerConfig.fromJSON(configJson)
        } else {
            triggerConfig = TriggerConfig()
        }

        let contextNeeds: [AgentContextNeed] = Self.decodeJSON(
            [AgentContextNeed].self, from: row["context_needs"] as String? ?? "[]"
        ) ?? []

        let allowedActions: [AssistantActionRequest.ActionType] = Self.decodeJSON(
            [AssistantActionRequest.ActionType].self, from: row["allowed_actions"] as String? ?? "[]"
        ) ?? []

        return AgentTask(
            id: row["id"],
            name: row["name"],
            prompt: row["prompt"],
            triggerType: AgentTask.TriggerType(rawValue: row["trigger_type"]) ?? .manual,
            triggerConfig: triggerConfig,
            contextNeeds: contextNeeds,
            allowedActions: allowedActions,
            status: AgentTask.Status(rawValue: row["status"]) ?? .active,
            createdBy: AgentTask.CreatedBy(rawValue: row["created_by"]) ?? .chat,
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            lastRun: lastRunVal.map { Date(timeIntervalSince1970: $0) },
            nextRun: nextRunVal.map { Date(timeIntervalSince1970: $0) },
            runCount: row["run_count"],
            maxRuns: row["max_runs"],
            linkedTodoTaskId: row["linked_todo_task_id"]
        )
    }

    private static func parseResult(from row: Row) -> AgentTaskResult {
        let actionsProposed: [AssistantActionRequest] = Self.decodeJSON(
            [AssistantActionRequest].self, from: row["actions_proposed"] as String? ?? "[]"
        ) ?? []

        let actionsExecuted: [ExecutedAction] = Self.decodeJSON(
            [ExecutedAction].self, from: row["actions_executed"] as String? ?? "[]"
        ) ?? []

        return AgentTaskResult(
            id: row["id"],
            taskId: row["task_id"],
            timestamp: Date(timeIntervalSince1970: row["timestamp"]),
            output: row["output"],
            actionsProposed: actionsProposed,
            actionsExecuted: actionsExecuted,
            costUsd: row["cost_usd"],
            status: AgentTaskResult.ResultStatus(rawValue: row["status"]) ?? .success,
            durationMs: row["duration_ms"]
        )
    }

    private static func encodeJSON<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
