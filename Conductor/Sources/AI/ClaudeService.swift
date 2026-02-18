import Foundation

// MARK: - Command Validation (Shared)

enum CommandValidationResult {
    case allowed(warning: String?)
    case denied(reason: String)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .allowed(let warning):
            return warning ?? "Command allowed"
        case .denied(let reason):
            return reason
        }
    }
}

enum CommandValidator {
    static func validate(
        command: String,
        allowlistEnabled: Bool,
        allowedCommands: Set<String>,
        allowedGitSubcommands: Set<String>,
        blockedCommands: Set<String>
    ) -> CommandValidationResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .denied(reason: "Empty command")
        }

        let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let baseCommand = components.first else {
            return .denied(reason: "Invalid command format")
        }

        let commandName = (baseCommand as NSString).lastPathComponent

        if blockedCommands.contains(commandName) {
            return .denied(reason: "Command '\(commandName)' is blocked for security")
        }

        if containsShellInjection(trimmed) {
            return .denied(reason: "Command contains potentially unsafe patterns")
        }

        guard allowlistEnabled else {
            return .allowed(warning: "Command allowlist disabled - executing unrestricted")
        }

        if allowedCommands.contains(commandName) {
            if commandName == "git" && components.count > 1 {
                let gitSubcommand = components[1]
                if allowedGitSubcommands.contains(gitSubcommand) {
                    return .allowed(warning: nil)
                } else {
                    return .denied(reason: "Git subcommand '\(gitSubcommand)' is not in allowlist")
                }
            }
            return .allowed(warning: nil)
        }

        return .denied(reason: "Command '\(commandName)' is not in allowlist")
    }

    static func containsShellInjection(_ command: String) -> Bool {
        let dangerousPatterns = [
            "$(", "`",           // Command substitution
            "&&", "||", ";",     // Command chaining
            "|",                 // Piping (could be used for exfiltration)
            ">", ">>",           // Output redirection
            "<",                 // Input redirection
            "\\n", "\\r",        // Newline injection
            "${",                // Variable expansion
        ]

        return dangerousPatterns.contains { command.contains($0) }
    }
}

/// Service that interfaces with the Claude CLI (`claude` command) as a subprocess.
/// Uses the user's existing Claude Code Max subscription instead of requiring API keys.
///
/// This is an actor to ensure thread-safe access to session state.
actor ClaudeService {
    static let shared = ClaudeService()

    // MARK: - Command Security

    /// Allowed commands when command allowlist is enabled
    /// These are safe, read-only commands that won't modify the system
    static let allowedCommands: Set<String> = [
        "git", "ls", "cat", "head", "tail", "echo", "pwd", "which", "whoami",
        "date", "cal", "wc", "sort", "uniq", "grep", "find", "tree", "file",
        "diff", "less", "more"
    ]

    /// Allowed git subcommands (read-only operations)
    static let allowedGitSubcommands: Set<String> = [
        "status", "diff", "log", "show", "branch", "remote", "tag",
        "blame", "shortlog", "describe", "rev-parse", "config"
    ]

    /// Blocked commands that should never be executed
    static let blockedCommands: Set<String> = [
        "rm", "rmdir", "mv", "cp", "chmod", "chown", "chgrp",
        "curl", "wget", "ssh", "scp", "rsync", "ftp", "sftp",
        "sudo", "su", "doas", "pkexec",
        "kill", "killall", "pkill",
        "shutdown", "reboot", "halt",
        "mkfs", "fdisk", "dd", "mount", "umount",
        "apt", "apt-get", "brew", "pip", "npm", "yarn", "cargo",
        "systemctl", "service", "launchctl"
    ]

    /// Current session ID for conversation continuity
    private var currentSessionId: String?

    /// Model to use for requests
    private var model: String = "opus"

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
            // Return the config file written eagerly by MCPServer on startup.
            // Only return it if the file exists (server is running).
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

    struct ToolCallInfo: Codable, Equatable {
        let toolName: String
        let input: String?
        let timestamp: Date

        /// Strips MCP prefix for display (e.g. "mcp__conductor-context__conductor_get_calendar" → "conductor_get_calendar")
        var displayName: String {
            if let range = toolName.range(of: "mcp__conductor-context__") {
                return String(toolName[range.upperBound...])
            }
            // Strip any mcp__<server>__ prefix
            if toolName.hasPrefix("mcp__"),
               let lastSep = toolName.range(of: "__", options: .backwards, range: toolName.index(toolName.startIndex, offsetBy: 5)..<toolName.endIndex) {
                return String(toolName[lastSep.upperBound...])
            }
            return toolName
        }
    }

    struct ClaudeResponse: Codable {
        let result: String
        let totalCostUsd: Double?
        let sessionId: String?
        let duration_ms: Int?
        let num_turns: Int?
        let is_error: Bool?
        let model: String?
        let toolCalls: [ToolCallInfo]?

        enum CodingKeys: String, CodingKey {
            case result
            case totalCostUsd = "total_cost_usd"
            case sessionId = "session_id"
            case duration_ms
            case num_turns
            case is_error
            case model
            case toolCalls
        }
    }

    /// Represents a single line in stream-json output
    struct StreamEvent: Codable {
        let type: String?
        let subtype: String?

        // "system" event fields
        let model: String?

        // "assistant" event with message content
        let message: StreamMessageContent?

        // "content_block_start" / "content_block_delta" fields
        let content_block: StreamContentBlock?

        // "result" event fields
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

    /// Content can be a plain string or an array of content blocks
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
        // tool_use fields
        let id: String?
        let name: String?
        let input: AnyCodable?
    }

    /// Type-erased Codable for arbitrary JSON
    struct AnyCodable: Codable, Equatable {
        let value: Any

        init(_ value: Any) { self.value = value }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dict = try? container.decode([String: AnyCodable].self) {
                value = dict.mapValues { $0.value }
            } else if let arr = try? container.decode([AnyCodable].self) {
                value = arr.map { $0.value }
            } else if let str = try? container.decode(String.self) {
                value = str
            } else if let num = try? container.decode(Double.self) {
                value = num
            } else if let bool = try? container.decode(Bool.self) {
                value = bool
            } else {
                value = NSNull()
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let str = value as? String { try container.encode(str) }
            else if let num = value as? Double { try container.encode(num) }
            else if let bool = value as? Bool { try container.encode(bool) }
            else { try container.encodeNil() }
        }

        static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
            String(describing: lhs.value) == String(describing: rhs.value)
        }

        var jsonString: String? {
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    // MARK: - Public API

    /// Sends a message to Claude via the CLI subprocess
    /// - Parameters:
    ///   - userMessage: The user's message
    ///   - history: Previous chat messages (used for building context, not sent directly)
    ///   - toolsEnabled: When true, Claude can use tools (with user approval). Default: false (safe mode)
    ///   - modelOverride: Optional model name passed to the Claude CLI via `--model` (e.g. "sonnet", "opus").
    ///   - permissionModeOverride: Optional Claude Code permission mode (e.g. "plan", "default").
    /// - Returns: The assistant's response
    func sendMessage(
        _ userMessage: String,
        history: [ChatMessage],
        toolsEnabled: Bool = false,
        modelOverride: String? = nil,
        permissionModeOverride: String? = nil,
        runtimePreamble: String? = nil
    ) async throws -> ClaudeResponse {
        // Build arguments for the claude CLI.
        // - Use --print for non-interactive mode.
        // - Pass only the user message via stdin to avoid leaking content via argv.
        let trimmedOverride = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenModel = (trimmedOverride?.isEmpty == false) ? trimmedOverride! : model

        var args = ["--print", "--verbose", "--input-format", "text", "--output-format", "stream-json", "--model", chosenModel]

        // Always enable tools so MCP context tools work.
        // When tool execution is disabled, block dangerous built-in tools via --disallowed-tools.
        args += ["--tools", "default"]

        if toolsEnabled {
            let mode = sanitizePermissionMode(permissionModeOverride) ?? "plan"
            args += ["--permission-mode", mode]

            // Block obviously dangerous tool patterns until we have a dedicated approval UI.
            args += ["--disallowed-tools", Self.disallowedToolsArgument]
        } else {
            // Lock down to plan mode and block all execution tools — only MCP tools remain usable.
            args += ["--permission-mode", "plan"]
            args += ["--disallowed-tools", Self.allBuiltinToolsArgument]
        }

        // Add MCP config so Claude can call Conductor context tools.
        // Pre-approve our MCP tools so they work regardless of permission mode.
        if let mcpConfigPath = mcpConfigPathProvider() {
            args += ["--mcp-config", mcpConfigPath]
            args += ["--allowedTools", Self.allowedMCPToolsArgument]
        }

        // On first call, inject system instructions via --append-system-prompt.
        // On resumed sessions, Claude Code persists the system prompt so we skip it.
        if let sessionId = currentSessionId {
            args += ["--resume", sessionId]
        } else {
            args += ["--append-system-prompt", buildSystemPrompt()]
        }

        let trimmedPreamble = runtimePreamble?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdinMessage: String
        if let trimmedPreamble, !trimmedPreamble.isEmpty {
            stdinMessage = "\(trimmedPreamble)\n\nUser request:\n\(userMessage)\n"
        } else {
            stdinMessage = userMessage + "\n"
        }

        let result = try await runClaudeCLI(args, stdin: stdinMessage.data(using: .utf8))

        guard result.exitCode == 0 else {
            let message = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Unknown error"
            throw ClaudeError.cliError("Claude CLI exited with code \(result.exitCode): \(message)")
        }

        // Parse the stream-json response
        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        let response = try OutputParser.parse(output)

        // Check for error response
        if response.is_error == true {
            throw ClaudeError.cliError(response.result)
        }

        // Save session for continuity
        if let sessionId = response.sessionId {
            currentSessionId = sessionId
        }

        return response
    }

    /// Starts a new conversation (clears current session)
    func startNewConversation() {
        currentSessionId = nil
    }

    /// Resumes a specific session
    func resumeSession(_ sessionId: String) {
        currentSessionId = sessionId
    }

    /// Gets the current session ID
    var sessionId: String? {
        currentSessionId
    }

    /// Executes a prompt for an agent task (fresh session, no --resume, agent system prompt).
    /// Uses a separate call path from chat to avoid mutating session state.
    func executeAgentPrompt(
        _ prompt: String,
        modelOverride: String? = "opus"
    ) async throws -> ClaudeResponse {
        let chosenModel = modelOverride ?? "opus"

        var args = ["--print", "--verbose", "--input-format", "text", "--output-format", "stream-json", "--model", chosenModel]
        args += ["--tools", "default"]
        args += ["--permission-mode", "plan"]
        args += ["--disallowed-tools", Self.allBuiltinToolsArgument]

        // Add MCP config for context tools
        if let mcpConfigPath = mcpConfigPathProvider() {
            args += ["--mcp-config", mcpConfigPath]
            args += ["--allowedTools", Self.allowedMCPToolsArgument]
        }

        // Always use agent system prompt, never --resume
        args += ["--append-system-prompt", buildAgentSystemPrompt()]

        let result = try await runClaudeCLI(args, stdin: (prompt + "\n").data(using: .utf8))

        guard result.exitCode == 0 else {
            let message = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Unknown error"
            throw ClaudeError.cliError("Agent CLI exited with code \(result.exitCode): \(message)")
        }

        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        let response = try OutputParser.parse(output)

        if response.is_error == true {
            throw ClaudeError.cliError(response.result)
        }

        return response
    }

    private func buildAgentSystemPrompt() -> String {
        """
        You are Conductor Agent, executing a background task autonomously.
        \(sharedPromptSections())
        Be concise and actionable. Focus on completing your assigned task.
        """
    }

    /// Checks if the Claude CLI is available
    func checkCLIAvailable() async -> Bool {
        ExecutableResolver.resolve(name: "claude") != nil
    }

    /// Gets Claude CLI version
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
            // CLI not available
        }
        return nil
    }

    // MARK: - Command Security Validation

    /// Validates if a command is allowed based on security settings
    /// - Parameters:
    ///   - command: The command string to validate
    ///   - allowlistEnabled: Whether the command allowlist is enabled
    /// - Returns: A CommandValidationResult indicating if the command is allowed
    func validateCommand(_ command: String, allowlistEnabled: Bool) -> CommandValidationResult {
        CommandValidator.validate(
            command: command,
            allowlistEnabled: allowlistEnabled,
            allowedCommands: Self.allowedCommands,
            allowedGitSubcommands: Self.allowedGitSubcommands,
            blockedCommands: Self.blockedCommands
        )
    }

    // MARK: - Private Methods

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
        You help users manage their day, tasks, and projects.

        Key behaviors:
        - Be concise and actionable
        - Use bullet points and clear formatting
        - Proactively suggest relevant actions

        \(sharedPromptSections())

        ## Scheduling
        You can create time blocks in two ways:
        1. Direct: Use conductor_create_theme_block to create a single block with a specific theme, start, and end time. Set publish=true to also add it to the calendar.
        2. Bulk: Use conductor_plan_day to generate suggestions, then conductor_apply_plan_blocks (with publish=true) to apply and publish in one step.

        Always describe proposed blocks to the user before creating them. Wait for confirmation unless the user has clearly asked you to schedule something specific.

        If a tool returns an error saying a feature is disabled, tell the user they can enable it in Conductor Settings.
        """
    }

    private func sharedPromptSections() -> String {
        """
        Current date and time: \(formattedDateTime(now()))

        ## Your MCP Tools
        You have MCP tools provided by the "conductor-context" server that let you access the user's:
        - Calendar events (any date range)
        - Reminders and tasks
        - Daily goals and completion status
        - Notes
        - Emails

        IMPORTANT: When the user asks about their schedule, calendar, events, meetings, tasks, reminders, goals, plans, notes, or emails — you MUST call the appropriate MCP tools to fetch real data. Do NOT guess, apologize, or say you cannot access their data. Your MCP tools from the conductor-context server are exactly how you access it.

        ## Proposing Actions
        If you want to create tasks, calendar events, reminders, or other actions, output them as:
        <conductor_actions>
        [{"id": "unique-id", "type": "createTodoTask", "title": "Description", "requiresUserApproval": true, "payload": {"title": "Task name"}}]
        </conductor_actions>

        Available action types: createTodoTask, updateTodoTask, deleteTodoTask, createCalendarEvent, createReminder, createGoal, completeGoal, sendEmail
        """
    }

    /// Writes a temporary MCP config file for the current invocation.
    /// Returns the file path, or nil if the MCP server is not running.
    /// This is a static helper so it can be used as the default mcpConfigPathProvider.
    static func writeMCPConfigFile() -> String? {
        guard let url = MCPServer.shared.endpointURL else { return nil }

        let config: [String: Any] = [
            "mcpServers": [
                "conductor-context": [
                    "type": "http",
                    "url": url,
                    "headers": ["Authorization": MCPAuthPolicy.shared.authorizationHeaderValue()]
                ]
            ]
        ]

        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("conductor-mcp.json").path

        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            Log.mcp.info("Wrote config to \(configPath, privacy: .public)")
            return configPath
        } catch {
            Log.mcp.error("Failed to write config: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func formattedDateTime(_ date: Date) -> String {
        SharedDateFormatters.fullDateTime.string(from: date)
    }

    /// Pre-approved MCP tools from the conductor-context server.
    /// Uses wildcard to match the full prefixed name (mcp__conductor-context__conductor_*).
    private static let allowedMCPToolsArgument = [
        "mcp__conductor-context__conductor_get_calendar",
        "mcp__conductor-context__conductor_get_reminders",
        "mcp__conductor-context__conductor_get_goals",
        "mcp__conductor-context__conductor_get_notes",
        "mcp__conductor-context__conductor_get_emails",
        "mcp__conductor-context__conductor_create_todo_task",
        "mcp__conductor-context__conductor_create_agent_task",
        "mcp__conductor-context__conductor_list_agent_tasks",
        "mcp__conductor-context__conductor_cancel_agent_task",
        "mcp__conductor-context__conductor_get_themes",
        "mcp__conductor-context__conductor_create_theme",
        "mcp__conductor-context__conductor_delete_theme",
        "mcp__conductor-context__conductor_get_day_review",
        "mcp__conductor-context__conductor_get_operation_events",
        "mcp__conductor-context__conductor_assign_task_theme",
        "mcp__conductor-context__conductor_plan_day",
        "mcp__conductor-context__conductor_plan_week",
        "mcp__conductor-context__conductor_apply_plan_blocks",
        "mcp__conductor-context__conductor_publish_plan_blocks",
        "mcp__conductor-context__conductor_create_theme_block"
    ].joined(separator: ",")

    private static let disallowedToolsArgument = [
        "Bash(rm:*)",
        "Bash(rmdir:*)",
        "Bash(mv:*)",
        "Bash(cp:*)",
        "Bash(chmod:*)",
        "Bash(chown:*)",
        "Bash(sudo:*)",
        "Bash(ssh:*)",
        "Bash(scp:*)",
        "Bash(rsync:*)",
        "Bash(curl:*)",
        "Bash(wget:*)"
    ].joined(separator: ",")

    /// Blocks all built-in execution tools when tool mode is off.
    /// MCP tools (conductor_*) are NOT in this list and remain callable.
    private static let allBuiltinToolsArgument = [
        "Bash", "Read", "Write", "Edit", "Glob", "Grep",
        "WebFetch", "WebSearch", "NotebookEdit"
    ].joined(separator: ",")

    private func sanitizePermissionMode(_ override: String?) -> String? {
        let trimmed = override?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        switch trimmed {
        case "acceptEdits", "bypassPermissions", "default", "delegate", "dontAsk", "plan":
            return trimmed
        default:
            return nil
        }
    }
}

// MARK: - Command Security

/// Validates a command and returns whether it should be allowed
/// This is a standalone function for use outside the ClaudeService actor
func validateCommandSecurity(_ command: String) -> (allowed: Bool, reason: String) {
    let allowlistEnabled = (try? Database.shared.getPreference(key: "command_allowlist_enabled")) != "false"

    let result = CommandValidator.validate(
        command: command,
        allowlistEnabled: allowlistEnabled,
        allowedCommands: ClaudeService.allowedCommands,
        allowedGitSubcommands: ClaudeService.allowedGitSubcommands,
        blockedCommands: ClaudeService.blockedCommands
    )

    switch result {
    case .allowed(let warning):
        return (true, warning ?? "Allowed")
    case .denied(let reason):
        return (false, reason)
    }
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

            // Always parse as stream-json (newline-delimited JSON events)
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
            var toolCalls: [ToolCallInfo] = []

            let decoder = JSONDecoder()

            for line in lines {
                guard let data = line.data(using: .utf8) else { continue }
                guard let event = try? decoder.decode(StreamEvent.self, from: data) else { continue }

                switch event.type {
                case "system":
                    // Extract model from system event
                    if let m = event.model {
                        model = m
                    }

                case "assistant":
                    // Extract text and tool_use blocks from assistant message content
                    if let content = event.message?.content {
                        switch content {
                        case .text(let text):
                            resultText += text
                        case .blocks(let blocks):
                            for block in blocks {
                                if block.type == "text", let text = block.text {
                                    resultText += text
                                } else if block.type == "tool_use", let name = block.name {
                                    let inputStr = block.input?.jsonString
                                    toolCalls.append(ToolCallInfo(
                                        toolName: name,
                                        input: inputStr,
                                        timestamp: Date()
                                    ))
                                }
                            }
                        }
                    }

                case "content_block_start", "content_block_delta":
                    // Handle streaming content blocks (tool_use)
                    if let block = event.content_block, block.type == "tool_use", let name = block.name {
                        let inputStr = block.input?.jsonString
                        toolCalls.append(ToolCallInfo(
                            toolName: name,
                            input: inputStr,
                            timestamp: Date()
                        ))
                    }

                case "result":
                    // Final result event — overrides accumulated text
                    if let r = event.result {
                        resultText = r
                    }
                    if let sid = event.session_id {
                        sessionId = sid
                    }
                    if let cost = event.total_cost_usd {
                        totalCost = cost
                    }
                    if let err = event.is_error {
                        isError = err
                    }
                    if let d = event.duration_ms {
                        durationMs = d
                    }
                    if let n = event.num_turns {
                        numTurns = n
                    }

                default:
                    // message, tool_result, etc. — extract what we can
                    if let content = event.message?.content {
                        if case .text(let text) = content {
                            resultText += text
                        }
                    }
                    if let sid = event.session_id {
                        sessionId = sid
                    }
                    if let cost = event.total_cost_usd {
                        totalCost = cost
                    }
                    if let err = event.is_error {
                        isError = err
                    }
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
                model: model,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
        }
    }
}
