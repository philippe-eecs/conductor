import Foundation
import GRDB

struct TaskRepository: Sendable {
    let db: GRDBDatabase

    // MARK: - Task Lists

    func createTaskList(name: String, color: String = "blue", icon: String = "list.bullet") throws -> String {
        let id = UUID().uuidString
        try db.write { db in
            let maxOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) FROM task_lists") ?? -1
            try db.execute(
                sql: """
                    INSERT INTO task_lists (id, name, color, icon, sort_order, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id, name, color, icon, maxOrder + 1, Date().timeIntervalSince1970]
            )
        }
        return id
    }

    func upsertTaskList(_ list: TaskList) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO task_lists (id, name, color, icon, sort_order, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET name = ?, color = ?, icon = ?, sort_order = ?
                    """,
                arguments: [
                    list.id, list.name, list.color, list.icon, list.sortOrder,
                    Date().timeIntervalSince1970,
                    list.name, list.color, list.icon, list.sortOrder,
                ]
            )
        }
    }

    func getTaskLists() throws -> [TaskList] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM task_lists ORDER BY sort_order ASC")
            return rows.map { Self.parseTaskList(from: $0) }
        }
    }

    func updateTaskList(id: String, name: String? = nil, color: String? = nil, icon: String? = nil) throws {
        try db.write { db in
            var sets: [String] = []
            var args: [DatabaseValueConvertible?] = []
            if let name { sets.append("name = ?"); args.append(name) }
            if let color { sets.append("color = ?"); args.append(color) }
            if let icon { sets.append("icon = ?"); args.append(icon) }
            guard !sets.isEmpty else { return }
            args.append(id)
            try db.execute(
                sql: "UPDATE task_lists SET \(sets.joined(separator: ", ")) WHERE id = ?",
                arguments: StatementArguments(args)!
            )
        }
    }

    func deleteTaskList(id: String) throws {
        try db.write { db in
            // Orphan tasks from the deleted list
            try db.execute(sql: "UPDATE tasks SET list_id = NULL WHERE list_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM task_lists WHERE id = ?", arguments: [id])
        }
    }

    func restoreListMembership(taskIds: [String], listId: String?) throws {
        guard !taskIds.isEmpty else { return }
        try db.write { db in
            let placeholders = taskIds.map { _ in "?" }.joined(separator: ", ")
            var args: [DatabaseValueConvertible?] = [listId]
            args.append(contentsOf: taskIds.map { $0 as DatabaseValueConvertible? })
            try db.execute(
                sql: "UPDATE tasks SET list_id = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments(args)!
            )
        }
    }

    // MARK: - Tasks

    func createTask(_ task: TodoTask) throws {
        try db.write { db in
            let now = Date().timeIntervalSince1970
            try db.execute(
                sql: """
                    INSERT INTO tasks
                    (id, title, notes, due_date, list_id, priority, completed, completed_at,
                     created_at, updated_at, blocked_by_task_id, blocked_offset_days)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    task.id, task.title, task.notes,
                    task.dueDate?.timeIntervalSince1970,
                    task.listId, task.priority.rawValue,
                    task.isCompleted ? 1 : 0,
                    task.completedAt?.timeIntervalSince1970,
                    task.createdAt.timeIntervalSince1970, now,
                    task.blockedByTaskId, task.blockedOffsetDays,
                ]
            )
        }
    }

    func updateTask(_ task: TodoTask) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE tasks SET
                    title = ?, notes = ?, due_date = ?, list_id = ?, priority = ?,
                    completed = ?, completed_at = ?, updated_at = ?,
                    blocked_by_task_id = ?, blocked_offset_days = ?
                    WHERE id = ?
                    """,
                arguments: [
                    task.title, task.notes,
                    task.dueDate?.timeIntervalSince1970,
                    task.listId, task.priority.rawValue,
                    task.isCompleted ? 1 : 0,
                    task.completedAt?.timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                    task.blockedByTaskId, task.blockedOffsetDays,
                    task.id,
                ]
            )
        }
    }

    func deleteTask(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [id])
        }
    }

    func getTask(id: String) throws -> TodoTask? {
        try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM tasks WHERE id = ?", arguments: [id])
            else { return nil }
            return Self.parseTask(from: row)
        }
    }

    func getAllTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try db.read { db in
            let sql = includeCompleted
                ? "SELECT * FROM tasks ORDER BY priority DESC, created_at ASC"
                : "SELECT * FROM tasks WHERE completed = 0 ORDER BY priority DESC, created_at ASC"
            return try Row.fetchAll(db, sql: sql).map { Self.parseTask(from: $0) }
        }
    }

    func getTasksForList(_ listId: String?, includeCompleted: Bool = false) throws -> [TodoTask] {
        try db.read { db in
            let sql: String
            let args: StatementArguments
            if let listId {
                sql = includeCompleted
                    ? "SELECT * FROM tasks WHERE list_id = ? ORDER BY priority DESC, created_at ASC"
                    : "SELECT * FROM tasks WHERE list_id = ? AND completed = 0 ORDER BY priority DESC, created_at ASC"
                args = [listId]
            } else {
                sql = includeCompleted
                    ? "SELECT * FROM tasks WHERE list_id IS NULL ORDER BY priority DESC, created_at ASC"
                    : "SELECT * FROM tasks WHERE list_id IS NULL AND completed = 0 ORDER BY priority DESC, created_at ASC"
                args = []
            }
            return try Row.fetchAll(db, sql: sql, arguments: args).map { Self.parseTask(from: $0) }
        }
    }

    func getTodayTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try getTasksForDay(Date(), includeCompleted: includeCompleted, includeOverdue: true)
    }

    func getTasksForDay(_ date: Date, includeCompleted: Bool = false, includeOverdue: Bool = true) throws -> [TodoTask] {
        try db.read { db in
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date).timeIntervalSince1970
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!.timeIntervalSince1970

            var conditions = ["(due_date >= ? AND due_date < ?)"]
            var args: [DatabaseValueConvertible] = [dayStart, dayEnd]

            if includeOverdue {
                conditions.append("(due_date < ? AND completed = 0)")
                args.append(dayStart)
            }

            let dueDateClause = conditions.joined(separator: " OR ")
            let completedClause = includeCompleted ? "" : " AND completed = 0"

            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM tasks WHERE (\(dueDateClause))\(completedClause) ORDER BY priority DESC, due_date ASC",
                arguments: StatementArguments(args)!
            ).map { Self.parseTask(from: $0) }
        }
    }

    func getScheduledTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try db.read { db in
            let sql = includeCompleted
                ? "SELECT * FROM tasks WHERE due_date IS NOT NULL ORDER BY due_date ASC"
                : "SELECT * FROM tasks WHERE due_date IS NOT NULL AND completed = 0 ORDER BY due_date ASC"
            return try Row.fetchAll(db, sql: sql).map { Self.parseTask(from: $0) }
        }
    }

    func getFlaggedTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try db.read { db in
            let highPriority = TodoTask.Priority.high.rawValue
            let sql = includeCompleted
                ? "SELECT * FROM tasks WHERE priority >= ? ORDER BY priority DESC, created_at ASC"
                : "SELECT * FROM tasks WHERE priority >= ? AND completed = 0 ORDER BY priority DESC, created_at ASC"
            return try Row.fetchAll(db, sql: sql, arguments: [highPriority]).map { Self.parseTask(from: $0) }
        }
    }

    func toggleTaskCompleted(id: String) throws {
        try db.write { db in
            let now = Date().timeIntervalSince1970
            try db.execute(
                sql: """
                    UPDATE tasks SET
                    completed = CASE WHEN completed = 0 THEN 1 ELSE 0 END,
                    completed_at = CASE WHEN completed = 0 THEN ? ELSE NULL END,
                    updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [now, now, id]
            )
        }
    }

    func getBlockedTasks(by taskId: String) throws -> [TodoTask] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM tasks WHERE blocked_by_task_id = ?",
                arguments: [taskId]
            ).map { Self.parseTask(from: $0) }
        }
    }

    func unblockDependents(of taskId: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE tasks SET blocked_by_task_id = NULL, blocked_offset_days = NULL WHERE blocked_by_task_id = ?",
                arguments: [taskId]
            )
        }
    }

    // MARK: - Parsing

    static func parseTask(from row: Row) -> TodoTask {
        let dueDateVal: Double? = row["due_date"]
        let completedAtVal: Double? = row["completed_at"]

        return TodoTask(
            id: row["id"],
            title: row["title"],
            notes: row["notes"],
            dueDate: dueDateVal.map { Date(timeIntervalSince1970: $0) },
            listId: row["list_id"],
            priority: TodoTask.Priority(rawValue: row["priority"]) ?? .none,
            isCompleted: (row["completed"] as Int) != 0,
            completedAt: completedAtVal.map { Date(timeIntervalSince1970: $0) },
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            blockedByTaskId: row["blocked_by_task_id"],
            blockedOffsetDays: row["blocked_offset_days"]
        )
    }

    private static func parseTaskList(from row: Row) -> TaskList {
        TaskList(
            id: row["id"],
            name: row["name"],
            color: row["color"],
            icon: row["icon"],
            sortOrder: row["sort_order"]
        )
    }
}
