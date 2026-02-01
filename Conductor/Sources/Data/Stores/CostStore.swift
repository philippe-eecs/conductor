import Foundation
import SQLite

struct CostStore: DatabaseStore {
    let database: Database

    private let table = Table("cost_log")
    private let timestamp = Expression<Double>("timestamp")
    private let amountUsd = Expression<Double>("amount_usd")
    private let sessionId = Expression<String?>("session_id")

    static func createTables(in db: Connection) throws {
        let table = Table("cost_log")
        let timestamp = Expression<Double>("timestamp")
        let amountUsd = Expression<Double>("amount_usd")
        let sessionId = Expression<String?>("session_id")

        try db.run(table.create(ifNotExists: true) { t in
            t.column(timestamp)
            t.column(amountUsd)
            t.column(sessionId)
        })
        try db.run(table.createIndex(timestamp, ifNotExists: true))
    }

    func logCost(amount: Double, sessionId: String?) throws {
        try perform { db in
            let insert = table.insert(
                timestamp <- Date().timeIntervalSince1970,
                amountUsd <- amount,
                self.sessionId <- sessionId
            )
            try db.run(insert)
        }
    }

    func getTotalCost(since date: Date) throws -> Double {
        try perform { db in
            let query = table
                .filter(timestamp >= date.timeIntervalSince1970)
                .select(amountUsd.sum)

            if let row = try db.pluck(query) {
                return row[amountUsd.sum] ?? 0
            }
            return 0
        }
    }

    func getDailyCost() throws -> Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return try getTotalCost(since: startOfDay)
    }

    func getWeeklyCost() throws -> Double {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return try getTotalCost(since: startOfWeek)
    }

    func getMonthlyCost() throws -> Double {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        return try getTotalCost(since: startOfMonth)
    }

    func getCostHistory(days: Int = 30) throws -> [(date: Date, amount: Double)] {
        try perform { db in
            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!

            let query = table
                .filter(timestamp >= startDate.timeIntervalSince1970)
                .order(timestamp.asc)

            var history: [(date: Date, amount: Double)] = []
            for row in try db.prepare(query) {
                history.append((
                    date: Date(timeIntervalSince1970: row[timestamp]),
                    amount: row[amountUsd]
                ))
            }
            return history
        }
    }

    func deleteCosts(forSession sessionIdValue: String) throws {
        try perform { db in
            try db.run(table.filter(sessionId == sessionIdValue).delete())
        }
    }
}

