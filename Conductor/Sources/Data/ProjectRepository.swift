import Foundation
import GRDB

struct ProjectRepository {
    let db: AppDatabase

    // MARK: - Projects

    func allProjects(includeArchived: Bool = false) throws -> [Project] {
        try db.dbQueue.read { db in
            if includeArchived {
                return try Project.order(Column("name")).fetchAll(db)
            } else {
                return try Project.filter(Column("archived") == false).order(Column("name")).fetchAll(db)
            }
        }
    }

    func project(id: Int64) throws -> Project? {
        try db.dbQueue.read { db in
            try Project.fetchOne(db, key: id)
        }
    }

    @discardableResult
    func createProject(name: String, color: String = "#007AFF", description: String? = nil) throws -> Project {
        let now = Date()
        let project = Project(
            name: name, color: color, description: description,
            archived: false, createdAt: now, updatedAt: now
        )
        return try db.dbQueue.write { db in
            try project.inserted(db)
        }
    }

    func updateProject(_ project: Project) throws {
        var updated = project
        updated.updatedAt = Date()
        try db.dbQueue.write { db in
            try updated.update(db)
        }
    }

    func deleteProject(id: Int64) throws {
        try db.dbQueue.write { db in
            _ = try Project.deleteOne(db, key: id)
        }
    }

    func archiveProject(id: Int64) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE projects SET archived = 1, updatedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    // MARK: - Todos

    func todosForProject(_ projectId: Int64?) throws -> [Todo] {
        try db.dbQueue.read { db in
            if let projectId {
                return try Todo.filter(Column("projectId") == projectId)
                    .order(Column("completed"), Column("priority").desc, Column("createdAt").desc)
                    .fetchAll(db)
            } else {
                // Inbox: todos without a project
                return try Todo.filter(Column("projectId") == nil)
                    .order(Column("completed"), Column("priority").desc, Column("createdAt").desc)
                    .fetchAll(db)
            }
        }
    }

    func allOpenTodos() throws -> [Todo] {
        try db.dbQueue.read { db in
            try Todo.filter(Column("completed") == false)
                .order(Column("priority").desc, Column("dueDate"), Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func todo(id: Int64) throws -> Todo? {
        try db.dbQueue.read { db in
            try Todo.fetchOne(db, key: id)
        }
    }

    @discardableResult
    func createTodo(
        title: String,
        priority: Int = 0,
        dueDate: Date? = nil,
        projectId: Int64? = nil
    ) throws -> Todo {
        let now = Date()
        let todo = Todo(
            title: title, priority: priority, dueDate: dueDate,
            completed: false, completedAt: nil, projectId: projectId,
            createdAt: now, updatedAt: now
        )
        return try db.dbQueue.write { db in
            try todo.inserted(db)
        }
    }

    func updateTodo(_ todo: Todo) throws {
        var updated = todo
        updated.updatedAt = Date()
        try db.dbQueue.write { db in
            try updated.update(db)
        }
    }

    func completeTodo(id: Int64) throws {
        let now = Date()
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE todos SET completed = 1, completedAt = ?, updatedAt = ? WHERE id = ?",
                arguments: [now, now, id]
            )
        }
    }

    func deleteTodo(id: Int64) throws {
        try db.dbQueue.write { db in
            _ = try Todo.deleteOne(db, key: id)
        }
    }

    func openTodoCount(projectId: Int64) throws -> Int {
        try db.dbQueue.read { db in
            try Todo.filter(Column("projectId") == projectId && Column("completed") == false).fetchCount(db)
        }
    }

    // MARK: - Deliverables

    func deliverablesForTodo(_ todoId: Int64) throws -> [Deliverable] {
        try db.dbQueue.read { db in
            try Deliverable.filter(Column("todoId") == todoId).fetchAll(db)
        }
    }

    func deliverablesForProject(_ projectId: Int64) throws -> [Deliverable] {
        try db.dbQueue.read { db in
            try Deliverable.filter(Column("projectId") == projectId).fetchAll(db)
        }
    }

    @discardableResult
    func createDeliverable(
        kind: DeliverableKind,
        filePath: String? = nil,
        url: String? = nil,
        projectId: Int64? = nil,
        todoId: Int64? = nil
    ) throws -> Deliverable {
        let deliverable = Deliverable(
            kind: kind, filePath: filePath, url: url,
            verified: false, verifiedAt: nil,
            projectId: projectId, todoId: todoId,
            createdAt: Date()
        )
        return try db.dbQueue.write { db in
            try deliverable.inserted(db)
        }
    }

    func verifyDeliverable(id: Int64, verified: Bool) throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE deliverables SET verified = ?, verifiedAt = ? WHERE id = ?",
                arguments: [verified, verified ? Date() : nil, id]
            )
        }
    }

    // MARK: - Summary

    struct ProjectSummary {
        let project: Project
        let openTodoCount: Int
        let totalDeliverables: Int
    }

    func projectSummaries() throws -> [ProjectSummary] {
        try db.dbQueue.read { db in
            let projects = try Project.filter(Column("archived") == false)
                .order(Column("name"))
                .fetchAll(db)

            return try projects.map { project in
                let openTodos = try Todo.filter(
                    Column("projectId") == project.id && Column("completed") == false
                ).fetchCount(db)

                let deliverables = try Deliverable.filter(
                    Column("projectId") == project.id
                ).fetchCount(db)

                return ProjectSummary(
                    project: project,
                    openTodoCount: openTodos,
                    totalDeliverables: deliverables
                )
            }
        }
    }
}
