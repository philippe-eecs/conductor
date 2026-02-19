import Foundation
import GRDB

// MARK: - Project

struct Project: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var name: String
    var color: String
    var description: String?
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "projects"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Todo

struct Todo: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var title: String
    var priority: Int  // 0=none, 1=low, 2=medium, 3=high
    var dueDate: Date?
    var completed: Bool
    var completedAt: Date?
    var projectId: Int64?
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "todos"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    static let project = belongsTo(Project.self)
    static let deliverables = hasMany(Deliverable.self)
}

// MARK: - Deliverable

enum DeliverableKind: String, Codable {
    case pdf
    case pr
    case markdown
    case code
    case other
}

struct Deliverable: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var kind: DeliverableKind
    var filePath: String?
    var url: String?
    var verified: Bool
    var verifiedAt: Date?
    var projectId: Int64?
    var todoId: Int64?
    var createdAt: Date

    static let databaseTableName = "deliverables"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - BlinkLog

enum BlinkDecision: String, Codable {
    case silent
    case notify
    case agent
}

struct BlinkLog: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var decision: BlinkDecision
    var contextSummary: String
    var notificationTitle: String?
    var notificationBody: String?
    var agentTodoId: Int64?
    var agentPrompt: String?
    var costUsd: Double?
    var createdAt: Date

    static let databaseTableName = "blink_logs"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - AgentRun

enum AgentRunStatus: String, Codable {
    case running
    case completed
    case failed
}

struct AgentRun: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var todoId: Int64?
    var prompt: String
    var status: AgentRunStatus
    var output: String?
    var costUsd: Double?
    var startedAt: Date
    var completedAt: Date?

    static let databaseTableName = "agent_runs"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Message

struct Message: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var role: String  // "user", "assistant", "system"
    var content: String
    var sessionId: String?
    var costUsd: Double?
    var model: String?
    var createdAt: Date

    static let databaseTableName = "messages"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Preference

struct Preference: Codable, FetchableRecord, PersistableRecord {
    var key: String
    var value: String

    static let databaseTableName = "preferences"
}
