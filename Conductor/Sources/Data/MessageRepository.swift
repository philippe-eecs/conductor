import Foundation
import GRDB

struct MessageRepository {
    let db: AppDatabase

    @discardableResult
    func saveMessage(role: String, content: String, sessionId: String?, costUsd: Double? = nil, model: String? = nil) throws -> Message {
        let message = Message(
            role: role, content: content, sessionId: sessionId,
            costUsd: costUsd, model: model, createdAt: Date()
        )
        return try db.dbQueue.write { db in
            try message.inserted(db)
        }
    }

    func messagesForSession(_ sessionId: String) throws -> [Message] {
        try db.dbQueue.read { db in
            try Message.filter(Column("sessionId") == sessionId)
                .order(Column("createdAt"))
                .fetchAll(db)
        }
    }

    func recentMessages(limit: Int = 50) throws -> [Message] {
        try db.dbQueue.read { db in
            try Message.order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
                .reversed()
        }
    }

    func deleteMessagesForSession(_ sessionId: String) throws {
        try db.dbQueue.write { db in
            _ = try Message.filter(Column("sessionId") == sessionId).deleteAll(db)
        }
    }
}
