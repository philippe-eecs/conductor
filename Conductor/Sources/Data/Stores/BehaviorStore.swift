import Foundation
import SQLite

struct BehaviorStore: DatabaseStore {
    let database: Database

    // MARK: - Table Definition

    private static let behaviorEvents = Table("behavior_events")

    private static let id = Expression<String>("id")
    private static let eventType = Expression<String>("event_type")
    private static let entityId = Expression<String?>("entity_id")
    private static let metadataJson = Expression<String>("metadata_json")
    private static let hourOfDay = Expression<Int>("hour_of_day")
    private static let dayOfWeek = Expression<Int>("day_of_week")
    private static let createdAt = Expression<Double>("created_at")

    // MARK: - Table Creation

    static func createTables(in db: Connection) throws {
        try db.run(behaviorEvents.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(eventType)
            t.column(entityId)
            t.column(metadataJson, defaultValue: "{}")
            t.column(hourOfDay)
            t.column(dayOfWeek)
            t.column(createdAt)
        })
    }

    // MARK: - Record Events

    func recordEvent(type: BehaviorEventType, entityId: String? = nil, metadata: [String: String] = [:]) throws {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        let metaJSON: String
        if let data = try? JSONEncoder().encode(metadata),
           let str = String(data: data, encoding: .utf8) {
            metaJSON = str
        } else {
            metaJSON = "{}"
        }

        try perform { db in
            try db.run(Self.behaviorEvents.insert(
                Self.id <- UUID().uuidString,
                Self.eventType <- type.rawValue,
                Self.entityId <- entityId,
                Self.metadataJson <- metaJSON,
                Self.hourOfDay <- hour,
                Self.dayOfWeek <- weekday,
                Self.createdAt <- now.timeIntervalSince1970
            ))
        }
    }

    // MARK: - Query Events

    func getEvents(type: BehaviorEventType? = nil, since: Date? = nil, limit: Int = 100) throws -> [BehaviorEvent] {
        try perform { db in
            var query = Self.behaviorEvents.order(Self.createdAt.desc).limit(limit)
            if let type {
                query = query.filter(Self.eventType == type.rawValue)
            }
            if let since {
                query = query.filter(Self.createdAt >= since.timeIntervalSince1970)
            }
            return try db.prepare(query).map(parseBehaviorEvent)
        }
    }

    func getEventCountByHour(type: BehaviorEventType, days: Int = 30) throws -> [Int: Int] {
        let since = Date().addingTimeInterval(Double(-days * 86400))
        return try perform { db in
            var counts: [Int: Int] = [:]
            let query = Self.behaviorEvents
                .filter(Self.eventType == type.rawValue && Self.createdAt >= since.timeIntervalSince1970)
                .select(Self.hourOfDay)
            for row in try db.prepare(query) {
                let hour = row[Self.hourOfDay]
                counts[hour, default: 0] += 1
            }
            return counts
        }
    }

    func getEventCountByDayOfWeek(type: BehaviorEventType, days: Int = 30) throws -> [Int: Int] {
        let since = Date().addingTimeInterval(Double(-days * 86400))
        return try perform { db in
            var counts: [Int: Int] = [:]
            let query = Self.behaviorEvents
                .filter(Self.eventType == type.rawValue && Self.createdAt >= since.timeIntervalSince1970)
                .select(Self.dayOfWeek)
            for row in try db.prepare(query) {
                let day = row[Self.dayOfWeek]
                counts[day, default: 0] += 1
            }
            return counts
        }
    }

    func getTotalCount(type: BehaviorEventType, since: Date) throws -> Int {
        try perform { db in
            try db.scalar(
                Self.behaviorEvents
                    .filter(Self.eventType == type.rawValue && Self.createdAt >= since.timeIntervalSince1970)
                    .count
            )
        }
    }

    // MARK: - Parsing

    private func parseBehaviorEvent(from row: Row) -> BehaviorEvent {
        let metaJSON = row[Self.metadataJson]
        let metadata: [String: String]
        if let data = metaJSON.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
            metadata = parsed
        } else {
            metadata = [:]
        }

        return BehaviorEvent(
            id: row[Self.id],
            eventType: BehaviorEventType(rawValue: row[Self.eventType]) ?? .taskCompleted,
            entityId: row[Self.entityId],
            metadata: metadata,
            hourOfDay: row[Self.hourOfDay],
            dayOfWeek: row[Self.dayOfWeek],
            createdAt: Date(timeIntervalSince1970: row[Self.createdAt])
        )
    }
}

// MARK: - Models

enum BehaviorEventType: String, Codable, CaseIterable {
    case taskCompleted = "task_completed"
    case goalCompleted = "goal_completed"
    case goalRolled = "goal_rolled"
    case actionApproved = "action_approved"
    case actionRejected = "action_rejected"
    case taskDeferred = "task_deferred"
    case emailDismissed = "email_dismissed"
    case emailActioned = "email_actioned"
    case checkinCompleted = "checkin_completed"
    case agentTaskCreated = "agent_task_created"
}

struct BehaviorEvent: Identifiable {
    let id: String
    let eventType: BehaviorEventType
    let entityId: String?
    let metadata: [String: String]
    let hourOfDay: Int
    let dayOfWeek: Int
    let createdAt: Date
}
