import Foundation
import SQLite

struct ProductivityStatsStore: DatabaseStore {
    let database: Database

    private let table = Table("productivity_stats")
    private let id = Expression<String>("id")
    private let date = Expression<String>("date")
    private let goalsCompleted = Expression<Int>("goals_completed")
    private let goalsTotal = Expression<Int>("goals_total")
    private let meetingsCount = Expression<Int>("meetings_count")
    private let meetingsHours = Expression<Double>("meetings_hours")
    private let focusHours = Expression<Double>("focus_hours")
    private let overdueCount = Expression<Int>("overdue_count")
    private let generatedAt = Expression<Double>("generated_at")

    static func createTables(in db: Connection) throws {
        let table = Table("productivity_stats")
        let id = Expression<String>("id")
        let date = Expression<String>("date")
        let goalsCompleted = Expression<Int>("goals_completed")
        let goalsTotal = Expression<Int>("goals_total")
        let meetingsCount = Expression<Int>("meetings_count")
        let meetingsHours = Expression<Double>("meetings_hours")
        let focusHours = Expression<Double>("focus_hours")
        let overdueCount = Expression<Int>("overdue_count")
        let generatedAt = Expression<Double>("generated_at")

        try db.run(table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(date)
            t.column(goalsCompleted)
            t.column(goalsTotal)
            t.column(meetingsCount)
            t.column(meetingsHours)
            t.column(focusHours)
            t.column(overdueCount)
            t.column(generatedAt)
        })
        try db.run(table.createIndex(date, ifNotExists: true))
    }

    func saveProductivityStats(_ stats: ProductivityStats) throws {
        try perform { db in
            let insert = table.insert(or: .replace,
                id <- stats.id,
                date <- stats.date,
                goalsCompleted <- stats.goalsCompleted,
                goalsTotal <- stats.goalsTotal,
                meetingsCount <- stats.meetingsCount,
                meetingsHours <- stats.meetingsHours,
                focusHours <- stats.focusHours,
                overdueCount <- stats.overdueCount,
                generatedAt <- stats.generatedAt.timeIntervalSince1970
            )
            try db.run(insert)
        }
    }

    func getProductivityStats(for dateValue: String) throws -> ProductivityStats? {
        try perform { db in
            let query = table.filter(date == dateValue)
            if let row = try db.pluck(query) {
                return ProductivityStats(
                    id: row[id],
                    date: row[date],
                    goalsCompleted: row[goalsCompleted],
                    goalsTotal: row[goalsTotal],
                    meetingsCount: row[meetingsCount],
                    meetingsHours: row[meetingsHours],
                    focusHours: row[focusHours],
                    overdueCount: row[overdueCount],
                    generatedAt: Date(timeIntervalSince1970: row[generatedAt])
                )
            }
            return nil
        }
    }

    func getProductivityStatsRange(from startDate: String, to endDate: String) throws -> [ProductivityStats] {
        try perform { db in
            let query = table
                .filter(date >= startDate && date <= endDate)
                .order(date.asc)

            var stats: [ProductivityStats] = []
            for row in try db.prepare(query) {
                stats.append(ProductivityStats(
                    id: row[id],
                    date: row[date],
                    goalsCompleted: row[goalsCompleted],
                    goalsTotal: row[goalsTotal],
                    meetingsCount: row[meetingsCount],
                    meetingsHours: row[meetingsHours],
                    focusHours: row[focusHours],
                    overdueCount: row[overdueCount],
                    generatedAt: Date(timeIntervalSince1970: row[generatedAt])
                ))
            }
            return stats
        }
    }

    func getRecentProductivityStats(days: Int = 30) throws -> [ProductivityStats] {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!

        return try getProductivityStatsRange(
            from: SharedDateFormatters.databaseDate.string(from: startDate),
            to: SharedDateFormatters.databaseDate.string(from: endDate)
        )
    }
}

