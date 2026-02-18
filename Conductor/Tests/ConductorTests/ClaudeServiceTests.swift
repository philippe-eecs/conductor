import XCTest
@testable import Conductor

final class ClaudeServiceTests: XCTestCase {

    // MARK: - Output Parser Tests

    func testParseStreamResult() throws {
        let output = """
        {"type":"system","model":"claude-sonnet-4-20250514"}
        {"type":"assistant","message":{"role":"assistant","content":"Hello!"}}
        {"type":"result","result":"Hello!","session_id":"abc123","total_cost_usd":0.001,"is_error":false,"duration_ms":500,"num_turns":1}
        """

        let response = try ClaudeService.OutputParser.parse(output)
        XCTAssertEqual(response.result, "Hello!")
        XCTAssertEqual(response.sessionId, "abc123")
        XCTAssertEqual(response.totalCostUsd, 0.001)
        XCTAssertEqual(response.is_error, false)
        XCTAssertEqual(response.duration_ms, 500)
        XCTAssertEqual(response.num_turns, 1)
    }

    func testParseStreamWithContentBlocks() throws {
        let output = """
        {"type":"system","model":"claude-sonnet-4-20250514"}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Block one"},{"type":"text","text":" and two"}]}}
        {"type":"result","result":"Block one and two","session_id":"def456","total_cost_usd":0.002}
        """

        let response = try ClaudeService.OutputParser.parse(output)
        XCTAssertEqual(response.result, "Block one and two")
        XCTAssertEqual(response.sessionId, "def456")
    }

    func testParseEmptyOutput() {
        XCTAssertThrowsError(try ClaudeService.OutputParser.parse("")) { error in
            XCTAssertTrue(error is ClaudeError)
        }
    }

    func testParseErrorResponse() throws {
        let output = """
        {"type":"result","result":"Something went wrong","is_error":true}
        """

        let response = try ClaudeService.OutputParser.parse(output)
        XCTAssertEqual(response.is_error, true)
        XCTAssertEqual(response.result, "Something went wrong")
    }

    // MARK: - Mock Subprocess Tests

    func testCLINotFound() async {
        let service = ClaudeService(
            claudeExecutableURLProvider: { throw ClaudeError.cliNotFound }
        )

        do {
            _ = try await service.sendMessage("test", history: [])
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is ClaudeError)
        }
    }

    func testSessionManagement() async {
        let service = ClaudeService()

        // Initially no session
        let sessionId = await service.sessionId
        XCTAssertNil(sessionId)

        // Resume session
        await service.resumeSession("test-session")
        let resumed = await service.sessionId
        XCTAssertEqual(resumed, "test-session")

        // Start new conversation clears session
        await service.startNewConversation()
        let cleared = await service.sessionId
        XCTAssertNil(cleared)
    }
}
