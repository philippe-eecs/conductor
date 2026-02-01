import Foundation
import SQLite

struct GoalStore: DatabaseStore {
    let database: Database

    private let table = Table("daily_goals")
    private let id = Expression<String>("id")
    private let date = Expression<String>("date")
    private let text = Expression<String>("goal_text")
    private let priority = Expression<Int>("priority")
    private let completedAt = Expression<Double?>("completed_at")
    private let rolledTo = Expression<String?>("rolled_to")

    static func createTables(in db: Connection) throws {
        let table = Table("daily_goals")
        let id = Expression<String>("id")
        let date = Expression<String>("date")
        let text = Expression<String>("goal_text")
        let priority = Expression<Int>("priority")
        let completedAt = Expression<Double?>("completed_at")
        let rolledTo = Expression<String?>("rolled_to")

        try db.run(table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(date)
            t.column(text)
            t.column(priority, defaultValue: 0)
            t.column(completedAt)
            t.column(rolledTo)
        })
        try db.run(table.createIndex(date, ifNotExists: true))
    }

    func saveDailyGoal(_ goal: DailyGoal) throws {
        try perform { db in
            let insert = table.insert(or: .replace,
                id <- goal.id,
                date <- goal.date,
                text <- goal.goalText,
                priority <- goal.priority,
                completedAt <- goal.completedAt?.timeIntervalSince1970,
                rolledTo <- goal.rolledTo
            )
            try db.run(insert)
        }
    }

    func getGoalsForDate(_ dateValue: String) throws -> [DailyGoal] {
        try perform { db in
            let query = table.filter(date == dateValue).order(priority.asc)
            var goals: [DailyGoal] = []
            for row in try db.prepare(query) {
                goals.append(DailyGoal(
                    id: row[id],
                    date: row[date],
                    goalText: row[text],
                    priority: row[priority],
                    completedAt: row[completedAt].map { Date(timeIntervalSince1970: $0) },
                    rolledTo: row[rolledTo]
                ))
            }
            return goals
        }
    }

    func markGoalCompleted(id idValue: String) throws {
        try perform { db in
            try db.run(table.filter(id == idValue).update(completedAt <- Date().timeIntervalSince1970))
        }
    }

    func markGoalIncomplete(id idValue: String) throws {
        try perform { db in
            try db.run(table.filter(id == idValue).update(completedAt <- nil as Double?))
        }
    }

    func rollGoalToDate(id idValue: String, newDate: String) throws {
        try perform { db in
            try db.run(table.filter(id == idValue).update(rolledTo <- newDate))
        }
    }

    func deleteGoal(id idValue: String) throws {
        try perform { db in
            try db.run(table.filter(id == idValue).delete())
        }
    }

    func updateGoalText(id idValue: String, text newText: String) throws {
        try perform { db in
            try db.run(table.filter(id == idValue).update(text <- newText))
        }
    }

    func updateGoalPriority(id idValue: String, priority newPriority: Int) throws {
        try perform { db in
            try db.run(table.filter(id == idValue).update(priority <- newPriority))
        }
    }

    func getIncompleteGoals(before dateValue: String) throws -> [DailyGoal] {
        try perform { db in
            let query = table
                .filter(date < dateValue)
                .filter(completedAt == nil)
                .filter(rolledTo == nil)
                .order(date.desc, priority.asc)

            var goals: [DailyGoal] = []
            for row in try db.prepare(query) {
                goals.append(DailyGoal(
                    id: row[id],
                    date: row[date],
                    goalText: row[text],
                    priority: row[priority],
                    completedAt: row[completedAt].map { Date(timeIntervalSince1970: $0) },
                    rolledTo: row[rolledTo]
                ))
            }
            return goals
        }
    }

    func getGoalCompletionRate(forDays days: Int = 7) throws -> Double {
        try perform { db in
            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!
            let startDateString = SharedDateFormatters.databaseDate.string(from: startDate)

            let totalQuery = table.filter(date >= startDateString).count
            let completedQuery = table
                .filter(date >= startDateString)
                .filter(completedAt != nil)
                .count

            let total = try db.scalar(totalQuery)
            let completed = try db.scalar(completedQuery)

            guard total > 0 else { return 0 }
            return Double(completed) / Double(total)
        }
    }
}

