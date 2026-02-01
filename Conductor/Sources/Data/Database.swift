import Foundation
import SQLite

final class Database {
    static let shared = Database()

    private var db: Connection?

    // SQLite.swift `Connection` is not safe to use concurrently across threads in this app.
    // Conductor accesses the database from `Task.detached` and UI contexts, so we serialize
    // all DB work through a single queue to avoid races and "database is locked" issues.
    private let accessQueue = DispatchQueue(label: "com.conductor.database")
    private let accessQueueKey = DispatchSpecificKey<UInt8>()

    // Tables
    private let messagesTable = Table("messages")
    private let sessionsTable = Table("sessions")
    private let costLogTable = Table("cost_log")
    private let notesTable = Table("notes")
    private let preferencesTable = Table("preferences")
    private let dailyBriefsTable = Table("daily_briefs")
    private let dailyGoalsTable = Table("daily_goals")
    private let productivityStatsTable = Table("productivity_stats")
    private let tasksTable = Table("tasks")
    private let taskListsTable = Table("task_lists")

    // Messages columns
    private let id = Expression<String>("id")
    private let role = Expression<String>("role")
    private let content = Expression<String>("content")
    private let timestamp = Expression<Double>("timestamp")
    private let sessionId = Expression<String?>("session_id")

    // Sessions columns
    private let sessId = Expression<String>("id")
    private let sessCreatedAt = Expression<Double>("created_at")
    private let sessLastUsed = Expression<Double>("last_used")
    private let sessTitle = Expression<String>("title")

    // Cost log columns
    private let costTimestamp = Expression<Double>("timestamp")
    private let costAmount = Expression<Double>("amount_usd")
    private let costSessionId = Expression<String?>("session_id")

    // Notes columns
    private let noteId = Expression<String>("id")
    private let noteTitle = Expression<String>("title")
    private let noteContent = Expression<String>("content")
    private let noteCreatedAt = Expression<Double>("created_at")
    private let noteUpdatedAt = Expression<Double>("updated_at")

    // Preferences columns
    private let prefKey = Expression<String>("key")
    private let prefValue = Expression<String>("value")

    // Daily briefs columns
    private let briefId = Expression<String>("id")
    private let briefDate = Expression<String>("date")
    private let briefType = Expression<String>("brief_type")
    private let briefContent = Expression<String>("content")
    private let briefGeneratedAt = Expression<Double>("generated_at")
    private let briefReadAt = Expression<Double?>("read_at")
    private let briefDismissed = Expression<Int>("dismissed")

    // Daily goals columns
    private let goalId = Expression<String>("id")
    private let goalDate = Expression<String>("date")
    private let goalText = Expression<String>("goal_text")
    private let goalPriority = Expression<Int>("priority")
    private let goalCompletedAt = Expression<Double?>("completed_at")
    private let goalRolledTo = Expression<String?>("rolled_to")

    // Productivity stats columns
    private let statsId = Expression<String>("id")
    private let statsDate = Expression<String>("date")
    private let statsGoalsCompleted = Expression<Int>("goals_completed")
    private let statsGoalsTotal = Expression<Int>("goals_total")
    private let statsMeetingsCount = Expression<Int>("meetings_count")
    private let statsMeetingsHours = Expression<Double>("meetings_hours")
    private let statsFocusHours = Expression<Double>("focus_hours")
    private let statsOverdueCount = Expression<Int>("overdue_count")
    private let statsGeneratedAt = Expression<Double>("generated_at")

    // Tasks columns
    private let taskId = Expression<String>("id")
    private let taskTitle = Expression<String>("title")
    private let taskNotes = Expression<String?>("notes")
    private let taskDueDate = Expression<Double?>("due_date")
    private let taskListId = Expression<String?>("list_id")
    private let taskPriority = Expression<Int>("priority")  // 0=none, 1=low, 2=medium, 3=high
    private let taskCompleted = Expression<Int>("completed")
    private let taskCompletedAt = Expression<Double?>("completed_at")
    private let taskCreatedAt = Expression<Double>("created_at")
    private let taskUpdatedAt = Expression<Double>("updated_at")

    // Task lists columns
    private let listId = Expression<String>("id")
    private let listName = Expression<String>("name")
    private let listColor = Expression<String>("color")
    private let listIcon = Expression<String>("icon")
    private let listSortOrder = Expression<Int>("sort_order")
    private let listCreatedAt = Expression<Double>("created_at")

    private init() {
        configureAccessQueue()
        setupDatabase()
    }

    /// Internal initializer intended for tests (e.g. in-memory databases).
    init(connection: Connection) {
        configureAccessQueue()
        db = connection
        do {
            try createTables()
        } catch {
            print("Database initialization failed: \(error)")
        }
    }

    private func configureAccessQueue() {
        accessQueue.setSpecific(key: accessQueueKey, value: 1)
    }

    @discardableResult
    private func perform<T>(_ body: (Connection) throws -> T) throws -> T {
        guard let db = db else { throw DatabaseError.notInitialized }

        if DispatchQueue.getSpecific(key: accessQueueKey) != nil {
            return try body(db)
        }

        return try accessQueue.sync {
            try body(db)
        }
    }

    private func setupDatabase() {
        do {
            let dbPath = getDatabasePath()
            db = try Connection(dbPath)

            // Create tables if they don't exist
            try createTables()

            print("Database initialized at: \(dbPath)")
        } catch {
            print("Database initialization failed: \(error)")
        }
    }

    private func getDatabasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let conductorDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: conductorDir, withIntermediateDirectories: true)

        return conductorDir.appendingPathComponent("conductor.db").path
    }

    private func createTables() throws {
        try perform { db in
            // Messages table
            try db.run(messagesTable.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(role)
                t.column(content)
                t.column(timestamp)
                t.column(sessionId)
            })
            try db.run(messagesTable.createIndex(timestamp, ifNotExists: true))
            // Composite index for session-scoped queries
            try db.run(messagesTable.createIndex(sessionId, timestamp, ifNotExists: true))

            // Sessions table
            try db.run(sessionsTable.create(ifNotExists: true) { t in
                t.column(sessId, primaryKey: true)
                t.column(sessCreatedAt)
                t.column(sessLastUsed)
                t.column(sessTitle)
            })
            try db.run(sessionsTable.createIndex(sessLastUsed, ifNotExists: true))

            // Cost log table
            try db.run(costLogTable.create(ifNotExists: true) { t in
                t.column(costTimestamp)
                t.column(costAmount)
                t.column(costSessionId)
            })
            try db.run(costLogTable.createIndex(costTimestamp, ifNotExists: true))

            // Notes table
            try db.run(notesTable.create(ifNotExists: true) { t in
                t.column(noteId, primaryKey: true)
                t.column(noteTitle)
                t.column(noteContent)
                t.column(noteCreatedAt)
                t.column(noteUpdatedAt)
            })
            try db.run(notesTable.createIndex(noteUpdatedAt, ifNotExists: true))

            // Preferences table
            try db.run(preferencesTable.create(ifNotExists: true) { t in
                t.column(prefKey, primaryKey: true)
                t.column(prefValue)
            })

            // Daily briefs table
            try db.run(dailyBriefsTable.create(ifNotExists: true) { t in
                t.column(briefId, primaryKey: true)
                t.column(briefDate)
                t.column(briefType)
                t.column(briefContent)
                t.column(briefGeneratedAt)
                t.column(briefReadAt)
                t.column(briefDismissed, defaultValue: 0)
            })
            try db.run(dailyBriefsTable.createIndex(briefDate, ifNotExists: true))

            // Daily goals table
            try db.run(dailyGoalsTable.create(ifNotExists: true) { t in
                t.column(goalId, primaryKey: true)
                t.column(goalDate)
                t.column(goalText)
                t.column(goalPriority, defaultValue: 0)
                t.column(goalCompletedAt)
                t.column(goalRolledTo)
            })
            try db.run(dailyGoalsTable.createIndex(goalDate, ifNotExists: true))

            // Productivity stats table
            try db.run(productivityStatsTable.create(ifNotExists: true) { t in
                t.column(statsId, primaryKey: true)
                t.column(statsDate)
                t.column(statsGoalsCompleted)
                t.column(statsGoalsTotal)
                t.column(statsMeetingsCount)
                t.column(statsMeetingsHours)
                t.column(statsFocusHours)
                t.column(statsOverdueCount)
                t.column(statsGeneratedAt)
            })
            try db.run(productivityStatsTable.createIndex(statsDate, ifNotExists: true))

            // Tasks table
            try db.run(tasksTable.create(ifNotExists: true) { t in
                t.column(taskId, primaryKey: true)
                t.column(taskTitle)
                t.column(taskNotes)
                t.column(taskDueDate)
                t.column(taskListId)
                t.column(taskPriority, defaultValue: 0)
                t.column(taskCompleted, defaultValue: 0)
                t.column(taskCompletedAt)
                t.column(taskCreatedAt)
                t.column(taskUpdatedAt)
            })
            try db.run(tasksTable.createIndex(taskListId, ifNotExists: true))
            try db.run(tasksTable.createIndex(taskDueDate, ifNotExists: true))
            try db.run(tasksTable.createIndex(taskCompleted, ifNotExists: true))

            // Task lists table
            try db.run(taskListsTable.create(ifNotExists: true) { t in
                t.column(listId, primaryKey: true)
                t.column(listName)
                t.column(listColor, defaultValue: "blue")
                t.column(listIcon, defaultValue: "list.bullet")
                t.column(listSortOrder, defaultValue: 0)
                t.column(listCreatedAt)
            })
            try db.run(taskListsTable.createIndex(listSortOrder, ifNotExists: true))
        }
    }

    // MARK: - Messages

    func saveMessage(_ message: ChatMessage, forSession session: String? = nil) throws {
        try perform { db in
            let insert = messagesTable.insert(or: .replace,
                id <- message.id.uuidString,
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
            // Order by DESC to get newest first, then reverse to get chronological order
            // This ensures we get the N most recent messages, not the N oldest
            var query: SQLite.Table
            if let session = session {
                query = messagesTable.filter(sessionId == session).order(timestamp.desc).limit(limit)
            } else {
                query = messagesTable.order(timestamp.desc).limit(limit)
            }

            var messages: [ChatMessage] = []

            for row in try db.prepare(query) {
                if let messageRole = ChatMessage.Role(rawValue: row[role]),
                   let uuid = UUID(uuidString: row[id]) {
                    let message = ChatMessage(
                        id: uuid,
                        role: messageRole,
                        content: row[content],
                        timestamp: Date(timeIntervalSince1970: row[timestamp])
                    )
                    messages.append(message)
                }
            }

            // Reverse to get chronological order (oldest first within the recent set)
            return messages.reversed()
        }
    }

    func clearMessages(forSession session: String? = nil) throws {
        try perform { db in
            if let session = session {
                try db.run(messagesTable.filter(sessionId == session).delete())
            } else {
                try db.run(messagesTable.delete())
            }
        }
    }

    /// Updates messages with NULL session_id to associate them with a session.
    /// This is used when a session is created after the first message is saved.
    func associateOrphanedMessages(withSession session: String) throws {
        try perform { db in
            // Find messages with no session that were created recently (within last minute)
            // and associate them with the new session
            let oneMinuteAgo = Date().addingTimeInterval(-60).timeIntervalSince1970
            let orphanedMessages = messagesTable
                .filter(sessionId == nil)
                .filter(timestamp >= oneMinuteAgo)

            try db.run(orphanedMessages.update(sessionId <- session))
        }
    }

    // MARK: - Sessions

    func saveSession(id sessionIdValue: String, title: String) throws {
        try perform { db in
            let now = Date().timeIntervalSince1970

            // Try to update existing session
            let existingSession = sessionsTable.filter(sessId == sessionIdValue)
            let updateCount = try db.run(existingSession.update(
                sessLastUsed <- now,
                sessTitle <- title
            ))

            // If no rows updated, insert new session
            if updateCount == 0 {
                let insert = sessionsTable.insert(
                    sessId <- sessionIdValue,
                    sessCreatedAt <- now,
                    sessLastUsed <- now,
                    sessTitle <- title
                )
                try db.run(insert)
            }
        }
    }

    func getRecentSessions(limit: Int = 20) throws -> [Session] {
        try perform { db in
            let query = sessionsTable.order(sessLastUsed.desc).limit(limit)

            var sessions: [Session] = []

            for row in try db.prepare(query) {
                sessions.append(Session(
                    id: row[sessId],
                    createdAt: Date(timeIntervalSince1970: row[sessCreatedAt]),
                    lastUsed: Date(timeIntervalSince1970: row[sessLastUsed]),
                    title: row[sessTitle]
                ))
            }

            return sessions
        }
    }

    func deleteSession(id sessionIdValue: String) throws {
        try perform { db in
            // Delete session
            try db.run(sessionsTable.filter(sessId == sessionIdValue).delete())

            // Delete associated messages
            try db.run(messagesTable.filter(sessionId == sessionIdValue).delete())

            // Delete associated cost logs
            try db.run(costLogTable.filter(costSessionId == sessionIdValue).delete())
        }
    }

    // MARK: - Cost Tracking

    func logCost(amount: Double, sessionId session: String?) throws {
        try perform { db in
            let insert = costLogTable.insert(
                costTimestamp <- Date().timeIntervalSince1970,
                costAmount <- amount,
                costSessionId <- session
            )

            try db.run(insert)
        }
    }

    func getTotalCost(since date: Date) throws -> Double {
        try perform { db in
            let query = costLogTable
                .filter(costTimestamp >= date.timeIntervalSince1970)
                .select(costAmount.sum)

            if let row = try db.pluck(query) {
                return row[costAmount.sum] ?? 0
            }

            return 0
        }
    }

    func getDailyCost() throws -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
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

            let query = costLogTable
                .filter(costTimestamp >= startDate.timeIntervalSince1970)
                .order(costTimestamp.asc)

            var history: [(date: Date, amount: Double)] = []

            for row in try db.prepare(query) {
                history.append((
                    date: Date(timeIntervalSince1970: row[costTimestamp]),
                    amount: row[costAmount]
                ))
            }

            return history
        }
    }

    // MARK: - Notes

    func saveNote(title: String, content: String) throws -> String {
        try perform { db in
            let noteIdValue = UUID().uuidString
            let now = Date().timeIntervalSince1970

            let insert = notesTable.insert(
                noteId <- noteIdValue,
                noteTitle <- title,
                noteContent <- content,
                noteCreatedAt <- now,
                noteUpdatedAt <- now
            )

            try db.run(insert)
            return noteIdValue
        }
    }

    func updateNote(id: String, title: String? = nil, content: String? = nil) throws {
        try perform { db in
            let note = notesTable.filter(noteId == id)
            var setters: [Setter] = [noteUpdatedAt <- Date().timeIntervalSince1970]

            if let title = title {
                setters.append(noteTitle <- title)
            }
            if let content = content {
                setters.append(noteContent <- content)
            }

            try db.run(note.update(setters))
        }
    }

    func loadNotes(limit: Int = 20) throws -> [(id: String, title: String, content: String)] {
        try perform { db in
            let query = notesTable
                .order(noteUpdatedAt.desc)
                .limit(limit)

            var notes: [(id: String, title: String, content: String)] = []

            for row in try db.prepare(query) {
                notes.append((
                    id: row[noteId],
                    title: row[noteTitle],
                    content: row[noteContent]
                ))
            }

            return notes
        }
    }

    func deleteNote(id: String) throws {
        try perform { db in
            let note = notesTable.filter(noteId == id)
            try db.run(note.delete())
        }
    }

    // MARK: - Preferences

    func setPreference(key: String, value: String) throws {
        try perform { db in
            let insert = preferencesTable.insert(or: .replace,
                prefKey <- key,
                prefValue <- value
            )

            try db.run(insert)
        }
    }

    func getPreference(key: String) throws -> String? {
        try perform { db in
            let query = preferencesTable.filter(prefKey == key)

            if let row = try db.pluck(query) {
                return row[prefValue]
            }

            return nil
        }
    }

    func deletePreference(key: String) throws {
        try perform { db in
            let pref = preferencesTable.filter(prefKey == key)
            try db.run(pref.delete())
        }
    }

    // MARK: - Daily Briefs

    func saveDailyBrief(_ brief: DailyBrief) throws {
        try perform { db in
            let insert = dailyBriefsTable.insert(or: .replace,
                briefId <- brief.id,
                briefDate <- brief.date,
                briefType <- brief.briefType.rawValue,
                briefContent <- brief.content,
                briefGeneratedAt <- brief.generatedAt.timeIntervalSince1970,
                briefReadAt <- brief.readAt?.timeIntervalSince1970,
                briefDismissed <- brief.dismissed ? 1 : 0
            )

            try db.run(insert)
        }
    }

    func getDailyBrief(for date: String, type: DailyBrief.BriefType) throws -> DailyBrief? {
        try perform { db in
            let query = dailyBriefsTable
                .filter(briefDate == date)
                .filter(briefType == type.rawValue)

            if let row = try db.pluck(query) {
                return DailyBrief(
                    id: row[briefId],
                    date: row[briefDate],
                    briefType: DailyBrief.BriefType(rawValue: row[briefType]) ?? .morning,
                    content: row[briefContent],
                    generatedAt: Date(timeIntervalSince1970: row[briefGeneratedAt]),
                    readAt: row[briefReadAt].map { Date(timeIntervalSince1970: $0) },
                    dismissed: row[briefDismissed] == 1
                )
            }

            return nil
        }
    }

    func markBriefAsRead(id: String) throws {
        try perform { db in
            let brief = dailyBriefsTable.filter(briefId == id)
            try db.run(brief.update(briefReadAt <- Date().timeIntervalSince1970))
        }
    }

    func markBriefAsDismissed(id: String) throws {
        try perform { db in
            let brief = dailyBriefsTable.filter(briefId == id)
            try db.run(brief.update(briefDismissed <- 1))
        }
    }

    func getRecentBriefs(limit: Int = 7) throws -> [DailyBrief] {
        try perform { db in
            let query = dailyBriefsTable
                .order(briefGeneratedAt.desc)
                .limit(limit)

            var briefs: [DailyBrief] = []

            for row in try db.prepare(query) {
                briefs.append(DailyBrief(
                    id: row[briefId],
                    date: row[briefDate],
                    briefType: DailyBrief.BriefType(rawValue: row[briefType]) ?? .morning,
                    content: row[briefContent],
                    generatedAt: Date(timeIntervalSince1970: row[briefGeneratedAt]),
                    readAt: row[briefReadAt].map { Date(timeIntervalSince1970: $0) },
                    dismissed: row[briefDismissed] == 1
                ))
            }

            return briefs
        }
    }

    // MARK: - Daily Goals

    func saveDailyGoal(_ goal: DailyGoal) throws {
        try perform { db in
            let insert = dailyGoalsTable.insert(or: .replace,
                goalId <- goal.id,
                goalDate <- goal.date,
                goalText <- goal.goalText,
                goalPriority <- goal.priority,
                goalCompletedAt <- goal.completedAt?.timeIntervalSince1970,
                goalRolledTo <- goal.rolledTo
            )

            try db.run(insert)
        }
    }

    func getGoalsForDate(_ date: String) throws -> [DailyGoal] {
        try perform { db in
            let query = dailyGoalsTable
                .filter(goalDate == date)
                .order(goalPriority.asc)

            var goals: [DailyGoal] = []

            for row in try db.prepare(query) {
                goals.append(DailyGoal(
                    id: row[goalId],
                    date: row[goalDate],
                    goalText: row[goalText],
                    priority: row[goalPriority],
                    completedAt: row[goalCompletedAt].map { Date(timeIntervalSince1970: $0) },
                    rolledTo: row[goalRolledTo]
                ))
            }

            return goals
        }
    }

    func markGoalCompleted(id: String) throws {
        try perform { db in
            let goal = dailyGoalsTable.filter(goalId == id)
            try db.run(goal.update(goalCompletedAt <- Date().timeIntervalSince1970))
        }
    }

    func markGoalIncomplete(id: String) throws {
        try perform { db in
            let goal = dailyGoalsTable.filter(goalId == id)
            try db.run(goal.update(goalCompletedAt <- nil as Double?))
        }
    }

    func rollGoalToDate(id: String, newDate: String) throws {
        try perform { db in
            let goal = dailyGoalsTable.filter(goalId == id)
            try db.run(goal.update(goalRolledTo <- newDate))
        }
    }

    func deleteGoal(id: String) throws {
        try perform { db in
            let goal = dailyGoalsTable.filter(goalId == id)
            try db.run(goal.delete())
        }
    }

    func updateGoalText(id: String, text: String) throws {
        try perform { db in
            let goal = dailyGoalsTable.filter(goalId == id)
            try db.run(goal.update(goalText <- text))
        }
    }

    func updateGoalPriority(id: String, priority: Int) throws {
        try perform { db in
            let goal = dailyGoalsTable.filter(goalId == id)
            try db.run(goal.update(goalPriority <- priority))
        }
    }

    func getIncompleteGoals(before date: String) throws -> [DailyGoal] {
        try perform { db in
            let query = dailyGoalsTable
                .filter(goalDate < date)
                .filter(goalCompletedAt == nil)
                .filter(goalRolledTo == nil)
                .order(goalDate.desc, goalPriority.asc)

            var goals: [DailyGoal] = []

            for row in try db.prepare(query) {
                goals.append(DailyGoal(
                    id: row[goalId],
                    date: row[goalDate],
                    goalText: row[goalText],
                    priority: row[goalPriority],
                    completedAt: row[goalCompletedAt].map { Date(timeIntervalSince1970: $0) },
                    rolledTo: row[goalRolledTo]
                ))
            }

            return goals
        }
    }

    func getGoalCompletionRate(forDays days: Int = 7) throws -> Double {
        try perform { db in
            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let startDateString = dateFormatter.string(from: startDate)

            let totalQuery = dailyGoalsTable
                .filter(goalDate >= startDateString)
                .count

            let completedQuery = dailyGoalsTable
                .filter(goalDate >= startDateString)
                .filter(goalCompletedAt != nil)
                .count

            let total = try db.scalar(totalQuery)
            let completed = try db.scalar(completedQuery)

            guard total > 0 else { return 0 }
            return Double(completed) / Double(total)
        }
    }

    // MARK: - Productivity Stats

    func saveProductivityStats(_ stats: ProductivityStats) throws {
        try perform { db in
            let insert = productivityStatsTable.insert(or: .replace,
                statsId <- stats.id,
                statsDate <- stats.date,
                statsGoalsCompleted <- stats.goalsCompleted,
                statsGoalsTotal <- stats.goalsTotal,
                statsMeetingsCount <- stats.meetingsCount,
                statsMeetingsHours <- stats.meetingsHours,
                statsFocusHours <- stats.focusHours,
                statsOverdueCount <- stats.overdueCount,
                statsGeneratedAt <- stats.generatedAt.timeIntervalSince1970
            )

            try db.run(insert)
        }
    }

    func getProductivityStats(for date: String) throws -> ProductivityStats? {
        try perform { db in
            let query = productivityStatsTable.filter(statsDate == date)

            if let row = try db.pluck(query) {
                return ProductivityStats(
                    id: row[statsId],
                    date: row[statsDate],
                    goalsCompleted: row[statsGoalsCompleted],
                    goalsTotal: row[statsGoalsTotal],
                    meetingsCount: row[statsMeetingsCount],
                    meetingsHours: row[statsMeetingsHours],
                    focusHours: row[statsFocusHours],
                    overdueCount: row[statsOverdueCount],
                    generatedAt: Date(timeIntervalSince1970: row[statsGeneratedAt])
                )
            }

            return nil
        }
    }

    func getProductivityStatsRange(from startDate: String, to endDate: String) throws -> [ProductivityStats] {
        try perform { db in
            let query = productivityStatsTable
                .filter(statsDate >= startDate && statsDate <= endDate)
                .order(statsDate.asc)

            var stats: [ProductivityStats] = []

            for row in try db.prepare(query) {
                stats.append(ProductivityStats(
                    id: row[statsId],
                    date: row[statsDate],
                    goalsCompleted: row[statsGoalsCompleted],
                    goalsTotal: row[statsGoalsTotal],
                    meetingsCount: row[statsMeetingsCount],
                    meetingsHours: row[statsMeetingsHours],
                    focusHours: row[statsFocusHours],
                    overdueCount: row[statsOverdueCount],
                    generatedAt: Date(timeIntervalSince1970: row[statsGeneratedAt])
                ))
            }

            return stats
        }
    }

    func getRecentProductivityStats(days: Int = 30) throws -> [ProductivityStats] {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return try getProductivityStatsRange(
            from: dateFormatter.string(from: startDate),
            to: dateFormatter.string(from: endDate)
        )
    }

    // MARK: - Task Lists

    func createTaskList(name: String, color: String = "blue", icon: String = "list.bullet") throws -> String {
        try perform { db in
            let listIdValue = UUID().uuidString
            let now = Date().timeIntervalSince1970

            // Get max sort order
            let maxOrder = try db.scalar(taskListsTable.select(listSortOrder.max)) ?? 0

            let insert = taskListsTable.insert(
                listId <- listIdValue,
                listName <- name,
                listColor <- color,
                listIcon <- icon,
                listSortOrder <- maxOrder + 1,
                listCreatedAt <- now
            )

            try db.run(insert)
            return listIdValue
        }
    }

    func getTaskLists() throws -> [TaskList] {
        try perform { db in
            let query = taskListsTable.order(listSortOrder.asc)
            var lists: [TaskList] = []

            for row in try db.prepare(query) {
                lists.append(TaskList(
                    id: row[listId],
                    name: row[listName],
                    color: row[listColor],
                    icon: row[listIcon],
                    sortOrder: row[listSortOrder]
                ))
            }

            return lists
        }
    }

    func updateTaskList(id: String, name: String? = nil, color: String? = nil, icon: String? = nil) throws {
        try perform { db in
            let list = taskListsTable.filter(listId == id)
            var setters: [Setter] = []

            if let name = name { setters.append(listName <- name) }
            if let color = color { setters.append(listColor <- color) }
            if let icon = icon { setters.append(listIcon <- icon) }

            guard !setters.isEmpty else { return }
            try db.run(list.update(setters))
        }
    }

    func deleteTaskList(id: String) throws {
        try perform { db in
            // Delete the list
            try db.run(taskListsTable.filter(listId == id).delete())

            // Clear list_id from tasks in this list (don't delete tasks)
            try db.run(tasksTable.filter(taskListId == id).update(taskListId <- nil as String?))
        }
    }

    // MARK: - Tasks

    func createTask(_ task: TodoTask) throws {
        try perform { db in
            let now = Date().timeIntervalSince1970

            let insert = tasksTable.insert(
                taskId <- task.id,
                taskTitle <- task.title,
                taskNotes <- task.notes,
                taskDueDate <- task.dueDate?.timeIntervalSince1970,
                taskListId <- task.listId,
                taskPriority <- task.priority.rawValue,
                taskCompleted <- task.isCompleted ? 1 : 0,
                taskCompletedAt <- task.completedAt?.timeIntervalSince1970,
                taskCreatedAt <- task.createdAt.timeIntervalSince1970,
                taskUpdatedAt <- now
            )

            try db.run(insert)
        }
    }

    func updateTask(_ task: TodoTask) throws {
        try perform { db in
            let now = Date().timeIntervalSince1970
            let taskRow = tasksTable.filter(taskId == task.id)

            try db.run(taskRow.update(
                taskTitle <- task.title,
                taskNotes <- task.notes,
                taskDueDate <- task.dueDate?.timeIntervalSince1970,
                taskListId <- task.listId,
                taskPriority <- task.priority.rawValue,
                taskCompleted <- task.isCompleted ? 1 : 0,
                taskCompletedAt <- task.completedAt?.timeIntervalSince1970,
                taskUpdatedAt <- now
            ))
        }
    }

    func deleteTask(id: String) throws {
        try perform { db in
            try db.run(tasksTable.filter(taskId == id).delete())
        }
    }

    func getTask(id: String) throws -> TodoTask? {
        try perform { db in
            let query = tasksTable.filter(taskId == id)

            if let row = try db.pluck(query) {
                return rowToTask(row)
            }
            return nil
        }
    }

    func getAllTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            var query = tasksTable.order(taskDueDate.asc, taskPriority.desc, taskCreatedAt.desc)
            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }

            var tasks: [TodoTask] = []
            for row in try db.prepare(query) {
                tasks.append(rowToTask(row))
            }
            return tasks
        }
    }

    func getTasksForList(_ listIdValue: String?, includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            var query: SQLite.Table
            if let listIdValue = listIdValue {
                query = tasksTable.filter(taskListId == listIdValue)
            } else {
                query = tasksTable.filter(taskListId == nil)
            }

            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }

            query = query.order(taskDueDate.asc, taskPriority.desc, taskCreatedAt.desc)

            var tasks: [TodoTask] = []
            for row in try db.prepare(query) {
                tasks.append(rowToTask(row))
            }
            return tasks
        }
    }

    func getTodayTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date()).timeIntervalSince1970
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!.timeIntervalSince1970

            var query = tasksTable.filter(
                (taskDueDate != nil && taskDueDate >= startOfDay && taskDueDate < endOfDay) ||
                (taskDueDate != nil && taskDueDate < startOfDay && taskCompleted == 0)  // Overdue
            )

            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }

            query = query.order(taskDueDate.asc, taskPriority.desc)

            var tasks: [TodoTask] = []
            for row in try db.prepare(query) {
                tasks.append(rowToTask(row))
            }
            return tasks
        }
    }

    func getScheduledTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            var query = tasksTable.filter(taskDueDate != nil)
            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }
            query = query.order(taskDueDate.asc, taskPriority.desc)

            var tasks: [TodoTask] = []
            for row in try db.prepare(query) {
                tasks.append(rowToTask(row))
            }
            return tasks
        }
    }

    func getFlaggedTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            var query = tasksTable.filter(taskPriority == TodoTask.Priority.high.rawValue)
            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }
            query = query.order(taskDueDate.asc, taskCreatedAt.desc)

            var tasks: [TodoTask] = []
            for row in try db.prepare(query) {
                tasks.append(rowToTask(row))
            }
            return tasks
        }
    }

    func toggleTaskCompleted(id: String) throws {
        try perform { db in
            let taskRow = tasksTable.filter(taskId == id)
            if let row = try db.pluck(taskRow) {
                let isCompleted = row[taskCompleted] == 1
                let now = Date().timeIntervalSince1970

                if isCompleted {
                    // Mark incomplete
                    try db.run(taskRow.update(
                        taskCompleted <- 0,
                        taskCompletedAt <- nil as Double?,
                        taskUpdatedAt <- now
                    ))
                } else {
                    // Mark complete
                    try db.run(taskRow.update(
                        taskCompleted <- 1,
                        taskCompletedAt <- now,
                        taskUpdatedAt <- now
                    ))
                }
            }
        }
    }

    private func rowToTask(_ row: Row) -> TodoTask {
        TodoTask(
            id: row[taskId],
            title: row[taskTitle],
            notes: row[taskNotes],
            dueDate: row[taskDueDate].map { Date(timeIntervalSince1970: $0) },
            listId: row[taskListId],
            priority: TodoTask.Priority(rawValue: row[taskPriority]) ?? .none,
            isCompleted: row[taskCompleted] == 1,
            completedAt: row[taskCompletedAt].map { Date(timeIntervalSince1970: $0) },
            createdAt: Date(timeIntervalSince1970: row[taskCreatedAt])
        )
    }
}

// MARK: - Models

struct Session: Identifiable {
    let id: String
    let createdAt: Date
    let lastUsed: Date
    let title: String

    var formattedLastUsed: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }
}

struct DailyBrief: Identifiable {
    let id: String
    let date: String  // YYYY-MM-DD
    let briefType: BriefType
    let content: String
    let generatedAt: Date
    var readAt: Date?
    var dismissed: Bool

    enum BriefType: String, Codable {
        case morning
        case evening
        case weekly
        case monthly
    }

    init(id: String = UUID().uuidString,
         date: String,
         briefType: BriefType,
         content: String,
         generatedAt: Date = Date(),
         readAt: Date? = nil,
         dismissed: Bool = false) {
        self.id = id
        self.date = date
        self.briefType = briefType
        self.content = content
        self.generatedAt = generatedAt
        self.readAt = readAt
        self.dismissed = dismissed
    }
}

struct DailyGoal: Identifiable {
    let id: String
    let date: String  // YYYY-MM-DD
    var goalText: String
    var priority: Int  // 1, 2, 3 for top 3
    var completedAt: Date?
    var rolledTo: String?  // Date string if rolled to another day

    var isCompleted: Bool {
        completedAt != nil
    }

    var isRolled: Bool {
        rolledTo != nil
    }

    init(id: String = UUID().uuidString,
         date: String,
         goalText: String,
         priority: Int = 0,
         completedAt: Date? = nil,
         rolledTo: String? = nil) {
        self.id = id
        self.date = date
        self.goalText = goalText
        self.priority = priority
        self.completedAt = completedAt
        self.rolledTo = rolledTo
    }
}

struct ProductivityStats: Identifiable {
    let id: String
    let date: String  // YYYY-MM-DD
    let goalsCompleted: Int
    let goalsTotal: Int
    let meetingsCount: Int
    let meetingsHours: Double
    let focusHours: Double
    let overdueCount: Int
    let generatedAt: Date

    var completionRate: Double {
        guard goalsTotal > 0 else { return 0 }
        return Double(goalsCompleted) / Double(goalsTotal)
    }

    init(id: String = UUID().uuidString,
         date: String,
         goalsCompleted: Int,
         goalsTotal: Int,
         meetingsCount: Int,
         meetingsHours: Double,
         focusHours: Double,
         overdueCount: Int,
         generatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.goalsCompleted = goalsCompleted
        self.goalsTotal = goalsTotal
        self.meetingsCount = meetingsCount
        self.meetingsHours = meetingsHours
        self.focusHours = focusHours
        self.overdueCount = overdueCount
        self.generatedAt = generatedAt
    }
}

// MARK: - Errors

enum DatabaseError: LocalizedError {
    case notInitialized
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database not initialized"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

// MARK: - Task List Model

struct TaskList: Identifiable {
    let id: String
    var name: String
    var color: String
    var icon: String
    var sortOrder: Int

    init(id: String = UUID().uuidString, name: String, color: String = "blue", icon: String = "list.bullet", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
    }

    var swiftUIColor: Color {
        switch color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        default: return .blue
        }
    }
}

// MARK: - Task Model

struct TodoTask: Identifiable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: Date?
    var listId: String?
    var priority: Priority
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date

    enum Priority: Int, CaseIterable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3

        var label: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }

        var icon: String? {
            switch self {
            case .none: return nil
            case .low: return "arrow.down"
            case .medium: return "minus"
            case .high: return "exclamationmark"
            }
        }

        var color: Color {
            switch self {
            case .none: return .secondary
            case .low: return .blue
            case .medium: return .orange
            case .high: return .red
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        listId: String? = nil,
        priority: Priority = .none,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.listId = listId
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    var isOverdue: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }
        return dueDate < Date()
    }

    var isDueToday: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    var isDueTomorrow: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInTomorrow(dueDate)
    }

    var isDueThisWeek: Bool {
        guard let dueDate = dueDate else { return false }
        let calendar = Calendar.current
        let now = Date()
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) else { return false }
        return dueDate >= now && dueDate < weekEnd
    }

    var dueDateLabel: String? {
        guard let dueDate = dueDate else { return nil }

        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        } else if isOverdue {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: dueDate, relativeTo: Date())
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: dueDate)
        }
    }
}

import SwiftUI
