import Foundation
import os

final class Database {
    static let shared = Database()

    let grdb: GRDBDatabase

    // Repositories
    private(set) lazy var sessions = SessionRepository(db: grdb)
    private(set) lazy var preferences = PreferenceRepository(db: grdb)
    private(set) lazy var tasks = TaskRepository(db: grdb)
    private(set) lazy var themes = ThemeRepository(db: grdb)
    private(set) lazy var agentTasks = AgentTaskRepository(db: grdb)
    private(set) lazy var activity = ActivityRepository(db: grdb)
    private(set) lazy var content = ContentRepository(db: grdb)

    private init() {
        do {
            grdb = try GRDBDatabase()
        } catch {
            Log.database.fault("Database initialization failed: \(error.localizedDescription, privacy: .public)")
            fatalError("Database initialization failed: \(error)")
        }
    }

    /// Test initializer — in-memory database.
    init(inMemory: Bool) throws {
        precondition(inMemory)
        grdb = try GRDBDatabase(inMemory: true)
    }

    // MARK: - Messages

    func saveMessage(_ message: ChatMessage, forSession session: String? = nil) throws {
        try sessions.saveMessage(message, forSession: session)
    }

    func loadRecentMessages(limit: Int = 50, forSession session: String? = nil) throws -> [ChatMessage] {
        try sessions.loadRecentMessages(limit: limit, forSession: session)
    }

    func clearMessages(forSession session: String? = nil) throws {
        try sessions.clearMessages(forSession: session)
    }

    func associateOrphanedMessages(withSession session: String) throws {
        try sessions.associateOrphanedMessages(withSession: session)
    }

    // MARK: - Sessions

    func saveSession(id sessionIdValue: String, title: String) throws {
        try sessions.saveSession(id: sessionIdValue, title: title)
    }

    func getRecentSessions(limit: Int = 20) throws -> [Session] {
        try sessions.getRecentSessions(limit: limit)
    }

    func deleteSession(id sessionIdValue: String) throws {
        try sessions.deleteSession(id: sessionIdValue)
    }

    // MARK: - Cost Tracking

    func logCost(amount: Double, sessionId session: String?) throws {
        try sessions.logCost(amount: amount, sessionId: session)
    }

    func getTotalCost(since date: Date) throws -> Double {
        try sessions.getTotalCost(since: date)
    }

    func getDailyCost() throws -> Double {
        try sessions.getDailyCost()
    }

    func getWeeklyCost() throws -> Double {
        try sessions.getWeeklyCost()
    }

    func getMonthlyCost() throws -> Double {
        try sessions.getMonthlyCost()
    }

    func getCostHistory(days: Int = 30) throws -> [(date: Date, amount: Double)] {
        try sessions.getCostHistory(days: days)
    }

    // MARK: - Notes

    func saveNote(title: String, content: String) throws -> String {
        try self.content.saveNote(title: title, content: content)
    }

    func updateNote(id: String, title: String? = nil, content: String? = nil) throws {
        try self.content.updateNote(id: id, title: title, content: content)
    }

    func loadNotes(limit: Int = 20) throws -> [(id: String, title: String, content: String)] {
        try self.content.loadNotes(limit: limit)
    }

    func deleteNote(id: String) throws {
        try self.content.deleteNote(id: id)
    }

    // MARK: - Preferences

    func setPreference(key: String, value: String) throws {
        try preferences.set(key: key, value: value)
    }

    func getPreference(key: String) throws -> String? {
        try preferences.get(key: key)
    }

    func deletePreference(key: String) throws {
        try preferences.delete(key: key)
    }

    // MARK: - Daily Briefs

    func saveDailyBrief(_ brief: DailyBrief) throws {
        try content.saveDailyBrief(brief)
    }

    func getDailyBrief(for date: String, type: DailyBrief.BriefType) throws -> DailyBrief? {
        try content.getDailyBrief(for: date, type: type)
    }

    func markBriefAsRead(id: String) throws {
        try content.markBriefAsRead(id: id)
    }

    func markBriefAsDismissed(id: String) throws {
        try content.markBriefAsDismissed(id: id)
    }

    func getRecentBriefs(limit: Int = 7) throws -> [DailyBrief] {
        try content.getRecentBriefs(limit: limit)
    }

    // MARK: - Daily Goals

    func saveDailyGoal(_ goal: DailyGoal) throws {
        try content.saveDailyGoal(goal)
    }

    func getGoalsForDate(_ date: String) throws -> [DailyGoal] {
        try content.getGoalsForDate(date)
    }

    func markGoalCompleted(id: String) throws {
        try content.markGoalCompleted(id: id)
    }

    func markGoalIncomplete(id: String) throws {
        try content.markGoalIncomplete(id: id)
    }

    func rollGoalToDate(id: String, newDate: String) throws {
        try content.rollGoalToDate(id: id, newDate: newDate)
    }

    func deleteGoal(id: String) throws {
        try content.deleteGoal(id: id)
    }

    func updateGoalText(id: String, text: String) throws {
        try content.updateGoalText(id: id, text: text)
    }

    func updateGoalPriority(id: String, priority: Int) throws {
        try content.updateGoalPriority(id: id, priority: priority)
    }

    func getIncompleteGoals(before date: String) throws -> [DailyGoal] {
        try content.getIncompleteGoals(before: date)
    }

    func getGoalCompletionRate(forDays days: Int = 7) throws -> Double {
        try content.getGoalCompletionRate(forDays: days)
    }

    // MARK: - Productivity Stats

    func saveProductivityStats(_ stats: ProductivityStats) throws {
        try content.saveProductivityStats(stats)
    }

    func getProductivityStats(for date: String) throws -> ProductivityStats? {
        try content.getProductivityStats(for: date)
    }

    func getProductivityStatsRange(from startDate: String, to endDate: String) throws -> [ProductivityStats] {
        try content.getProductivityStatsRange(from: startDate, to: endDate)
    }

    func getRecentProductivityStats(days: Int = 30) throws -> [ProductivityStats] {
        try content.getRecentProductivityStats(days: days)
    }

    // MARK: - Task Lists

    func createTaskList(name: String, color: String = "blue", icon: String = "list.bullet") throws -> String {
        try tasks.createTaskList(name: name, color: color, icon: icon)
    }

    func upsertTaskList(_ list: TaskList) throws {
        try tasks.upsertTaskList(list)
    }

    func getTaskLists() throws -> [TaskList] {
        try tasks.getTaskLists()
    }

    func updateTaskList(id: String, name: String? = nil, color: String? = nil, icon: String? = nil) throws {
        try tasks.updateTaskList(id: id, name: name, color: color, icon: icon)
    }

    func deleteTaskList(id: String) throws {
        try tasks.deleteTaskList(id: id)
    }

    func restoreListMembership(taskIds: [String], listId: String?) throws {
        try tasks.restoreListMembership(taskIds: taskIds, listId: listId)
    }

    // MARK: - Tasks

    func createTask(_ task: TodoTask) throws {
        try tasks.createTask(task)
    }

    func updateTask(_ task: TodoTask) throws {
        try tasks.updateTask(task)
    }

    func deleteTask(id: String) throws {
        try tasks.deleteTask(id: id)
    }

    func getTask(id: String) throws -> TodoTask? {
        try tasks.getTask(id: id)
    }

    func getAllTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try tasks.getAllTasks(includeCompleted: includeCompleted)
    }

    func getTasksForList(_ listIdValue: String?, includeCompleted: Bool = false) throws -> [TodoTask] {
        try tasks.getTasksForList(listIdValue, includeCompleted: includeCompleted)
    }

    func getTodayTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try tasks.getTodayTasks(includeCompleted: includeCompleted)
    }

    func getTasksForDay(_ date: Date, includeCompleted: Bool = false, includeOverdue: Bool = true) throws -> [TodoTask] {
        try tasks.getTasksForDay(date, includeCompleted: includeCompleted, includeOverdue: includeOverdue)
    }

    func getScheduledTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try tasks.getScheduledTasks(includeCompleted: includeCompleted)
    }

    func getFlaggedTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try tasks.getFlaggedTasks(includeCompleted: includeCompleted)
    }

    func toggleTaskCompleted(id: String) throws {
        try tasks.toggleTaskCompleted(id: id)
    }

    func getBlockedTasks(by taskId: String) throws -> [TodoTask] {
        try tasks.getBlockedTasks(by: taskId)
    }

    func unblockDependents(of taskId: String) throws {
        try tasks.unblockDependents(of: taskId)
    }

    // MARK: - Context Library

    func saveContextLibraryItem(_ item: ContextLibraryItem) throws {
        try content.saveContextLibraryItem(item)
    }

    func updateContextLibraryItem(id: String, title: String? = nil, content: String? = nil, autoInclude: Bool? = nil) throws {
        try self.content.updateContextLibraryItem(id: id, title: title, content: content, autoInclude: autoInclude)
    }

    func getAllContextLibraryItems() throws -> [ContextLibraryItem] {
        try content.getAllContextLibraryItems()
    }

    func getAutoIncludeContextLibraryItems() throws -> [ContextLibraryItem] {
        try content.getAutoIncludeContextLibraryItems()
    }

    func getContextLibraryItem(id: String) throws -> ContextLibraryItem? {
        try content.getContextLibraryItem(id: id)
    }

    func deleteContextLibraryItem(id: String) throws {
        try content.deleteContextLibraryItem(id: id)
    }

    func getContextLibraryItemCount() throws -> Int {
        try content.getContextLibraryItemCount()
    }

    // MARK: - Agent Tasks

    func createAgentTask(_ task: AgentTask) throws {
        try agentTasks.createAgentTask(task)
    }

    func getAgentTask(id: String) throws -> AgentTask? {
        try agentTasks.getAgentTask(id: id)
    }

    func getActiveAgentTasks() throws -> [AgentTask] {
        try agentTasks.getActiveAgentTasks()
    }

    func getAllAgentTasks() throws -> [AgentTask] {
        try agentTasks.getAllAgentTasks()
    }

    func getDueAgentTasks() throws -> [AgentTask] {
        try agentTasks.getDueTasks()
    }

    func getCheckinAgentTasks(phase: String) throws -> [AgentTask] {
        try agentTasks.getCheckinTasks(phase: phase)
    }

    func updateAgentTask(_ task: AgentTask) throws {
        try agentTasks.updateAgentTask(task)
    }

    func deleteAgentTask(id: String) throws {
        try agentTasks.deleteAgentTask(id: id)
    }

    func saveAgentTaskResult(_ result: AgentTaskResult) throws {
        try agentTasks.saveResult(result)
    }

    func getRecentAgentTaskResults(limit: Int = 20) throws -> [AgentTaskResult] {
        try agentTasks.getRecentResults(limit: limit)
    }

    func getPendingApprovalResults() throws -> [AgentTaskResult] {
        try agentTasks.getPendingApprovalResults()
    }

    // MARK: - Processed Emails

    func saveProcessedEmail(_ email: ProcessedEmail) throws {
        try content.saveProcessedEmail(email)
    }

    func saveProcessedEmails(_ emails: [ProcessedEmail]) throws {
        try content.saveProcessedEmails(emails)
    }

    func getProcessedEmails(filter: EmailFilter = .all, limit: Int = 50) throws -> [ProcessedEmail] {
        try content.getProcessedEmails(filter: filter, limit: limit)
    }

    func getEmailActionNeededCount() throws -> Int {
        try content.getEmailActionNeededCount()
    }

    func dismissProcessedEmail(id: String) throws {
        try content.dismissProcessedEmail(id: id)
    }

    // MARK: - Themes

    func createTheme(_ theme: Theme) throws {
        try themes.createTheme(theme)
    }

    func getThemes(includeArchived: Bool = false) throws -> [Theme] {
        try themes.getThemes(includeArchived: includeArchived)
    }

    func getTheme(id: String) throws -> Theme? {
        try themes.getTheme(id: id)
    }

    func getLooseTheme() throws -> Theme {
        try themes.getLooseTheme()
    }

    func updateTheme(_ theme: Theme) throws {
        try themes.updateTheme(theme)
    }

    func archiveTheme(id: String) throws {
        try themes.archiveTheme(id: id)
    }

    func deleteTheme(id: String) throws {
        try themes.deleteTheme(id: id)
    }

    func addItemToTheme(themeId: String, itemType: ThemeItemType, itemId: String) throws {
        try themes.addItemToTheme(themeId: themeId, itemType: itemType, itemId: itemId)
    }

    func removeItemFromTheme(themeId: String, itemType: ThemeItemType, itemId: String) throws {
        try themes.removeItemFromTheme(themeId: themeId, itemType: itemType, itemId: itemId)
    }

    func getItemsForTheme(id themeId: String, type: ThemeItemType? = nil) throws -> [ThemeItem] {
        try themes.getItemsForTheme(id: themeId, type: type)
    }

    func getThemesForItem(itemType: ThemeItemType, itemId: String) throws -> [Theme] {
        try themes.getThemesForItem(itemType: itemType, itemId: itemId)
    }

    func getTaskCountForTheme(id themeId: String) throws -> Int {
        try themes.getTaskCountForTheme(id: themeId)
    }

    func getTaskIdsForTheme(id themeId: String) throws -> [String] {
        try themes.getTaskIdsForTheme(id: themeId)
    }

    func addThemeKeyword(_ keyword: String, toTheme themeId: String) throws {
        try themes.addKeyword(keyword, toTheme: themeId)
    }

    func getThemeKeywords(forTheme themeId: String) throws -> [String] {
        try themes.getKeywords(forTheme: themeId)
    }

    func removeThemeKeyword(_ keyword: String, fromTheme themeId: String) throws {
        try themes.removeKeyword(keyword, fromTheme: themeId)
    }

    // MARK: - Theme Blocks

    func createThemeBlock(_ block: ThemeBlock) throws {
        try themes.createThemeBlock(block)
    }

    func getThemeBlocksForTheme(id themeId: String) throws -> [ThemeBlock] {
        try themes.getThemeBlocksForTheme(id: themeId)
    }

    func getThemeBlock(id blockId: String) throws -> ThemeBlock? {
        try themes.getThemeBlock(id: blockId)
    }

    func getThemeBlocksForDay(_ date: Date) throws -> [ThemeBlock] {
        try themes.getThemeBlocksForDay(date)
    }

    func updateThemeBlock(_ block: ThemeBlock) throws {
        try themes.updateThemeBlock(block)
    }

    func deleteThemeBlock(id blockId: String) throws {
        try themes.deleteThemeBlock(id: blockId)
    }

    func getActiveTheme(at date: Date = Date()) throws -> Theme? {
        try themes.getActiveTheme(at: date)
    }

    // MARK: - Behavior Tracking

    func recordBehaviorEvent(type: BehaviorEventType, entityId: String? = nil, metadata: [String: String] = [:]) throws {
        try activity.recordBehaviorEvent(type: type, entityId: entityId, metadata: metadata)
    }

    func getBehaviorEvents(type: BehaviorEventType? = nil, since: Date? = nil, limit: Int = 100) throws -> [BehaviorEvent] {
        try activity.getBehaviorEvents(type: type, since: since, limit: limit)
    }

    func getEventCountByHour(type: BehaviorEventType, days: Int) throws -> [Int: Int] {
        try activity.getEventCountByHour(type: type, days: days)
    }

    func getTotalCount(type: BehaviorEventType, since: Date) throws -> Int {
        try activity.getTotalCount(type: type, since: since)
    }

    func getEventCountByDayOfWeek(type: BehaviorEventType, days: Int) throws -> [Int: Int] {
        try activity.getEventCountByDayOfWeek(type: type, days: days)
    }

    // MARK: - Operation Events

    func saveOperationEvent(_ event: OperationEvent) throws {
        try activity.saveOperationEvent(event)
    }

    func getRecentOperationEvents(limit: Int = 100) throws -> [OperationEvent] {
        try activity.getRecentOperationEvents(limit: limit)
    }

    func getOperationEvents(
        limit: Int = 100,
        status: OperationStatus? = nil,
        correlationId: String? = nil
    ) throws -> [OperationEvent] {
        try activity.getOperationEvents(limit: limit, status: status, correlationId: correlationId)
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
