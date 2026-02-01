import XCTest
@testable import Conductor

final class ClaudeServiceTests: XCTestCase {
    actor StubSubprocessRunner: SubprocessRunning {
        struct Invocation: Sendable {
            let executableURL: URL
            let arguments: [String]
            let environment: [String: String]
            let currentDirectoryURL: URL?
            let stdin: Data?
        }

        private(set) var invocations: [Invocation] = []
        var nextResult: SubprocessResult

        init(nextResult: SubprocessResult) {
            self.nextResult = nextResult
        }

        func run(
            executableURL: URL,
            arguments: [String],
            environment: [String: String],
            currentDirectoryURL: URL?,
            stdin: Data?
        ) async throws -> SubprocessResult {
            invocations.append(Invocation(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                currentDirectoryURL: currentDirectoryURL,
                stdin: stdin
            ))
            return nextResult
        }
    }

    func test_sendMessage_usesStdinAndResumesSession() async throws {
        let json = #"{"result":"OK","total_cost_usd":0.12,"session_id":"sess_1","is_error":false}"#
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let service = ClaudeService(subprocessRunner: runner, now: { fixedNow })

        let response1 = try await service.sendMessage("Hello", context: nil, history: [])
        XCTAssertEqual(response1.result, "OK")
        XCTAssertEqual(response1.sessionId, "sess_1")

        // Second call should include --resume sess_1 and must not include prompt text in argv.
        _ = try await service.sendMessage("Second", context: nil, history: [])

        let invocations = await runner.invocations
        XCTAssertEqual(invocations.count, 2)

        XCTAssertFalse(invocations[0].arguments.contains("--system-prompt"))
        XCTAssertFalse(invocations[1].arguments.contains("--system-prompt"))

        XCTAssertTrue(invocations[0].arguments.contains("--print"))
        XCTAssertTrue(invocations[0].arguments.contains("--tools"))
        XCTAssertTrue(invocations[1].arguments.contains("--resume"))
        XCTAssertTrue(invocations[1].arguments.contains("sess_1"))

        let stdin1 = String(data: invocations[0].stdin ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(stdin1.contains("Hello"))

        let stdin2 = String(data: invocations[1].stdin ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(stdin2.contains("Second"))
        XCTAssertFalse(invocations[1].arguments.contains("Second"))
    }

    func test_outputParser_parsesStreamJson() throws {
        let stream = """
        {"type":"message","message":{"role":"assistant","content":"Hello "},"session_id":"s1"}
        {"type":"message","message":{"role":"assistant","content":"world"}}
        {"type":"result","result":"Hello world","total_cost_usd":0.2,"session_id":"s1","is_error":false}
        """

        let parsed = try ClaudeService.OutputParser.parse(stream)
        XCTAssertEqual(parsed.result, "Hello world")
        XCTAssertEqual(parsed.sessionId, "s1")
        XCTAssertEqual(parsed.totalCostUsd ?? 0, 0.2, accuracy: 0.000001)
        XCTAssertEqual(parsed.is_error, false)
    }
}
