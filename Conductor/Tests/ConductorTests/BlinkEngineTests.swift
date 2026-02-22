import XCTest
@testable import Conductor

final class BlinkEngineTests: XCTestCase {
    var db: AppDatabase!
    var blinkRepo: BlinkRepository!

    override func setUp() async throws {
        db = try AppDatabase()
        blinkRepo = BlinkRepository(db: db)
    }

    func testBlinkLogPersistence() throws {
        let log = BlinkLog(
            decision: .silent,
            contextSummary: "All clear",
            notificationTitle: nil,
            notificationBody: nil,
            agentTodoId: nil,
            agentPrompt: nil,
            costUsd: 0.001,
            createdAt: Date()
        )
        let saved = try blinkRepo.logBlink(log)
        XCTAssertNotNil(saved.id)
        XCTAssertEqual(saved.decision, .silent)
    }

    func testRecentBlinksOrdering() throws {
        for i in 0..<5 {
            let log = BlinkLog(
                decision: i % 2 == 0 ? .silent : .notify,
                contextSummary: "Blink \(i)",
                notificationTitle: i % 2 == 1 ? "Alert \(i)" : nil,
                notificationBody: i % 2 == 1 ? "Body \(i)" : nil,
                agentTodoId: nil,
                agentPrompt: nil,
                costUsd: nil,
                createdAt: Date().addingTimeInterval(Double(i) * 60)
            )
            _ = try blinkRepo.logBlink(log)
        }

        let recent = try blinkRepo.recentBlinks(limit: 3)
        XCTAssertEqual(recent.count, 3)
        // Most recent first
        XCTAssertTrue(recent[0].createdAt >= recent[1].createdAt)
    }

    func testAgentRunLifecycle() throws {
        let projectRepo = ProjectRepository(db: db)
        let todo = try projectRepo.createTodo(title: "Agent test")

        let run = try blinkRepo.createAgentRun(todoId: todo.id, prompt: "Do the thing")
        XCTAssertEqual(run.status, .running)

        try blinkRepo.completeAgentRun(
            id: run.id!,
            output: "Done!",
            costUsd: 0.05,
            status: .completed
        )

        let runs = try blinkRepo.agentRunsForTodo(todo.id!)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].status, .completed)
        XCTAssertEqual(runs[0].output, "Done!")
    }

    func testRunningAgentRuns() throws {
        let run1 = try blinkRepo.createAgentRun(todoId: nil, prompt: "Task 1")
        _ = try blinkRepo.createAgentRun(todoId: nil, prompt: "Task 2")

        let running = try blinkRepo.runningAgentRuns()
        XCTAssertEqual(running.count, 2)

        try blinkRepo.completeAgentRun(id: run1.id!, output: nil, costUsd: nil, status: .completed)

        let stillRunning = try blinkRepo.runningAgentRuns()
        XCTAssertEqual(stillRunning.count, 1)
    }

    func testBlinkPromptBuilder() throws {
        let prompt = BlinkPromptBuilder.build(
            calendarEvents: [],
            openTodos: [],
            runningAgents: [],
            recentBlinks: [],
            unreadEmailCount: 0,
            recentEmails: []
        )
        XCTAssertTrue(prompt.contains("silent"))
        XCTAssertTrue(prompt.contains("notify"))
        XCTAssertTrue(prompt.contains("agent"))
        XCTAssertTrue(prompt.contains("No upcoming events today"))
    }
}
