import Foundation
import GRDB

struct SessionRepository: Sendable {
    let db: GRDBDatabase

    // MARK: - Messages

    func saveMessage(_ message: ChatMessage, forSession session: String? = nil) throws {
        try db.write { db in
            let metadata = MessageMetadata(
                cost: message.cost,
                model: message.model,
                contextUsed: message.contextUsed,
                richContent: message.richContent,
                interactionState: message.interactionState
            )
            let metadataJson = Self.encodeJSON(metadata)

            let uiEnvelope = MessageUIEnvelope(
                uiElements: message.uiElements,
                interactionState: message.interactionState
            )
            let uiJson = message.uiElements.isEmpty ? nil : Self.encodeJSON(uiEnvelope)

            let toolCallsJson: String?
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                toolCallsJson = Self.encodeJSON(toolCalls)
            } else {
                toolCallsJson = nil
            }

            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO messages
                    (id, role, content, timestamp, session_id, metadata_json, ui_json, tool_calls_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    message.id.uuidString,
                    message.role.rawValue,
                    message.content,
                    message.timestamp.timeIntervalSince1970,
                    session,
                    metadataJson,
                    uiJson,
                    toolCallsJson,
                ]
            )
        }
    }

    func loadRecentMessages(limit: Int = 50, forSession session: String? = nil) throws -> [ChatMessage] {
        try db.read { db in
            let sql: String
            let args: StatementArguments

            if let session {
                sql = """
                    SELECT * FROM messages WHERE session_id = ?
                    ORDER BY timestamp DESC LIMIT ?
                    """
                args = [session, limit]
            } else {
                sql = """
                    SELECT * FROM messages WHERE session_id IS NULL
                    ORDER BY timestamp DESC LIMIT ?
                    """
                args = [limit]
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.reversed().compactMap { Self.parseMessage(from: $0) }
        }
    }

    func clearMessages(forSession session: String? = nil) throws {
        try db.write { db in
            if let session {
                try db.execute(sql: "DELETE FROM messages WHERE session_id = ?", arguments: [session])
            } else {
                try db.execute(sql: "DELETE FROM messages WHERE session_id IS NULL")
            }
        }
    }

    func associateOrphanedMessages(withSession session: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE messages SET session_id = ? WHERE session_id IS NULL",
                arguments: [session]
            )
        }
    }

    // MARK: - Sessions

    func saveSession(id sessionId: String, title: String) throws {
        try db.write { db in
            let now = Date().timeIntervalSince1970
            try db.execute(
                sql: """
                    INSERT INTO sessions (id, created_at, last_used, title)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET last_used = ?, title = ?
                    """,
                arguments: [sessionId, now, now, title, now, title]
            )
        }
    }

    func getRecentSessions(limit: Int = 20) throws -> [Session] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM sessions ORDER BY last_used DESC LIMIT ?",
                arguments: [limit]
            )
            return rows.map { row in
                Session(
                    id: row["id"],
                    createdAt: Date(timeIntervalSince1970: row["created_at"]),
                    lastUsed: Date(timeIntervalSince1970: row["last_used"]),
                    title: row["title"]
                )
            }
        }
    }

    func deleteSession(id sessionId: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM messages WHERE session_id = ?", arguments: [sessionId])
            try db.execute(sql: "DELETE FROM cost_log WHERE session_id = ?", arguments: [sessionId])
            try db.execute(sql: "DELETE FROM sessions WHERE id = ?", arguments: [sessionId])
        }
    }

    // MARK: - Cost Tracking

    func logCost(amount: Double, sessionId: String?) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO cost_log (timestamp, amount_usd, session_id) VALUES (?, ?, ?)",
                arguments: [Date().timeIntervalSince1970, amount, sessionId]
            )
        }
    }

    func getTotalCost(since date: Date) throws -> Double {
        try db.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(amount_usd), 0) FROM cost_log WHERE timestamp >= ?",
                arguments: [date.timeIntervalSince1970]
            ) ?? 0
        }
    }

    func getDailyCost() throws -> Double {
        try getTotalCost(since: Calendar.current.startOfDay(for: Date()))
    }

    func getWeeklyCost() throws -> Double {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return try getTotalCost(since: weekStart)
    }

    func getMonthlyCost() throws -> Double {
        let monthStart = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        return try getTotalCost(since: monthStart)
    }

    func getCostHistory(days: Int = 30) throws -> [(date: Date, amount: Double)] {
        try db.read { db in
            let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT date(timestamp, 'unixepoch', 'localtime') as day, SUM(amount_usd) as total
                    FROM cost_log WHERE timestamp >= ?
                    GROUP BY day ORDER BY day
                    """,
                arguments: [since.timeIntervalSince1970]
            )
            return rows.compactMap { row -> (date: Date, amount: Double)? in
                guard let dayStr: String = row["day"],
                      let date = SharedDateFormatters.databaseDate.date(from: dayStr)
                else { return nil }
                return (date: date, amount: row["total"])
            }
        }
    }

    // MARK: - Private

    private struct MessageMetadata: Codable {
        let cost: Double?
        let model: String?
        let contextUsed: MessageContext?
        let richContent: RichContent?
        let interactionState: ChatInteractionState?
    }

    private struct MessageUIEnvelope: Codable {
        let uiElements: [ChatUIElement]
        let interactionState: ChatInteractionState?
    }

    private static func parseMessage(from row: Row) -> ChatMessage? {
        guard let idStr: String = row["id"],
              let id = UUID(uuidString: idStr),
              let roleStr: String = row["role"],
              let role = ChatMessage.Role(rawValue: roleStr)
        else { return nil }

        var cost: Double?
        var model: String?
        var contextUsed: MessageContext?
        var richContent: RichContent?
        var interactionState: ChatInteractionState?

        if let metaJson: String = row["metadata_json"] {
            let meta = decodeJSON(MessageMetadata.self, from: metaJson)
            cost = meta?.cost
            model = meta?.model
            contextUsed = meta?.contextUsed
            richContent = meta?.richContent
            interactionState = meta?.interactionState
        }

        var uiElements: [ChatUIElement] = []
        if let uiJson: String = row["ui_json"] {
            if let envelope = decodeJSON(MessageUIEnvelope.self, from: uiJson) {
                uiElements = envelope.uiElements
                if interactionState == nil {
                    interactionState = envelope.interactionState
                }
            }
        }

        var toolCalls: [ClaudeService.ToolCallInfo]?
        if let tcJson: String = row["tool_calls_json"] {
            toolCalls = decodeJSON([ClaudeService.ToolCallInfo].self, from: tcJson)
        }

        return ChatMessage(
            id: id,
            role: role,
            content: row["content"],
            timestamp: Date(timeIntervalSince1970: row["timestamp"]),
            contextUsed: contextUsed,
            cost: cost,
            model: model,
            toolCalls: toolCalls,
            richContent: richContent,
            uiElements: uiElements,
            interactionState: interactionState
        )
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
