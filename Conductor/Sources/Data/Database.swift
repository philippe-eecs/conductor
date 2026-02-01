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

    private var sessionStore: SessionStore { SessionStore(database: self) }
    private var costStore: CostStore { CostStore(database: self) }
    private var noteStore: NoteStore { NoteStore(database: self) }
    private var preferenceStore: PreferenceStore { PreferenceStore(database: self) }
    private var briefStore: BriefStore { BriefStore(database: self) }
    private var goalStore: GoalStore { GoalStore(database: self) }
    private var productivityStatsStore: ProductivityStatsStore { ProductivityStatsStore(database: self) }
    private var taskStore: TaskStore { TaskStore(database: self) }

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
    func perform<T>(_ body: (Connection) throws -> T) throws -> T {
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
            try PreferenceStore.createTables(in: db)
            try SessionStore.createTables(in: db)
            try CostStore.createTables(in: db)
            try NoteStore.createTables(in: db)
            try BriefStore.createTables(in: db)
            try GoalStore.createTables(in: db)
            try ProductivityStatsStore.createTables(in: db)
            try TaskStore.createTables(in: db)
        }
    }

    // MARK: - Messages

    func saveMessage(_ message: ChatMessage, forSession session: String? = nil) throws {
        try sessionStore.saveMessage(message, forSession: session)
    }

    func loadRecentMessages(limit: Int = 50, forSession session: String? = nil) throws -> [ChatMessage] {
        try sessionStore.loadRecentMessages(limit: limit, forSession: session)
    }

    func clearMessages(forSession session: String? = nil) throws {
        try sessionStore.clearMessages(forSession: session)
    }

    func associateOrphanedMessages(withSession session: String) throws {
        try sessionStore.associateOrphanedMessages(withSession: session)
    }

    // MARK: - Sessions

    func saveSession(id sessionIdValue: String, title: String) throws {
        try sessionStore.saveSession(id: sessionIdValue, title: title)
    }

    func getRecentSessions(limit: Int = 20) throws -> [Session] {
        try sessionStore.getRecentSessions(limit: limit)
    }

    func deleteSession(id sessionIdValue: String) throws {
        try sessionStore.deleteSession(id: sessionIdValue)
    }

    // MARK: - Cost Tracking

    func logCost(amount: Double, sessionId session: String?) throws {
        try costStore.logCost(amount: amount, sessionId: session)
    }

    func getTotalCost(since date: Date) throws -> Double {
        try costStore.getTotalCost(since: date)
    }

    func getDailyCost() throws -> Double {
        try costStore.getDailyCost()
    }

    func getWeeklyCost() throws -> Double {
        try costStore.getWeeklyCost()
    }

    func getMonthlyCost() throws -> Double {
        try costStore.getMonthlyCost()
    }

    func getCostHistory(days: Int = 30) throws -> [(date: Date, amount: Double)] {
        try costStore.getCostHistory(days: days)
    }

    // MARK: - Notes

    func saveNote(title: String, content: String) throws -> String {
        try noteStore.saveNote(title: title, content: content)
    }

    func updateNote(id: String, title: String? = nil, content: String? = nil) throws {
        try noteStore.updateNote(id: id, title: title, content: content)
    }

    func loadNotes(limit: Int = 20) throws -> [(id: String, title: String, content: String)] {
        try noteStore.loadNotes(limit: limit)
    }

    func deleteNote(id: String) throws {
        try noteStore.deleteNote(id: id)
    }

    // MARK: - Preferences

    func setPreference(key: String, value: String) throws {
        try preferenceStore.setPreference(key: key, value: value)
    }

    func getPreference(key: String) throws -> String? {
        try preferenceStore.getPreference(key: key)
    }

    func deletePreference(key: String) throws {
        try preferenceStore.deletePreference(key: key)
    }

    // MARK: - Daily Briefs

    func saveDailyBrief(_ brief: DailyBrief) throws {
        try briefStore.saveDailyBrief(brief)
    }

    func getDailyBrief(for date: String, type: DailyBrief.BriefType) throws -> DailyBrief? {
        try briefStore.getDailyBrief(for: date, type: type)
    }

    func markBriefAsRead(id: String) throws {
        try briefStore.markBriefAsRead(id: id)
    }

    func markBriefAsDismissed(id: String) throws {
        try briefStore.markBriefAsDismissed(id: id)
    }

    func getRecentBriefs(limit: Int = 7) throws -> [DailyBrief] {
        try briefStore.getRecentBriefs(limit: limit)
    }

    // MARK: - Daily Goals

    func saveDailyGoal(_ goal: DailyGoal) throws {
        try goalStore.saveDailyGoal(goal)
    }

    func getGoalsForDate(_ date: String) throws -> [DailyGoal] {
        try goalStore.getGoalsForDate(date)
    }

    func markGoalCompleted(id: String) throws {
        try goalStore.markGoalCompleted(id: id)
    }

    func markGoalIncomplete(id: String) throws {
        try goalStore.markGoalIncomplete(id: id)
    }

    func rollGoalToDate(id: String, newDate: String) throws {
        try goalStore.rollGoalToDate(id: id, newDate: newDate)
    }

    func deleteGoal(id: String) throws {
        try goalStore.deleteGoal(id: id)
    }

    func updateGoalText(id: String, text: String) throws {
        try goalStore.updateGoalText(id: id, text: text)
    }

    func updateGoalPriority(id: String, priority: Int) throws {
        try goalStore.updateGoalPriority(id: id, priority: priority)
    }

    func getIncompleteGoals(before date: String) throws -> [DailyGoal] {
        try goalStore.getIncompleteGoals(before: date)
    }

    func getGoalCompletionRate(forDays days: Int = 7) throws -> Double {
        try goalStore.getGoalCompletionRate(forDays: days)
    }

    // MARK: - Productivity Stats

    func saveProductivityStats(_ stats: ProductivityStats) throws {
        try productivityStatsStore.saveProductivityStats(stats)
    }

    func getProductivityStats(for date: String) throws -> ProductivityStats? {
        try productivityStatsStore.getProductivityStats(for: date)
    }

    func getProductivityStatsRange(from startDate: String, to endDate: String) throws -> [ProductivityStats] {
        try productivityStatsStore.getProductivityStatsRange(from: startDate, to: endDate)
    }

    func getRecentProductivityStats(days: Int = 30) throws -> [ProductivityStats] {
        try productivityStatsStore.getRecentProductivityStats(days: days)
    }

    // MARK: - Task Lists

    func createTaskList(name: String, color: String = "blue", icon: String = "list.bullet") throws -> String {
        try taskStore.createTaskList(name: name, color: color, icon: icon)
    }

    func upsertTaskList(_ list: TaskList) throws {
        try taskStore.upsertTaskList(list)
    }

    func getTaskLists() throws -> [TaskList] {
        try taskStore.getTaskLists()
    }

    func updateTaskList(id: String, name: String? = nil, color: String? = nil, icon: String? = nil) throws {
        try taskStore.updateTaskList(id: id, name: name, color: color, icon: icon)
    }

    func deleteTaskList(id: String) throws {
        try taskStore.deleteTaskList(id: id)
    }

    func restoreListMembership(taskIds: [String], listId: String?) throws {
        try taskStore.restoreListMembership(taskIds: taskIds, listId: listId)
    }

    // MARK: - Tasks

    func createTask(_ task: TodoTask) throws {
        try taskStore.createTask(task)
    }

    func updateTask(_ task: TodoTask) throws {
        try taskStore.updateTask(task)
    }

    func deleteTask(id: String) throws {
        try taskStore.deleteTask(id: id)
    }

    func getTask(id: String) throws -> TodoTask? {
        try taskStore.getTask(id: id)
    }

    func getAllTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try taskStore.getAllTasks(includeCompleted: includeCompleted)
    }

    func getTasksForList(_ listIdValue: String?, includeCompleted: Bool = false) throws -> [TodoTask] {
        try taskStore.getTasksForList(listIdValue, includeCompleted: includeCompleted)
    }

    func getTodayTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try taskStore.getTodayTasks(includeCompleted: includeCompleted)
    }

    func getScheduledTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try taskStore.getScheduledTasks(includeCompleted: includeCompleted)
    }

    func getFlaggedTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try taskStore.getFlaggedTasks(includeCompleted: includeCompleted)
    }

    func toggleTaskCompleted(id: String) throws {
        try taskStore.toggleTaskCompleted(id: id)
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
