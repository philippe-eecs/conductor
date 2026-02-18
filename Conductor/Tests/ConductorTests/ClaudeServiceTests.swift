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

    // Helper to build a valid stream-json result line
    private func resultJSON(result: String = "OK", cost: Double = 0.12, sessionId: String = "sess_1") -> String {
        """
        {"type":"result","result":"\(result)","total_cost_usd":\(cost),"session_id":"\(sessionId)","is_error":false}
        """
    }

    func test_sendMessage_usesStdinAndResumesSession() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") }
        )

        let response1 = try await service.sendMessage("Hello", history: [])
        XCTAssertEqual(response1.result, "OK")
        XCTAssertEqual(response1.sessionId, "sess_1")

        // Second call should include --resume sess_1 and must not include prompt text in argv.
        _ = try await service.sendMessage("Second", history: [])

        let invocations = await runner.invocations
        XCTAssertEqual(invocations.count, 2)

        // First call should have --append-system-prompt (not --system-prompt)
        XCTAssertTrue(invocations[0].arguments.contains("--append-system-prompt"))
        // Second call should NOT have --append-system-prompt (resumed session)
        XCTAssertFalse(invocations[1].arguments.contains("--append-system-prompt"))

        XCTAssertTrue(invocations[0].arguments.contains("--print"))
        XCTAssertTrue(invocations[0].arguments.contains("--tools"))
        XCTAssertTrue(invocations[1].arguments.contains("--resume"))
        XCTAssertTrue(invocations[1].arguments.contains("sess_1"))

        // stdin should contain only the user message, NOT system prompt
        let stdin1 = String(data: invocations[0].stdin ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(stdin1.contains("Hello"))
        // System prompt should NOT be in stdin
        XCTAssertFalse(stdin1.contains("You are Conductor"))

        let stdin2 = String(data: invocations[1].stdin ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(stdin2.contains("Second"))
        XCTAssertFalse(invocations[1].arguments.contains("Second"))
    }

    func test_sendMessage_systemPromptInArgsNotStdin() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") }
        )

        _ = try await service.sendMessage("Test", history: [])

        let invocation = await runner.invocations.first!
        let args = invocation.arguments

        // System prompt should be passed via --append-system-prompt flag
        guard let idx = args.firstIndex(of: "--append-system-prompt"), idx + 1 < args.count else {
            return XCTFail("Expected --append-system-prompt argument")
        }
        let systemPrompt = args[idx + 1]
        XCTAssertTrue(systemPrompt.contains("You are Conductor"))
        XCTAssertTrue(systemPrompt.contains("conductor-context"))
        XCTAssertTrue(systemPrompt.contains("MUST call"))

        // stdin should contain only the user message
        let stdin = String(data: invocation.stdin ?? Data(), encoding: .utf8) ?? ""
        XCTAssertEqual(stdin, "Test\n")
    }

    func test_sendMessage_systemPromptDoesNotHardcodeToolNames() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") }
        )

        _ = try await service.sendMessage("Test", history: [])

        let invocation = await runner.invocations.first!
        let args = invocation.arguments
        guard let idx = args.firstIndex(of: "--append-system-prompt"), idx + 1 < args.count else {
            return XCTFail("Expected --append-system-prompt argument")
        }
        let systemPrompt = args[idx + 1]

        // Should NOT contain hardcoded tool names
        XCTAssertFalse(systemPrompt.contains("conductor_get_calendar"))
        XCTAssertFalse(systemPrompt.contains("conductor_get_reminders"))
        // Should reference the server name instead
        XCTAssertTrue(systemPrompt.contains("conductor-context"))
    }

    func test_outputParser_parsesStreamJsonWithToolUse() throws {
        let stream = """
        {"type":"system","model":"claude-sonnet-4-20250514"}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu_1","name":"mcp__conductor-context__conductor_get_calendar","input":{"startDate":"2025-01-01","endDate":"2025-01-02"}},{"type":"text","text":"Here are your events."}]}}
        {"type":"result","result":"Here are your events.","total_cost_usd":0.05,"session_id":"s1","is_error":false,"duration_ms":1200,"num_turns":2}
        """

        let parsed = try ClaudeService.OutputParser.parse(stream)
        XCTAssertEqual(parsed.result, "Here are your events.")
        XCTAssertEqual(parsed.sessionId, "s1")
        XCTAssertEqual(parsed.totalCostUsd ?? 0, 0.05, accuracy: 0.000001)
        XCTAssertEqual(parsed.is_error, false)
        XCTAssertEqual(parsed.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(parsed.duration_ms, 1200)
        XCTAssertEqual(parsed.num_turns, 2)

        // Tool calls
        XCTAssertNotNil(parsed.toolCalls)
        XCTAssertEqual(parsed.toolCalls?.count, 1)
        XCTAssertEqual(parsed.toolCalls?.first?.toolName, "mcp__conductor-context__conductor_get_calendar")
        XCTAssertEqual(parsed.toolCalls?.first?.displayName, "conductor_get_calendar")
    }

    func test_outputParser_parsesStreamJsonWithoutTools() throws {
        let stream = """
        {"type":"system","model":"claude-opus-4-20250514"}
        {"type":"assistant","message":{"role":"assistant","content":"Hello world"}}
        {"type":"result","result":"Hello world","total_cost_usd":0.2,"session_id":"s1","is_error":false}
        """

        let parsed = try ClaudeService.OutputParser.parse(stream)
        XCTAssertEqual(parsed.result, "Hello world")
        XCTAssertEqual(parsed.sessionId, "s1")
        XCTAssertEqual(parsed.totalCostUsd ?? 0, 0.2, accuracy: 0.000001)
        XCTAssertEqual(parsed.model, "claude-opus-4-20250514")
        XCTAssertNil(parsed.toolCalls)
    }

    func test_outputParser_modelExtraction() throws {
        let stream = """
        {"type":"system","model":"claude-opus-4-20250514"}
        {"type":"result","result":"Done","total_cost_usd":0.01,"session_id":"s2","is_error":false}
        """
        let parsed = try ClaudeService.OutputParser.parse(stream)
        XCTAssertEqual(parsed.model, "claude-opus-4-20250514")
    }

    func test_toolCallInfo_displayNameStripping() {
        let tool1 = ClaudeService.ToolCallInfo(
            toolName: "mcp__conductor-context__conductor_get_calendar",
            input: nil,
            timestamp: Date()
        )
        XCTAssertEqual(tool1.displayName, "conductor_get_calendar")

        let tool2 = ClaudeService.ToolCallInfo(
            toolName: "mcp__some-server__some_tool",
            input: nil,
            timestamp: Date()
        )
        XCTAssertEqual(tool2.displayName, "some_tool")

        let tool3 = ClaudeService.ToolCallInfo(
            toolName: "Bash",
            input: nil,
            timestamp: Date()
        )
        XCTAssertEqual(tool3.displayName, "Bash")
    }

    func test_sendMessage_defaultsToOpusModel() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") }
        )

        _ = try await service.sendMessage("Hello", history: [])
        let invocation = await runner.invocations.first
        let args = invocation?.arguments ?? []

        guard let modelIndex = args.firstIndex(of: "--model"), modelIndex + 1 < args.count else {
            return XCTFail("Expected --model argument")
        }
        XCTAssertEqual(args[modelIndex + 1], "opus")
    }

    func test_sendMessage_canOverrideModelToSonnet() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") }
        )

        _ = try await service.sendMessage("Hello", history: [], toolsEnabled: false, modelOverride: "sonnet")
        let invocation = await runner.invocations.first
        let args = invocation?.arguments ?? []

        guard let modelIndex = args.firstIndex(of: "--model"), modelIndex + 1 < args.count else {
            return XCTFail("Expected --model argument")
        }
        XCTAssertEqual(args[modelIndex + 1], "sonnet")
    }

    func test_sendMessage_usesStreamJsonOutputFormat() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") }
        )

        _ = try await service.sendMessage("Hello", history: [])
        let invocation = await runner.invocations.first
        let args = invocation?.arguments ?? []

        guard let fmtIndex = args.firstIndex(of: "--output-format"), fmtIndex + 1 < args.count else {
            return XCTFail("Expected --output-format argument")
        }
        XCTAssertEqual(args[fmtIndex + 1], "stream-json")
    }

    func test_sendMessage_whenToolsEnabled_addsPermissionModeAndToolGuards() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") }
        )

        _ = try await service.sendMessage(
            "Hello",
            history: [],
            toolsEnabled: true,
            modelOverride: "sonnet",
            permissionModeOverride: "plan"
        )

        let invocation = await runner.invocations.first
        let args = invocation?.arguments ?? []

        guard let toolsIndex = args.firstIndex(of: "--tools"), toolsIndex + 1 < args.count else {
            return XCTFail("Expected --tools argument")
        }
        XCTAssertEqual(args[toolsIndex + 1], "default")

        guard let modeIndex = args.firstIndex(of: "--permission-mode"), modeIndex + 1 < args.count else {
            return XCTFail("Expected --permission-mode argument")
        }
        XCTAssertEqual(args[modeIndex + 1], "plan")

        XCTAssertTrue(args.contains("--disallowed-tools"))
    }

    // MARK: - MCP Integration Tests

    /// Verifies the full MCP argument chain: --mcp-config is present, --append-system-prompt
    /// references "conductor-context", and --tools default enables MCP tool discovery.
    func test_sendMessage_withMCPServer_passesMCPConfigAndSystemPrompt() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

        // Simulate a running MCP server by providing a fake config path
        let fakeMCPConfigPath = "/tmp/test-conductor-mcp.json"
        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") },
            mcpConfigPathProvider: { fakeMCPConfigPath }
        )

        _ = try await service.sendMessage("What's on my calendar?", history: [])

        let invocation = await runner.invocations.first!
        let args = invocation.arguments

        // 1. --mcp-config must be present so Claude discovers the MCP tools
        guard let mcpIdx = args.firstIndex(of: "--mcp-config"), mcpIdx + 1 < args.count else {
            return XCTFail("Expected --mcp-config argument — without it Claude can't discover MCP tools")
        }
        XCTAssertEqual(args[mcpIdx + 1], fakeMCPConfigPath)

        // 2. --append-system-prompt must reference the conductor-context server
        //    so Claude knows which MCP server provides the user's data
        guard let sysIdx = args.firstIndex(of: "--append-system-prompt"), sysIdx + 1 < args.count else {
            return XCTFail("Expected --append-system-prompt — without it Claude won't know to use MCP tools")
        }
        let systemPrompt = args[sysIdx + 1]
        XCTAssertTrue(systemPrompt.contains("conductor-context"),
                       "System prompt must reference 'conductor-context' server so Claude can connect prompt instructions to MCP tools")
        XCTAssertTrue(systemPrompt.contains("MUST call"),
                       "System prompt must strongly instruct Claude to call MCP tools")
        XCTAssertTrue(systemPrompt.contains("Do NOT guess"),
                       "System prompt must tell Claude not to guess/apologize instead of calling tools")

        // 3. --tools default must be present to enable MCP tool usage
        guard let toolsIdx = args.firstIndex(of: "--tools"), toolsIdx + 1 < args.count else {
            return XCTFail("Expected --tools argument — required for MCP tool discovery")
        }
        XCTAssertEqual(args[toolsIdx + 1], "default")

        guard let allowedIdx = args.firstIndex(of: "--allowedTools"), allowedIdx + 1 < args.count else {
            return XCTFail("Expected --allowedTools argument with MCP allowlist")
        }
        let allowed = args[allowedIdx + 1]
        XCTAssertTrue(allowed.contains("conductor_get_day_review"))
        XCTAssertTrue(allowed.contains("conductor_plan_day"))
        XCTAssertTrue(allowed.contains("conductor_plan_week"))
        XCTAssertTrue(allowed.contains("conductor_apply_plan_blocks"))
        XCTAssertTrue(allowed.contains("conductor_publish_plan_blocks"))

        // 4. stdin must contain ONLY the user message (not system prompt)
        let stdin = String(data: invocation.stdin ?? Data(), encoding: .utf8) ?? ""
        XCTAssertEqual(stdin, "What's on my calendar?\n")

        // 5. output format must be stream-json for tool call visibility
        guard let fmtIdx = args.firstIndex(of: "--output-format"), fmtIdx + 1 < args.count else {
            return XCTFail("Expected --output-format argument")
        }
        XCTAssertEqual(args[fmtIdx + 1], "stream-json")
    }

    /// Verifies that --mcp-config is still passed on resumed sessions (MCP config is
    /// per-invocation, unlike the system prompt which persists in the session).
    func test_sendMessage_onResume_stillPassesMCPConfigButNotSystemPrompt() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

        let fakeMCPConfigPath = "/tmp/test-conductor-mcp.json"
        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") },
            mcpConfigPathProvider: { fakeMCPConfigPath }
        )

        // First call establishes session
        _ = try await service.sendMessage("Hello", history: [])
        // Second call resumes
        _ = try await service.sendMessage("Show my calendar", history: [])

        let invocations = await runner.invocations
        let resumeArgs = invocations[1].arguments

        // MCP config must be present on resume (it's per-invocation, not persisted in session)
        XCTAssertTrue(resumeArgs.contains("--mcp-config"),
                       "--mcp-config must be passed on every invocation, including resume")

        // System prompt should NOT be on resume (it's persisted in session)
        XCTAssertFalse(resumeArgs.contains("--append-system-prompt"),
                        "--append-system-prompt should not be sent on resume — it persists in the session")

        // --resume must be present
        XCTAssertTrue(resumeArgs.contains("--resume"))
        XCTAssertTrue(resumeArgs.contains("sess_1"))

        // --tools must still be present
        XCTAssertTrue(resumeArgs.contains("--tools"))
    }

    /// Verifies that when MCP server is NOT running, we don't pass --mcp-config
    /// (graceful degradation — Claude still works, just without MCP tools).
    func test_sendMessage_withoutMCPServer_omitsMCPConfig() async throws {
        let json = resultJSON()
        let runner = StubSubprocessRunner(nextResult: SubprocessResult(exitCode: 0, stdout: json, stderr: ""))
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

        let service = ClaudeService(
            subprocessRunner: runner,
            now: { fixedNow },
            claudeExecutableURLProvider: { URL(fileURLWithPath: "/usr/bin/claude") },
            mcpConfigPathProvider: { nil }  // MCP server not running
        )

        _ = try await service.sendMessage("Hello", history: [])
        let args = await runner.invocations.first!.arguments

        XCTAssertFalse(args.contains("--mcp-config"),
                        "Should not pass --mcp-config when MCP server is not running")
        // System prompt should still be present
        XCTAssertTrue(args.contains("--append-system-prompt"))
    }

    /// End-to-end parser test: simulates a realistic Claude stream-json response
    /// where Claude called an MCP tool, got a result, and produced a final answer.
    func test_outputParser_fullMCPToolCallFlow() throws {
        // Simulates what Claude CLI actually outputs when it calls an MCP tool
        let stream = """
        {"type":"system","model":"claude-opus-4-20250514","tools":["mcp__conductor-context__conductor_get_calendar","mcp__conductor-context__conductor_get_reminders"]}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01","name":"mcp__conductor-context__conductor_get_calendar","input":{"startDate":"2025-01-15","endDate":"2025-01-15"}}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Based on your calendar, here are today's events:\\n\\n- **9:00 AM** Team standup (30 min)\\n- **2:00 PM** Design review (1 hr)"}]}}
        {"type":"result","result":"Based on your calendar, here are today's events:\\n\\n- **9:00 AM** Team standup (30 min)\\n- **2:00 PM** Design review (1 hr)","total_cost_usd":0.08,"session_id":"sess_mcp","is_error":false,"duration_ms":3200,"num_turns":3}
        """

        let parsed = try ClaudeService.OutputParser.parse(stream)

        // Model should be extracted
        XCTAssertEqual(parsed.model, "claude-opus-4-20250514")

        // Tool call should be captured
        XCTAssertNotNil(parsed.toolCalls)
        XCTAssertEqual(parsed.toolCalls?.count, 1)

        let tool = parsed.toolCalls!.first!
        XCTAssertEqual(tool.toolName, "mcp__conductor-context__conductor_get_calendar")
        XCTAssertEqual(tool.displayName, "conductor_get_calendar")
        XCTAssertNotNil(tool.input)
        XCTAssertTrue(tool.input!.contains("2025-01-15"))

        // Final result should be the result event text (not accumulated)
        XCTAssertTrue(parsed.result.contains("Team standup"))
        XCTAssertEqual(parsed.sessionId, "sess_mcp")
        XCTAssertEqual(parsed.totalCostUsd, 0.08)
        XCTAssertEqual(parsed.duration_ms, 3200)
        XCTAssertEqual(parsed.num_turns, 3)
    }
}
