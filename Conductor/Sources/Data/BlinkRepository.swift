import Foundation
import GRDB

struct BlinkRepository {
    let db: AppDatabase

    @discardableResult
    func logBlink(_ log: BlinkLog) throws -> BlinkLog {
        try db.dbQueue.write { db in
            try log.inserted(db)
        }
    }

    func recentBlinks(limit: Int = 3) throws -> [BlinkLog] {
        try db.dbQueue.read { db in
            try BlinkLog.order(Column("createdAt").desc).limit(limit).fetchAll(db)
        }
    }

    func blinksToday() throws -> [BlinkLog] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return try db.dbQueue.read { db in
            try BlinkLog.filter(Column("createdAt") >= startOfDay)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Agent Runs

    @discardableResult
    func createAgentRun(todoId: Int64?, prompt: String) throws -> AgentRun {
        let run = AgentRun(
            todoId: todoId, prompt: prompt, status: .running,
            output: nil, costUsd: nil, startedAt: Date(), completedAt: nil
        )
        return try db.dbQueue.write { db in
            try run.inserted(db)
        }
    }

    func completeAgentRun(id: Int64, output: String?, costUsd: Double?, status: AgentRunStatus) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE agent_runs SET status = ?, output = ?, costUsd = ?, completedAt = ? WHERE id = ?",
                arguments: [status.rawValue, output, costUsd, Date(), id]
            )
        }
    }

    func runningAgentRuns() throws -> [AgentRun] {
        try db.dbQueue.read { db in
            try AgentRun.filter(Column("status") == AgentRunStatus.running.rawValue).fetchAll(db)
        }
    }

    func agentRunsForTodo(_ todoId: Int64) throws -> [AgentRun] {
        try db.dbQueue.read { db in
            try AgentRun.filter(Column("todoId") == todoId)
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }
    }
}
