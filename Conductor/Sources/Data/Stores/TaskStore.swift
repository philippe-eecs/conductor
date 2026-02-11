import Foundation
import SQLite

struct TaskStore: DatabaseStore {
    let database: Database

    // MARK: - Schema

    private let tasks = Table("tasks")
    private let taskLists = Table("task_lists")

    private let taskId = Expression<String>("id")
    private let taskTitle = Expression<String>("title")
    private let taskNotes = Expression<String?>("notes")
    private let taskDueDate = Expression<Double?>("due_date")
    private let taskListId = Expression<String?>("list_id")
    private let taskPriority = Expression<Int>("priority")
    private let taskCompleted = Expression<Int>("completed")
    private let taskCompletedAt = Expression<Double?>("completed_at")
    private let taskCreatedAt = Expression<Double>("created_at")
    private let taskUpdatedAt = Expression<Double>("updated_at")

    private let listId = Expression<String>("id")
    private let listName = Expression<String>("name")
    private let listColor = Expression<String>("color")
    private let listIcon = Expression<String>("icon")
    private let listSortOrder = Expression<Int>("sort_order")
    private let listCreatedAt = Expression<Double>("created_at")

    static func createTables(in db: Connection) throws {
        // Tasks table
        do {
            let tasks = Table("tasks")
            let taskId = Expression<String>("id")
            let taskTitle = Expression<String>("title")
            let taskNotes = Expression<String?>("notes")
            let taskDueDate = Expression<Double?>("due_date")
            let taskListId = Expression<String?>("list_id")
            let taskPriority = Expression<Int>("priority")
            let taskCompleted = Expression<Int>("completed")
            let taskCompletedAt = Expression<Double?>("completed_at")
            let taskCreatedAt = Expression<Double>("created_at")
            let taskUpdatedAt = Expression<Double>("updated_at")

            try db.run(tasks.create(ifNotExists: true) { t in
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
            try db.run(tasks.createIndex(taskListId, ifNotExists: true))
            try db.run(tasks.createIndex(taskDueDate, ifNotExists: true))
            try db.run(tasks.createIndex(taskCompleted, ifNotExists: true))
        }

        // Task lists table
        do {
            let taskLists = Table("task_lists")
            let listId = Expression<String>("id")
            let listName = Expression<String>("name")
            let listColor = Expression<String>("color")
            let listIcon = Expression<String>("icon")
            let listSortOrder = Expression<Int>("sort_order")
            let listCreatedAt = Expression<Double>("created_at")

            try db.run(taskLists.create(ifNotExists: true) { t in
                t.column(listId, primaryKey: true)
                t.column(listName)
                t.column(listColor, defaultValue: "blue")
                t.column(listIcon, defaultValue: "list.bullet")
                t.column(listSortOrder, defaultValue: 0)
                t.column(listCreatedAt)
            })
            try db.run(taskLists.createIndex(listSortOrder, ifNotExists: true))
        }
    }

    // MARK: - Task Lists

    func createTaskList(name: String, color: String = "blue", icon: String = "list.bullet") throws -> String {
        try perform { db in
            let listIdValue = UUID().uuidString
            let now = Date().timeIntervalSince1970
            let maxOrder = try db.scalar(taskLists.select(listSortOrder.max)) ?? 0

            let insert = taskLists.insert(
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

    func upsertTaskList(_ list: TaskList) throws {
        try perform { db in
            let insert = taskLists.insert(or: .replace,
                listId <- list.id,
                listName <- list.name,
                listColor <- list.color,
                listIcon <- list.icon,
                listSortOrder <- list.sortOrder,
                listCreatedAt <- Date().timeIntervalSince1970
            )
            try db.run(insert)
        }
    }

    func getTaskLists() throws -> [TaskList] {
        try perform { db in
            let query = taskLists.order(listSortOrder.asc)
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
            let list = taskLists.filter(listId == id)
            var setters: [Setter] = []

            if let name { setters.append(listName <- name) }
            if let color { setters.append(listColor <- color) }
            if let icon { setters.append(listIcon <- icon) }

            guard !setters.isEmpty else { return }
            try db.run(list.update(setters))
        }
    }

    func deleteTaskList(id: String) throws {
        try perform { db in
            try db.run(taskLists.filter(listId == id).delete())
            try db.run(tasks.filter(taskListId == id).update(taskListId <- nil as String?))
        }
    }

    // MARK: - Tasks

    func createTask(_ task: TodoTask) throws {
        try perform { db in
            let now = Date().timeIntervalSince1970
            let insert = tasks.insert(
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
            let taskRow = tasks.filter(taskId == task.id)

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
            try db.run(tasks.filter(taskId == id).delete())
        }
    }

    func getTask(id: String) throws -> TodoTask? {
        try perform { db in
            if let row = try db.pluck(tasks.filter(taskId == id)) {
                return rowToTask(row)
            }
            return nil
        }
    }

    func getAllTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            var query = tasks.order(taskDueDate.asc, taskPriority.desc, taskCreatedAt.desc)
            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }

            var result: [TodoTask] = []
            for row in try db.prepare(query) {
                result.append(rowToTask(row))
            }
            return result
        }
    }

    func getTasksForList(_ listIdValue: String?, includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            var query: SQLite.Table
            if let listIdValue {
                query = tasks.filter(taskListId == listIdValue)
            } else {
                query = tasks.filter(taskListId == nil)
            }

            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }

            query = query.order(taskDueDate.asc, taskPriority.desc, taskCreatedAt.desc)

            var result: [TodoTask] = []
            for row in try db.prepare(query) {
                result.append(rowToTask(row))
            }
            return result
        }
    }

    func getTodayTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date()).timeIntervalSince1970
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!.timeIntervalSince1970

            var query = tasks.filter(
                (taskDueDate != nil && taskDueDate >= startOfDay && taskDueDate < endOfDay) ||
                (taskDueDate != nil && taskDueDate < startOfDay && taskCompleted == 0)  // Overdue
            )

            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }

            query = query.order(taskDueDate.asc, taskPriority.desc)

            var result: [TodoTask] = []
            for row in try db.prepare(query) {
                result.append(rowToTask(row))
            }
            return result
        }
    }

    func getTasksForDay(_ date: Date, includeCompleted: Bool = false, includeOverdue: Bool = true) throws -> [TodoTask] {
        try perform { db in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date).timeIntervalSince1970
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!.timeIntervalSince1970

            var query: SQLite.Table
            if includeOverdue {
                query = tasks.filter(
                    (taskDueDate != nil && taskDueDate >= startOfDay && taskDueDate < endOfDay) ||
                    (taskDueDate != nil && taskDueDate < startOfDay && taskCompleted == 0)
                )
            } else {
                query = tasks.filter(
                    taskDueDate != nil && taskDueDate >= startOfDay && taskDueDate < endOfDay
                )
            }
            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }

            query = query.order(taskDueDate.asc, taskPriority.desc, taskCreatedAt.desc)

            var result: [TodoTask] = []
            for row in try db.prepare(query) {
                result.append(rowToTask(row))
            }
            return result
        }
    }

    func getScheduledTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            var query = tasks.filter(taskDueDate != nil)
            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }
            query = query.order(taskDueDate.asc, taskPriority.desc)

            var result: [TodoTask] = []
            for row in try db.prepare(query) {
                result.append(rowToTask(row))
            }
            return result
        }
    }

    func getFlaggedTasks(includeCompleted: Bool = false) throws -> [TodoTask] {
        try perform { db in
            var query = tasks.filter(taskPriority == TodoTask.Priority.high.rawValue)
            if !includeCompleted {
                query = query.filter(taskCompleted == 0)
            }
            query = query.order(taskDueDate.asc, taskCreatedAt.desc)

            var result: [TodoTask] = []
            for row in try db.prepare(query) {
                result.append(rowToTask(row))
            }
            return result
        }
    }

    func toggleTaskCompleted(id: String) throws {
        try perform { db in
            let taskRow = tasks.filter(taskId == id)
            if let row = try db.pluck(taskRow) {
                let isCompleted = row[taskCompleted] == 1
                let now = Date().timeIntervalSince1970

                if isCompleted {
                    try db.run(taskRow.update(
                        taskCompleted <- 0,
                        taskCompletedAt <- nil as Double?,
                        taskUpdatedAt <- now
                    ))
                } else {
                    try db.run(taskRow.update(
                        taskCompleted <- 1,
                        taskCompletedAt <- now,
                        taskUpdatedAt <- now
                    ))
                }
            }
        }
    }

    func restoreListMembership(taskIds: [String], listId: String?) throws {
        guard !taskIds.isEmpty else { return }
        try perform { db in
            for id in taskIds {
                try db.run(tasks.filter(taskId == id).update(taskListId <- listId))
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
