import XCTest
import SQLite
@testable import Conductor

final class DatabaseTests: XCTestCase {
    func test_loadRecentMessages_returnsMostRecentN_inChronologicalOrder() throws {
        let db = Database(connection: try Connection(.inMemory))

        let t1 = Date(timeIntervalSince1970: 1)
        let t2 = Date(timeIntervalSince1970: 2)
        let t3 = Date(timeIntervalSince1970: 3)

        let m1 = ChatMessage(role: .user, content: "m1", timestamp: t1)
        let m2 = ChatMessage(role: .user, content: "m2", timestamp: t2)
        let m3 = ChatMessage(role: .user, content: "m3", timestamp: t3)

        try db.saveMessage(m1, forSession: nil)
        try db.saveMessage(m2, forSession: nil)
        try db.saveMessage(m3, forSession: nil)

        let recent = try db.loadRecentMessages(limit: 2, forSession: nil)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].content, "m2")
        XCTAssertEqual(recent[1].content, "m3")
    }

    func test_associateOrphanedMessages_movesRecentNullSessionMessagesIntoSession() throws {
        let db = Database(connection: try Connection(.inMemory))
        let message = ChatMessage(role: .user, content: "orphan")
        try db.saveMessage(message, forSession: nil)

        try db.associateOrphanedMessages(withSession: "s1")
        let sessionMessages = try db.loadRecentMessages(limit: 10, forSession: "s1")
        XCTAssertEqual(sessionMessages.map(\.content), ["orphan"])
    }

    func test_preferences_setGetDelete() throws {
        let db = Database(connection: try Connection(.inMemory))

        try db.setPreference(key: "k", value: "v")
        XCTAssertEqual(try db.getPreference(key: "k"), "v")

        try db.deletePreference(key: "k")
        XCTAssertNil(try db.getPreference(key: "k"))
    }

    func test_saveSession_upsertsTitleAndLastUsed() throws {
        let db = Database(connection: try Connection(.inMemory))

        try db.saveSession(id: "s1", title: "First")
        try db.saveSession(id: "s1", title: "Updated")

        let sessions = try db.getRecentSessions(limit: 10)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "s1")
        XCTAssertEqual(sessions[0].title, "Updated")
    }

    // MARK: - Daily Planning Tests

    func test_dailyGoals_CRUD() throws {
        let db = Database(connection: try Connection(.inMemory))
        let today = "2024-01-15"

        // Create
        let goal = DailyGoal(date: today, goalText: "Ship MVP", priority: 1)
        try db.saveDailyGoal(goal)

        // Read
        let goals = try db.getGoalsForDate(today)
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(goals[0].goalText, "Ship MVP")
        XCTAssertEqual(goals[0].priority, 1)
        XCTAssertFalse(goals[0].isCompleted)

        // Update
        try db.updateGoalText(id: goal.id, text: "Ship MVP v2")
        let updatedGoals = try db.getGoalsForDate(today)
        XCTAssertEqual(updatedGoals[0].goalText, "Ship MVP v2")

        // Complete
        try db.markGoalCompleted(id: goal.id)
        let completedGoals = try db.getGoalsForDate(today)
        XCTAssertTrue(completedGoals[0].isCompleted)

        // Delete
        try db.deleteGoal(id: goal.id)
        let afterDelete = try db.getGoalsForDate(today)
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func test_dailyGoals_rollover() throws {
        let db = Database(connection: try Connection(.inMemory))
        let today = "2024-01-15"
        let tomorrow = "2024-01-16"

        let goal = DailyGoal(date: today, goalText: "Incomplete task", priority: 1)
        try db.saveDailyGoal(goal)

        // Roll to tomorrow
        try db.rollGoalToDate(id: goal.id, newDate: tomorrow)

        let todayGoals = try db.getGoalsForDate(today)
        XCTAssertEqual(todayGoals[0].rolledTo, tomorrow)
        XCTAssertTrue(todayGoals[0].isRolled)
    }

    func test_dailyGoals_incompleteQuery() throws {
        let db = Database(connection: try Connection(.inMemory))

        // Create goals for multiple days
        let goal1 = DailyGoal(date: "2024-01-13", goalText: "Old incomplete", priority: 1)
        let goal2 = DailyGoal(date: "2024-01-14", goalText: "Yesterday incomplete", priority: 1)
        let goal3 = DailyGoal(date: "2024-01-15", goalText: "Today", priority: 1)

        try db.saveDailyGoal(goal1)
        try db.saveDailyGoal(goal2)
        try db.saveDailyGoal(goal3)

        // Complete one
        try db.markGoalCompleted(id: goal1.id)

        // Query incomplete before today
        let incomplete = try db.getIncompleteGoals(before: "2024-01-15")
        XCTAssertEqual(incomplete.count, 1)
        XCTAssertEqual(incomplete[0].goalText, "Yesterday incomplete")
    }

    func test_dailyBriefs_saveAndRetrieve() throws {
        let db = Database(connection: try Connection(.inMemory))
        let today = "2024-01-15"

        let brief = DailyBrief(
            date: today,
            briefType: .morning,
            content: "Good morning! You have 3 meetings today."
        )
        try db.saveDailyBrief(brief)

        let retrieved = try db.getDailyBrief(for: today, type: .morning)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.content, "Good morning! You have 3 meetings today.")
        XCTAssertNil(retrieved?.readAt)
        XCTAssertFalse(retrieved?.dismissed ?? true)
    }

    func test_dailyBriefs_markAsRead() throws {
        let db = Database(connection: try Connection(.inMemory))
        let today = "2024-01-15"

        let brief = DailyBrief(date: today, briefType: .morning, content: "Test")
        try db.saveDailyBrief(brief)

        try db.markBriefAsRead(id: brief.id)

        let retrieved = try db.getDailyBrief(for: today, type: .morning)
        XCTAssertNotNil(retrieved?.readAt)
    }

    func test_dailyBriefs_dismiss() throws {
        let db = Database(connection: try Connection(.inMemory))
        let today = "2024-01-15"

        let brief = DailyBrief(date: today, briefType: .morning, content: "Test")
        try db.saveDailyBrief(brief)

        try db.markBriefAsDismissed(id: brief.id)

        let retrieved = try db.getDailyBrief(for: today, type: .morning)
        XCTAssertTrue(retrieved?.dismissed ?? false)
    }

    func test_goalCompletionRate() throws {
        let db = Database(connection: try Connection(.inMemory))

        // Use today's date to ensure goals fall within the query range
        let today = DailyPlanningService.todayDateString

        // Create 4 goals for today
        let goal1 = DailyGoal(date: today, goalText: "G1", priority: 1)
        let goal2 = DailyGoal(date: today, goalText: "G2", priority: 2)
        let goal3 = DailyGoal(date: today, goalText: "G3", priority: 3)
        let goal4 = DailyGoal(date: today, goalText: "G4", priority: 4)

        try db.saveDailyGoal(goal1)
        try db.saveDailyGoal(goal2)
        try db.saveDailyGoal(goal3)
        try db.saveDailyGoal(goal4)

        // Complete 2 of them
        try db.markGoalCompleted(id: goal1.id)
        try db.markGoalCompleted(id: goal3.id)

        // Completion rate should be 50%
        let rate = try db.getGoalCompletionRate(forDays: 7)
        XCTAssertEqual(rate, 0.5, accuracy: 0.001)
    }

    // MARK: - Productivity Stats Tests

    func test_productivityStats_saveAndRetrieve() throws {
        let db = Database(connection: try Connection(.inMemory))
        let today = "2024-01-15"

        let stats = ProductivityStats(
            date: today,
            goalsCompleted: 3,
            goalsTotal: 5,
            meetingsCount: 4,
            meetingsHours: 3.5,
            focusHours: 4.0,
            overdueCount: 2
        )
        try db.saveProductivityStats(stats)

        let retrieved = try XCTUnwrap(db.getProductivityStats(for: today))
        XCTAssertEqual(retrieved.date, today)
        XCTAssertEqual(retrieved.goalsCompleted, 3)
        XCTAssertEqual(retrieved.goalsTotal, 5)
        XCTAssertEqual(retrieved.meetingsCount, 4)
        XCTAssertEqual(retrieved.meetingsHours, 3.5, accuracy: 0.01)
        XCTAssertEqual(retrieved.focusHours, 4.0, accuracy: 0.01)
        XCTAssertEqual(retrieved.overdueCount, 2)
        XCTAssertEqual(retrieved.completionRate, 0.6, accuracy: 0.01)
    }

    func test_productivityStats_rangeQuery() throws {
        let db = Database(connection: try Connection(.inMemory))

        // Create stats for multiple days
        let stats1 = ProductivityStats(date: "2024-01-13", goalsCompleted: 2, goalsTotal: 3, meetingsCount: 2, meetingsHours: 1.5, focusHours: 5.0, overdueCount: 0)
        let stats2 = ProductivityStats(date: "2024-01-14", goalsCompleted: 3, goalsTotal: 4, meetingsCount: 3, meetingsHours: 2.0, focusHours: 4.0, overdueCount: 1)
        let stats3 = ProductivityStats(date: "2024-01-15", goalsCompleted: 1, goalsTotal: 3, meetingsCount: 5, meetingsHours: 4.0, focusHours: 2.0, overdueCount: 2)

        try db.saveProductivityStats(stats1)
        try db.saveProductivityStats(stats2)
        try db.saveProductivityStats(stats3)

        // Query range
        let range = try db.getProductivityStatsRange(from: "2024-01-13", to: "2024-01-14")
        XCTAssertEqual(range.count, 2)
        XCTAssertEqual(range[0].date, "2024-01-13")
        XCTAssertEqual(range[1].date, "2024-01-14")
    }

    // MARK: - Tasks Tests

    func test_tasksAndLists_CRUD_andQueries() throws {
        let db = Database(connection: try Connection(.inMemory))

        let listPersonal = try db.createTaskList(name: "Personal", color: "red", icon: "heart")
        let listWork = try db.createTaskList(name: "Work")

        var lists = try db.getTaskLists()
        XCTAssertEqual(lists.count, 2)
        XCTAssertEqual(lists[0].name, "Personal")
        XCTAssertEqual(lists[1].name, "Work")

        try db.updateTaskList(id: listWork, name: "Work (Updated)", color: "blue", icon: "briefcase")
        lists = try db.getTaskLists()
        XCTAssertEqual(lists.first(where: { $0.id == listWork })?.name, "Work (Updated)")

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let overdue = calendar.date(byAdding: .hour, value: -1, to: startOfToday)!
        let dueToday = calendar.date(byAdding: .hour, value: 10, to: startOfToday)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let dueTomorrow = calendar.date(byAdding: .hour, value: 9, to: tomorrow)!

        let t1 = TodoTask(title: "Overdue", dueDate: overdue, listId: listPersonal, priority: .medium)
        let t2 = TodoTask(title: "Today", dueDate: dueToday, listId: listPersonal, priority: .high)
        let t3 = TodoTask(title: "Tomorrow", dueDate: dueTomorrow, listId: nil, priority: .none)
        let t4 = TodoTask(title: "Completed High", dueDate: dueToday, listId: listWork, priority: .high, isCompleted: true, completedAt: Date())

        try db.createTask(t1)
        try db.createTask(t2)
        try db.createTask(t3)
        try db.createTask(t4)

        let todayTasks = try db.getTodayTasks(includeCompleted: false)
        XCTAssertEqual(Set(todayTasks.map(\.title)), Set(["Overdue", "Today"]))

        let scheduled = try db.getScheduledTasks(includeCompleted: false)
        XCTAssertEqual(Set(scheduled.map(\.title)), Set(["Overdue", "Today", "Tomorrow"]))

        let flagged = try db.getFlaggedTasks(includeCompleted: false)
        XCTAssertEqual(flagged.map(\.title), ["Today"])

        let personalTasks = try db.getTasksForList(listPersonal, includeCompleted: false)
        XCTAssertEqual(Set(personalTasks.map(\.title)), Set(["Overdue", "Today"]))

        // Deleting a list should not delete tasks; it should clear list_id.
        try db.deleteTaskList(id: listPersonal)
        XCTAssertEqual(try db.getTaskLists().count, 1)

        let t1After = try XCTUnwrap(db.getTask(id: t1.id))
        XCTAssertNil(t1After.listId)

        let t2After = try XCTUnwrap(db.getTask(id: t2.id))
        XCTAssertNil(t2After.listId)
    }

    func test_toggleTaskCompleted_setsAndClearsCompletedAt() throws {
        let db = Database(connection: try Connection(.inMemory))
        let t1 = TodoTask(title: "Toggle me")
        try db.createTask(t1)

        try db.toggleTaskCompleted(id: t1.id)
        let completed = try XCTUnwrap(db.getTask(id: t1.id))
        XCTAssertTrue(completed.isCompleted)
        XCTAssertNotNil(completed.completedAt)

        try db.toggleTaskCompleted(id: t1.id)
        let incomplete = try XCTUnwrap(db.getTask(id: t1.id))
        XCTAssertFalse(incomplete.isCompleted)
        XCTAssertNil(incomplete.completedAt)
    }
}
