import Foundation
import SQLite

struct BriefStore: DatabaseStore {
    let database: Database

    private let table = Table("daily_briefs")
    private let id = Expression<String>("id")
    private let date = Expression<String>("date")
    private let type = Expression<String>("brief_type")
    private let content = Expression<String>("content")
    private let generatedAt = Expression<Double>("generated_at")
    private let readAt = Expression<Double?>("read_at")
    private let dismissed = Expression<Int>("dismissed")

    static func createTables(in db: Connection) throws {
        let table = Table("daily_briefs")
        let id = Expression<String>("id")
        let date = Expression<String>("date")
        let type = Expression<String>("brief_type")
        let content = Expression<String>("content")
        let generatedAt = Expression<Double>("generated_at")
        let readAt = Expression<Double?>("read_at")
        let dismissed = Expression<Int>("dismissed")

        try db.run(table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(date)
            t.column(type)
            t.column(content)
            t.column(generatedAt)
            t.column(readAt)
            t.column(dismissed, defaultValue: 0)
        })
        try db.run(table.createIndex(date, ifNotExists: true))
    }

    func saveDailyBrief(_ brief: DailyBrief) throws {
        try perform { db in
            let insert = table.insert(or: .replace,
                id <- brief.id,
                date <- brief.date,
                type <- brief.briefType.rawValue,
                content <- brief.content,
                generatedAt <- brief.generatedAt.timeIntervalSince1970,
                readAt <- brief.readAt?.timeIntervalSince1970,
                dismissed <- brief.dismissed ? 1 : 0
            )
            try db.run(insert)
        }
    }

    func getDailyBrief(for dateValue: String, type typeValue: DailyBrief.BriefType) throws -> DailyBrief? {
        try perform { db in
            let query = table
                .filter(date == dateValue)
                .filter(type == typeValue.rawValue)

            if let row = try db.pluck(query) {
                return DailyBrief(
                    id: row[id],
                    date: row[date],
                    briefType: DailyBrief.BriefType(rawValue: row[type]) ?? .morning,
                    content: row[content],
                    generatedAt: Date(timeIntervalSince1970: row[generatedAt]),
                    readAt: row[readAt].map { Date(timeIntervalSince1970: $0) },
                    dismissed: row[dismissed] == 1
                )
            }
            return nil
        }
    }

    func markBriefAsRead(id idValue: String) throws {
        try perform { db in
            try db.run(table.filter(id == idValue).update(readAt <- Date().timeIntervalSince1970))
        }
    }

    func markBriefAsDismissed(id idValue: String) throws {
        try perform { db in
            try db.run(table.filter(id == idValue).update(dismissed <- 1))
        }
    }

    func getRecentBriefs(limit: Int = 7) throws -> [DailyBrief] {
        try perform { db in
            let query = table.order(generatedAt.desc).limit(limit)
            var briefs: [DailyBrief] = []
            for row in try db.prepare(query) {
                briefs.append(DailyBrief(
                    id: row[id],
                    date: row[date],
                    briefType: DailyBrief.BriefType(rawValue: row[type]) ?? .morning,
                    content: row[content],
                    generatedAt: Date(timeIntervalSince1970: row[generatedAt]),
                    readAt: row[readAt].map { Date(timeIntervalSince1970: $0) },
                    dismissed: row[dismissed] == 1
                ))
            }
            return briefs
        }
    }
}

