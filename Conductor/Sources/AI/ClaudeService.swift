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
    private var model: String = "sonnet"

    private let subprocessRunner: any SubprocessRunning
    private let now: @Sendable () -> Date
    private let claudeExecutableURLProvider: @Sendable () throws -> URL

    init(
        subprocessRunner: any SubprocessRunning = SystemSubprocessRunner(),
        now: @escaping @Sendable () -> Date = { Date() },
        claudeExecutableURLProvider: @escaping @Sendable () throws -> URL = {
            if let url = ExecutableResolver.resolve(name: "claude") {
                return url
            }
            throw ClaudeError.cliNotFound
        }
    ) {
        self.subprocessRunner = subprocessRunner
        self.now = now
        self.claudeExecutableURLProvider = claudeExecutableURLProvider
    }

    // MARK: - Response Types

    struct ClaudeResponse: Codable {
        let result: String
        let totalCostUsd: Double?
        let sessionId: String?
        let duration_ms: Int?
        let num_turns: Int?
        let is_error: Bool?

        enum CodingKeys: String, CodingKey {
            case result
            case totalCostUsd = "total_cost_usd"
            case sessionId = "session_id"
            case duration_ms
            case num_turns
            case is_error
        }
    }

    struct StreamMessage: Codable {
        let type: String
        let message: StreamMessageContent?
        let session_id: String?
        let result: String?
        let total_cost_usd: Double?
        let is_error: Bool?
    }

    struct StreamMessageContent: Codable {
        let role: String?
        let content: String?
    }

    // MARK: - Public API

    /// Sends a message to Claude via the CLI subprocess
    /// - Parameters:
    ///   - userMessage: The user's message
    ///   - context: Optional context data (calendar, reminders, etc.)
    ///   - history: Previous chat messages (used for building context, not sent directly)
    ///   - toolsEnabled: When true, Claude can use tools (with user approval). Default: false (safe mode)
    ///   - modelOverride: Optional model name passed to the Claude CLI via `--model` (e.g. "sonnet", "opus").
    /// - Returns: The assistant's response
    func sendMessage(_ userMessage: String, context: ContextData?, history: [ChatMessage], toolsEnabled: Bool = false, modelOverride: String? = nil) async throws -> ClaudeResponse {
        // Build arguments for the claude CLI.
        // - Use --print for non-interactive mode.
        // - Pass the full prompt via stdin to avoid leaking content via argv.
        let trimmedOverride = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenModel = (trimmedOverride?.isEmpty == false) ? trimmedOverride! : model

        var args = ["--print", "--input-format", "text", "--output-format", "json", "--model", chosenModel]

        // Tools mode: disabled by default for safety, enabled allows Claude to execute commands
        // When enabled, Claude Code will prompt for approval on dangerous operations
        if !toolsEnabled {
            args += ["--tools", ""]
        }

        // Continue session if we have one
        if let sessionId = currentSessionId {
            args += ["--resume", sessionId]
        }

        let fullPrompt = buildPrompt(userMessage: userMessage, context: context, history: history)
        let result = try await runClaudeCLI(args, stdin: (fullPrompt + "\n").data(using: .utf8))

        guard result.exitCode == 0 else {
            let message = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Unknown error"
            throw ClaudeError.cliError("Claude CLI exited with code \(result.exitCode): \(message)")
        }

        // Parse the JSON response
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

    private func buildPrompt(userMessage: String, context: ContextData?, history: [ChatMessage]) -> String {
        var prompt = """
        You are Conductor, a personal AI assistant running as a macOS menubar app.
        You help users manage their day, tasks, and projects.

        Key behaviors:
        - Be concise and actionable
        - Use bullet points and clear formatting
        - Proactively suggest relevant actions

        Current date and time: \(formattedDateTime(now()))
        """

        // Build context access summary - explicitly state what IS and ISN'T available
        prompt += "\n\n## Your Context Access:"

        if let context {
            // Calendar status
            if context.todayEvents.isEmpty {
                prompt += "\n- Calendar: No events today ✓"
            } else {
                prompt += "\n- Calendar: \(context.todayEvents.count) event\(context.todayEvents.count == 1 ? "" : "s") today ✓"
            }

            // Reminders status
            if context.upcomingReminders.isEmpty {
                prompt += "\n- Reminders: No pending reminders ✓"
            } else {
                prompt += "\n- Reminders: \(context.upcomingReminders.count) pending ✓"
            }

            // Goals status
            if let planning = context.planningContext {
                let incompleteGoals = planning.todaysGoals.filter { !$0.isCompleted }.count
                if planning.todaysGoals.isEmpty {
                    prompt += "\n- Goals: No goals set for today ✓"
                } else if incompleteGoals == 0 {
                    prompt += "\n- Goals: All \(planning.todaysGoals.count) goals completed ✓"
                } else {
                    prompt += "\n- Goals: \(incompleteGoals) of \(planning.todaysGoals.count) incomplete ✓"
                }
                if planning.overdueCount > 0 {
                    prompt += "\n- Overdue: \(planning.overdueCount) overdue goal\(planning.overdueCount == 1 ? "" : "s")"
                }
            } else {
                prompt += "\n- Goals: Not enabled"
            }

            // Email status
            if let email = context.emailContext {
                if email.unreadCount == 0 {
                    prompt += "\n- Email: No unread emails ✓"
                } else {
                    prompt += "\n- Email: \(email.unreadCount) unread ✓"
                }
            } else {
                prompt += "\n- Email: Not enabled (user preference)"
            }

            // Notes status
            if context.recentNotes.isEmpty {
                prompt += "\n- Notes: No recent notes"
            } else {
                prompt += "\n- Notes: \(context.recentNotes.count) recent ✓"
            }

            // Now output the actual data
            if !context.todayEvents.isEmpty {
                prompt += "\n\n## Today's Calendar:\n"
                for event in context.todayEvents {
                    prompt += "- \(event.time): \(event.title)"
                    if let location = event.location {
                        prompt += " (\(location))"
                    }
                    prompt += "\n"
                }
            }

            if !context.upcomingReminders.isEmpty {
                prompt += "\n\n## Upcoming Reminders:\n"
                for reminder in context.upcomingReminders {
                    prompt += "- \(reminder.title)"
                    if let dueDate = reminder.dueDate {
                        prompt += " (due: \(dueDate))"
                    }
                    prompt += "\n"
                }
            }

            if let planning = context.planningContext, !planning.todaysGoals.isEmpty {
                prompt += "\n\n## Today's Goals:\n"
                for goal in planning.todaysGoals {
                    let status = goal.isCompleted ? "✓" : "○"
                    prompt += "- \(status) \(goal.text)\n"
                }
            }

            if !context.recentNotes.isEmpty {
                prompt += "\n\n## Recent Notes:\n"
                for note in context.recentNotes {
                    prompt += "- \(note)\n"
                }
            }

            if let email = context.emailContext, !email.importantEmails.isEmpty {
                prompt += "\n\n## Important Emails:\n"
                for emailItem in email.importantEmails {
                    let readStatus = emailItem.isRead ? "" : " (unread)"
                    prompt += "- From \(emailItem.sender): \(emailItem.subject)\(readStatus)\n"
                }
            }
        } else {
            // No context available at all
            prompt += "\n- Calendar: Not connected"
            prompt += "\n- Reminders: Not connected"
            prompt += "\n- Goals: Not connected"
            prompt += "\n- Email: Not connected"
            prompt += "\n- Notes: Not connected"
        }

        // Claude CLI maintains conversation context via --resume; history is currently unused.
        _ = history

        prompt += "\n\n## User:\n\(userMessage)\n"
        return prompt
    }

    private func formattedDateTime(_ date: Date) -> String {
        SharedDateFormatters.fullDateTime.string(from: date)
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
            guard let data = trimmed.data(using: .utf8) else {
                throw ClaudeError.invalidResponse
            }

            do {
                return try JSONDecoder().decode(ClaudeResponse.self, from: data)
            } catch {
                return try parseStreamResponse(trimmed)
            }
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

            for line in lines {
                guard let data = line.data(using: .utf8) else { continue }
                guard let message = try? JSONDecoder().decode(StreamMessage.self, from: data) else { continue }

                if let content = message.message?.content {
                    resultText += content
                }
                if let sid = message.session_id {
                    sessionId = sid
                }
                if let result = message.result {
                    resultText = result
                }
                if let cost = message.total_cost_usd {
                    totalCost = cost
                }
                if let error = message.is_error {
                    isError = error
                }
            }

            if resultText.isEmpty {
                resultText = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return ClaudeResponse(
                result: resultText,
                totalCostUsd: totalCost,
                sessionId: sessionId,
                duration_ms: nil,
                num_turns: nil,
                is_error: isError
            )
        }
    }
}
