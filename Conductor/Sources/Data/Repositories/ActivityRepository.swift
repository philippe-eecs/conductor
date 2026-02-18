import Foundation
import GRDB

struct ActivityRepository: Sendable {
    let db: GRDBDatabase

    // MARK: - Behavior Events

    func recordBehaviorEvent(type: BehaviorEventType, entityId: String? = nil, metadata: [String: String] = [:]) throws {
        try db.write { db in
            let now = Date()
            let calendar = Calendar.current
            let metadataJson = Self.encodeJSON(metadata) ?? "{}"

            try db.execute(
                sql: """
                    INSERT INTO behavior_events
                    (id, event_type, entity_id, metadata_json, hour_of_day, day_of_week, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString,
                    type.rawValue,
                    entityId,
                    metadataJson,
                    calendar.component(.hour, from: now),
                    calendar.component(.weekday, from: now),
                    now.timeIntervalSince1970,
                ]
            )
        }
    }

    func getBehaviorEvents(type: BehaviorEventType? = nil, since: Date? = nil, limit: Int = 100) throws -> [BehaviorEvent] {
        try db.read { db in
            var conditions: [String] = []
            var args: [DatabaseValueConvertible] = []

            if let type {
                conditions.append("event_type = ?")
                args.append(type.rawValue)
            }
            if let since {
                conditions.append("created_at >= ?")
                args.append(since.timeIntervalSince1970)
            }

            let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
            args.append(limit)

            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM behavior_events \(whereClause) ORDER BY created_at DESC LIMIT ?",
                arguments: StatementArguments(args)!
            ).map { Self.parseBehaviorEvent(from: $0) }
        }
    }

    // MARK: - Behavior Analytics

    func getEventCountByHour(type: BehaviorEventType, days: Int) throws -> [Int: Int] {
        try db.read { db in
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT hour_of_day, COUNT(*) as cnt
                    FROM behavior_events
                    WHERE event_type = ? AND created_at >= ?
                    GROUP BY hour_of_day
                    """,
                arguments: [type.rawValue, cutoff]
            )
            var result: [Int: Int] = [:]
            for row in rows {
                let hour: Int = row["hour_of_day"]
                let count: Int = row["cnt"]
                result[hour] = count
            }
            return result
        }
    }

    func getTotalCount(type: BehaviorEventType, since: Date) throws -> Int {
        try db.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT COUNT(*) as cnt FROM behavior_events WHERE event_type = ? AND created_at >= ?",
                arguments: [type.rawValue, since.timeIntervalSince1970]
            )
            return row?["cnt"] ?? 0
        }
    }

    func getEventCountByDayOfWeek(type: BehaviorEventType, days: Int) throws -> [Int: Int] {
        try db.read { db in
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT day_of_week, COUNT(*) as cnt
                    FROM behavior_events
                    WHERE event_type = ? AND created_at >= ?
                    GROUP BY day_of_week
                    """,
                arguments: [type.rawValue, cutoff]
            )
            var result: [Int: Int] = [:]
            for row in rows {
                let day: Int = row["day_of_week"]
                let count: Int = row["cnt"]
                result[day] = count
            }
            return result
        }
    }

    // MARK: - Operation Events

    func saveOperationEvent(_ event: OperationEvent) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO operation_events
                    (id, correlation_id, operation, entity_type, entity_id, source,
                     status, message, payload_json, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    event.id,
                    event.correlationId,
                    event.operation.rawValue,
                    event.entityType,
                    event.entityId,
                    event.source,
                    event.status.rawValue,
                    event.message,
                    Self.encodeJSON(event.payload) ?? "{}",
                    event.createdAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func getRecentOperationEvents(limit: Int = 100) throws -> [OperationEvent] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM operation_events ORDER BY created_at DESC LIMIT ?",
                arguments: [limit]
            ).map { Self.parseOperationEvent(from: $0) }
        }
    }

    func getOperationEvents(
        limit: Int = 100,
        status: OperationStatus? = nil,
        correlationId: String? = nil
    ) throws -> [OperationEvent] {
        try db.read { db in
            var conditions: [String] = []
            var args: [DatabaseValueConvertible] = []

            if let status {
                conditions.append("status = ?")
                args.append(status.rawValue)
            }
            if let correlationId {
                conditions.append("correlation_id = ?")
                args.append(correlationId)
            }

            let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
            args.append(limit)

            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM operation_events \(whereClause) ORDER BY created_at DESC LIMIT ?",
                arguments: StatementArguments(args)!
            ).map { Self.parseOperationEvent(from: $0) }
        }
    }

    // MARK: - Parsing

    private static func parseBehaviorEvent(from row: Row) -> BehaviorEvent {
        let metadata: [String: String] = Self.decodeJSON(
            [String: String].self, from: row["metadata_json"] as String? ?? "{}"
        ) ?? [:]

        return BehaviorEvent(
            id: row["id"],
            eventType: BehaviorEventType(rawValue: row["event_type"]) ?? .taskCompleted,
            entityId: row["entity_id"],
            metadata: metadata,
            hourOfDay: row["hour_of_day"],
            dayOfWeek: row["day_of_week"],
            createdAt: Date(timeIntervalSince1970: row["created_at"])
        )
    }

    private static func parseOperationEvent(from row: Row) -> OperationEvent {
        let payload: [String: String] = Self.decodeJSON(
            [String: String].self, from: row["payload_json"] as String? ?? "{}"
        ) ?? [:]

        return OperationEvent(
            id: row["id"],
            correlationId: row["correlation_id"],
            operation: OperationKind(rawValue: row["operation"]) ?? .created,
            entityType: row["entity_type"],
            entityId: row["entity_id"],
            source: row["source"],
            status: OperationStatus(rawValue: row["status"]) ?? .success,
            message: row["message"],
            payload: payload,
            createdAt: Date(timeIntervalSince1970: row["created_at"])
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
