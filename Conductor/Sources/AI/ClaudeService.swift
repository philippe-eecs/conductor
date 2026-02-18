import Foundation

/// Service that interfaces with the Claude CLI as a subprocess.
/// Simplified for v2: no command validation, no blocklists.
actor ClaudeService {
    static let shared = ClaudeService()

    private var currentSessionId: String?
    private var model: String = "sonnet"

    private let subprocessRunner: any SubprocessRunning
    private let now: @Sendable () -> Date
    private let claudeExecutableURLProvider: @Sendable () throws -> URL
    private let mcpConfigPathProvider: @Sendable () -> String?

    init(
        subprocessRunner: any SubprocessRunning = SystemSubprocessRunner(),
        now: @escaping @Sendable () -> Date = { Date() },
        claudeExecutableURLProvider: @escaping @Sendable () throws -> URL = {
            if let url = ExecutableResolver.resolve(name: "claude") {
                return url
            }
            throw ClaudeError.cliNotFound
        },
        mcpConfigPathProvider: @escaping @Sendable () -> String? = {
            let path = MCPServer.configFilePath
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    ) {
        self.subprocessRunner = subprocessRunner
        self.now = now
        self.claudeExecutableURLProvider = claudeExecutableURLProvider
        self.mcpConfigPathProvider = mcpConfigPathProvider
    }

    // MARK: - Response Types

    struct ClaudeResponse: Codable {
        let result: String
        let totalCostUsd: Double?
        let sessionId: String?
        let duration_ms: Int?
        let num_turns: Int?
        let is_error: Bool?
        let model: String?

        enum CodingKeys: String, CodingKey {
            case result
            case totalCostUsd = "total_cost_usd"
            case sessionId = "session_id"
            case duration_ms
            case num_turns
            case is_error
            case model
        }
    }

    struct StreamEvent: Codable {
        let type: String?
        let subtype: String?
        let model: String?
        let message: StreamMessageContent?
        let content_block: StreamContentBlock?
        let result: String?
        let session_id: String?
        let total_cost_usd: Double?
        let is_error: Bool?
        let duration_ms: Int?
        let num_turns: Int?
    }

    struct StreamMessageContent: Codable {
        let role: String?
        let content: StreamContentValue?
    }

    enum StreamContentValue: Codable {
        case text(String)
        case blocks([StreamContentBlock])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else if let blocks = try? container.decode([StreamContentBlock].self) {
                self = .blocks(blocks)
            } else {
                self = .text("")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(text)
            case .blocks(let blocks):
                try container.encode(blocks)
            }
        }
    }

    struct StreamContentBlock: Codable {
        let type: String?
        let text: String?
        let id: String?
        let name: String?
    }

    // MARK: - Public API

    func sendMessage(
        _ userMessage: String,
        history: [Message],
        toolsEnabled: Bool = false,
        modelOverride: String? = nil
    ) async throws -> ClaudeResponse {
        let trimmedOverride = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenModel = (trimmedOverride?.isEmpty == false) ? trimmedOverride! : model

        var args = ["--print", "--verbose", "--input-format", "text", "--output-format", "stream-json", "--model", chosenModel]

        // Always enable MCP tools
        args += ["--tools", "default"]
        args += ["--permission-mode", "plan"]

        // Block all built-in execution tools — only MCP tools remain usable
        args += ["--disallowed-tools", Self.allBuiltinToolsArgument]

        if let mcpConfigPath = mcpConfigPathProvider() {
            args += ["--mcp-config", mcpConfigPath]
            args += ["--allowedTools", Self.allowedMCPToolsArgument]
        }

        if let sessionId = currentSessionId {
            args += ["--resume", sessionId]
        } else {
            args += ["--append-system-prompt", buildSystemPrompt()]
        }

        let result = try await runClaudeCLI(args, stdin: (userMessage + "\n").data(using: .utf8))

        guard result.exitCode == 0 else {
            let message = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Unknown error"
            throw ClaudeError.cliError("Claude CLI exited with code \(result.exitCode): \(message)")
        }

        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        let response = try OutputParser.parse(output)

        if response.is_error == true {
            throw ClaudeError.cliError(response.result)
        }

        if let sessionId = response.sessionId {
            currentSessionId = sessionId
        }

        return response
    }

    /// Execute a blink prompt (cheap, no tools, JSON response)
    func executeBlinkPrompt(_ prompt: String) async throws -> ClaudeResponse {
        var args = ["--print", "--verbose", "--input-format", "text", "--output-format", "stream-json", "--model", "sonnet"]
        args += ["--max-turns", "1"]

        // Blink doesn't need tools — just context analysis
        if let mcpConfigPath = mcpConfigPathProvider() {
            args += ["--mcp-config", mcpConfigPath]
            args += ["--tools", "default"]
            args += ["--permission-mode", "plan"]
            args += ["--disallowed-tools", Self.allBuiltinToolsArgument]
            args += ["--allowedTools", Self.allowedMCPToolsArgument]
        }

        args += ["--append-system-prompt", "You are the Blink Engine. Respond ONLY with valid JSON. No markdown, no explanation."]

        let result = try await runClaudeCLI(args, stdin: (prompt + "\n").data(using: .utf8))

        guard result.exitCode == 0 else {
            let message = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Unknown error"
            throw ClaudeError.cliError("Blink CLI error: \(message)")
        }

        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        return try OutputParser.parse(output)
    }

    /// Execute an agent prompt (fresh session, no --resume)
    func executeAgentPrompt(_ prompt: String, modelOverride: String? = "sonnet") async throws -> ClaudeResponse {
        let chosenModel = modelOverride ?? "sonnet"

        var args = ["--print", "--verbose", "--input-format", "text", "--output-format", "stream-json", "--model", chosenModel]
        args += ["--tools", "default"]
        args += ["--permission-mode", "plan"]
        args += ["--disallowed-tools", Self.allBuiltinToolsArgument]

        if let mcpConfigPath = mcpConfigPathProvider() {
            args += ["--mcp-config", mcpConfigPath]
            args += ["--allowedTools", Self.allowedMCPToolsArgument]
        }

        args += ["--append-system-prompt", "You are Conductor Agent, executing a background task autonomously. Be concise and actionable."]

        let result = try await runClaudeCLI(args, stdin: (prompt + "\n").data(using: .utf8))

        guard result.exitCode == 0 else {
            let message = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Unknown error"
            throw ClaudeError.cliError("Agent CLI error: \(message)")
        }

        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        let response = try OutputParser.parse(output)

        if response.is_error == true {
            throw ClaudeError.cliError(response.result)
        }

        return response
    }

    func startNewConversation() {
        currentSessionId = nil
    }

    func resumeSession(_ sessionId: String) {
        currentSessionId = sessionId
    }

    var sessionId: String? {
        currentSessionId
    }

    func checkCLIAvailable() async -> Bool {
        ExecutableResolver.resolve(name: "claude") != nil
    }

    func getCLIVersion() async -> String? {
        do {
            let claudeURL = try claudeExecutableURLProvider()
            let result = try await subprocessRunner.run(
                executableURL: claudeURL,
                arguments: ["--version"],
                environment: subprocessEnvironment(),
                currentDirectoryURL: workingDirectoryURL(),
                stdin: nil
            )
            guard result.exitCode == 0 else { return nil }
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private func workingDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let conductorDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)
        try? FileManager.default.createDirectory(at: conductorDir, withIntermediateDirectories: true)
        return conductorDir
    }

    private func subprocessEnvironment() -> [String: String] {
        let env = ProcessInfo.processInfo.environment

        var sanitized: [String: String] = [:]
        let allowList: Set<String> = [
            "PATH", "HOME", "USER", "LOGNAME", "SHELL",
            "LANG", "LC_ALL", "LC_CTYPE",
            "TMPDIR", "TMP", "TEMP",
            "XDG_CONFIG_HOME", "XDG_DATA_HOME"
        ]

        for (key, value) in env {
            if allowList.contains(key) || key.hasPrefix("CLAUDE_") || key.hasPrefix("ANTHROPIC_") {
                sanitized[key] = value
            }
        }

        let defaultPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/bin"
        ]
        let existing = sanitized["PATH"] ?? env["PATH"] ?? ""
        sanitized["PATH"] = (defaultPaths + [existing])
            .filter { !$0.isEmpty }
            .joined(separator: ":")

        return sanitized
    }

    private func runClaudeCLI(_ arguments: [String], stdin: Data?) async throws -> SubprocessResult {
        do {
            let claudeURL = try claudeExecutableURLProvider()
            return try await subprocessRunner.run(
                executableURL: claudeURL,
                arguments: arguments,
                environment: subprocessEnvironment(),
                currentDirectoryURL: workingDirectoryURL(),
                stdin: stdin
            )
        } catch let error as ClaudeError {
            throw error
        } catch {
            throw ClaudeError.processError(error.localizedDescription)
        }
    }

    private func buildSystemPrompt() -> String {
        """
        You are Conductor, a personal AI assistant running as a macOS menubar app.
        You help users manage their day, projects, and tasks.

        Current date and time: \(SharedDateFormatters.fullDateTime.string(from: now()))

        ## Your MCP Tools
        You have MCP tools provided by the "conductor-context" server:
        - conductor_get_calendar: Fetch calendar events for any date range
        - conductor_get_reminders: Fetch reminders/tasks
        - conductor_get_projects: List all projects with their TODOs
        - conductor_get_todos: Get TODOs, optionally filtered by project
        - conductor_create_project: Create a new project
        - conductor_create_todo: Create a new TODO
        - conductor_update_todo: Update or complete a TODO
        - conductor_create_calendar_block: Create a calendar event for time blocking
        - conductor_dispatch_agent: Dispatch an AI agent to work on a TODO

        IMPORTANT: When the user asks about their schedule, projects, tasks, or calendar —
        call the appropriate MCP tools. Do NOT guess or say you can't access their data.

        Be concise and actionable. Use bullet points and clear formatting.
        """
    }

    private static let allowedMCPToolsArgument = [
        "mcp__conductor-context__conductor_get_calendar",
        "mcp__conductor-context__conductor_get_reminders",
        "mcp__conductor-context__conductor_get_projects",
        "mcp__conductor-context__conductor_get_todos",
        "mcp__conductor-context__conductor_create_todo",
        "mcp__conductor-context__conductor_update_todo",
        "mcp__conductor-context__conductor_create_project",
        "mcp__conductor-context__conductor_create_calendar_block",
        "mcp__conductor-context__conductor_dispatch_agent"
    ].joined(separator: ",")

    private static let allBuiltinToolsArgument = [
        "Bash", "Read", "Write", "Edit", "Glob", "Grep",
        "WebFetch", "WebSearch", "NotebookEdit"
    ].joined(separator: ",")
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case cliNotFound
    case cliError(String)
    case processError(String)
    case invalidResponse
    case sessionError(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Claude CLI not found. Please install Claude Code first."
        case .cliError(let message):
            return "Claude CLI error: \(message)"
        case .processError(let message):
            return "Process error: \(message)"
        case .invalidResponse:
            return "Invalid response from Claude CLI."
        case .sessionError(let message):
            return "Session error: \(message)"
        }
    }
}

// MARK: - Output Parsing

extension ClaudeService {
    enum OutputParser {
        static func parse(_ output: String) throws -> ClaudeResponse {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ClaudeError.invalidResponse
            }
            return try parseStreamResponse(trimmed)
        }

        private static func parseStreamResponse(_ output: String) throws -> ClaudeResponse {
            let lines = output
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var resultText = ""
            var sessionId: String?
            var totalCost: Double?
            var isError: Bool?
            var durationMs: Int?
            var numTurns: Int?
            var model: String?

            let decoder = JSONDecoder()

            for line in lines {
                guard let data = line.data(using: .utf8) else { continue }
                guard let event = try? decoder.decode(StreamEvent.self, from: data) else { continue }

                switch event.type {
                case "system":
                    if let m = event.model { model = m }

                case "assistant":
                    if let content = event.message?.content {
                        switch content {
                        case .text(let text):
                            resultText += text
                        case .blocks(let blocks):
                            for block in blocks {
                                if block.type == "text", let text = block.text {
                                    resultText += text
                                }
                            }
                        }
                    }

                case "result":
                    if let r = event.result { resultText = r }
                    if let sid = event.session_id { sessionId = sid }
                    if let cost = event.total_cost_usd { totalCost = cost }
                    if let err = event.is_error { isError = err }
                    if let d = event.duration_ms { durationMs = d }
                    if let n = event.num_turns { numTurns = n }

                default:
                    if let content = event.message?.content {
                        if case .text(let text) = content {
                            resultText += text
                        }
                    }
                    if let sid = event.session_id { sessionId = sid }
                    if let cost = event.total_cost_usd { totalCost = cost }
                    if let err = event.is_error { isError = err }
                }
            }

            if resultText.isEmpty {
                resultText = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return ClaudeResponse(
                result: resultText,
                totalCostUsd: totalCost,
                sessionId: sessionId,
                duration_ms: durationMs,
                num_turns: numTurns,
                is_error: isError,
                model: model
            )
        }
    }
}
