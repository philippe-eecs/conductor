import XCTest
@testable import Conductor

final class ProjectRepositoryTests: XCTestCase {
    var db: AppDatabase!
    var repo: ProjectRepository!

    override func setUp() async throws {
        db = try AppDatabase()
        repo = ProjectRepository(db: db)
    }

    func testCreateProject() throws {
        let project = try repo.createProject(name: "Test Project", color: "#FF0000")
        XCTAssertNotNil(project.id)
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.color, "#FF0000")
        XCTAssertFalse(project.archived)
    }

    func testCreateAndListProjects() throws {
        try repo.createProject(name: "Alpha")
        try repo.createProject(name: "Beta")

        let projects = try repo.allProjects()
        XCTAssertEqual(projects.count, 2)
    }

    func testCreateTodo() throws {
        let project = try repo.createProject(name: "Work")
        let todo = try repo.createTodo(title: "Write docs", priority: 2, projectId: project.id)
        XCTAssertNotNil(todo.id)
        XCTAssertEqual(todo.title, "Write docs")
        XCTAssertEqual(todo.priority, 2)
        XCTAssertEqual(todo.projectId, project.id)
        XCTAssertFalse(todo.completed)
    }

    func testCompleteTodo() throws {
        let todo = try repo.createTodo(title: "Do thing")
        try repo.completeTodo(id: todo.id!)

        let fetched = try repo.todo(id: todo.id!)
        XCTAssertNotNil(fetched)
        XCTAssertTrue(fetched!.completed)
        XCTAssertNotNil(fetched!.completedAt)
    }

    func testProjectSummaries() throws {
        let project = try repo.createProject(name: "Summary Test")
        try repo.createTodo(title: "Open", projectId: project.id)
        try repo.createTodo(title: "Also Open", projectId: project.id)

        let completed = try repo.createTodo(title: "Done", projectId: project.id)
        try repo.completeTodo(id: completed.id!)

        let summaries = try repo.projectSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].openTodoCount, 2)
    }

    func testCreateDeliverable() throws {
        let project = try repo.createProject(name: "Ship")
        let todo = try repo.createTodo(title: "Build", projectId: project.id)
        let deliverable = try repo.createDeliverable(
            kind: .code,
            filePath: "/tmp/test.swift",
            projectId: project.id,
            todoId: todo.id
        )

        XCTAssertNotNil(deliverable.id)
        XCTAssertEqual(deliverable.kind, .code)
        XCTAssertFalse(deliverable.verified)

        let fetched = try repo.deliverablesForTodo(todo.id!)
        XCTAssertEqual(fetched.count, 1)
    }

    func testInboxTodos() throws {
        // Todos without a project go to inbox
        try repo.createTodo(title: "Inbox task 1")
        try repo.createTodo(title: "Inbox task 2")

        let inbox = try repo.todosForProject(nil)
        XCTAssertEqual(inbox.count, 2)
    }
}
