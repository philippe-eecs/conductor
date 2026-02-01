import Foundation
import SQLite

struct SessionStore: DatabaseStore {
    let database: Database

    // Sessions
    private let sessions = Table("sessions")
    private let sessId = Expression<String>("id")
    private let createdAt = Expression<Double>("created_at")
    private let lastUsed = Expression<Double>("last_used")
    private let title = Expression<String>("title")

    // Messages
    private let messages = Table("messages")
    private let messageId = Expression<String>("id")
    private let role = Expression<String>("role")
    private let content = Expression<String>("content")
    private let timestamp = Expression<Double>("timestamp")
    private let sessionId = Expression<String?>("session_id")

    // Cost log (for cascade delete)
    private let costLog = Table("cost_log")
    private let costSessionId = Expression<String?>("session_id")

    static func createTables(in db: Connection) throws {
        // Messages table
        do {
            let messages = Table("messages")
            let id = Expression<String>("id")
            let role = Expression<String>("role")
            let content = Expression<String>("content")
            let timestamp = Expression<Double>("timestamp")
            let sessionId = Expression<String?>("session_id")

            try db.run(messages.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(role)
                t.column(content)
                t.column(timestamp)
                t.column(sessionId)
            })
            try db.run(messages.createIndex(timestamp, ifNotExists: true))
            try db.run(messages.createIndex(sessionId, timestamp, ifNotExists: true))
        }

        // Sessions table
        do {
            let sessions = Table("sessions")
            let id = Expression<String>("id")
            let createdAt = Expression<Double>("created_at")
            let lastUsed = Expression<Double>("last_used")
            let title = Expression<String>("title")

            try db.run(sessions.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(createdAt)
                t.column(lastUsed)
                t.column(title)
            })
            try db.run(sessions.createIndex(lastUsed, ifNotExists: true))
        }
    }

    // MARK: - Messages

    func saveMessage(_ message: ChatMessage, forSession session: String? = nil) throws {
        try perform { db in
            let insert = messages.insert(or: .replace,
                messageId <- message.id.uuidString,
                role <- message.role.rawValue,
                content <- message.content,
                timestamp <- message.timestamp.timeIntervalSince1970,
                sessionId <- session
            )
            try db.run(insert)
        }
    }

    func loadRecentMessages(limit: Int = 50, forSession session: String? = nil) throws -> [ChatMessage] {
        try perform { db in
            let query: SQLite.Table
            if let session {
                query = messages.filter(sessionId == session).order(timestamp.desc).limit(limit)
            } else {
                query = messages.order(timestamp.desc).limit(limit)
            }

            var result: [ChatMessage] = []
            for row in try db.prepare(query) {
                if let messageRole = ChatMessage.Role(rawValue: row[role]),
                   let uuid = UUID(uuidString: row[messageId]) {
                    result.append(ChatMessage(
                        id: uuid,
                        role: messageRole,
                        content: row[content],
                        timestamp: Date(timeIntervalSince1970: row[timestamp])
                    ))
                }
            }

            return result.reversed()
        }
    }

    func clearMessages(forSession session: String? = nil) throws {
        try perform { db in
            if let session {
                try db.run(messages.filter(sessionId == session).delete())
            } else {
                try db.run(messages.delete())
            }
        }
    }

    func associateOrphanedMessages(withSession session: String) throws {
        try perform { db in
            let oneMinuteAgo = Date().addingTimeInterval(-60).timeIntervalSince1970
            let orphaned = messages
                .filter(sessionId == nil)
                .filter(timestamp >= oneMinuteAgo)
            try db.run(orphaned.update(sessionId <- session))
        }
    }

    // MARK: - Sessions

    func saveSession(id sessionIdValue: String, title titleValue: String) throws {
        try perform { db in
            let now = Date().timeIntervalSince1970

            let existing = sessions.filter(sessId == sessionIdValue)
            let updateCount = try db.run(existing.update(
                lastUsed <- now,
                title <- titleValue
            ))

            if updateCount == 0 {
                let insert = sessions.insert(
                    sessId <- sessionIdValue,
                    createdAt <- now,
                    lastUsed <- now,
                    title <- titleValue
                )
                try db.run(insert)
            }
        }
    }

    func getRecentSessions(limit: Int = 20) throws -> [Session] {
        try perform { db in
            let query = sessions.order(lastUsed.desc).limit(limit)
            var result: [Session] = []
            for row in try db.prepare(query) {
                result.append(Session(
                    id: row[sessId],
                    createdAt: Date(timeIntervalSince1970: row[createdAt]),
                    lastUsed: Date(timeIntervalSince1970: row[lastUsed]),
                    title: row[title]
                ))
            }
            return result
        }
    }

    func deleteSession(id sessionIdValue: String) throws {
        try perform { db in
            try db.run(sessions.filter(sessId == sessionIdValue).delete())
            try db.run(messages.filter(sessionId == sessionIdValue).delete())
            try db.run(costLog.filter(costSessionId == sessionIdValue).delete())
        }
    }
}

