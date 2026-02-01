import Foundation

/// Service that interfaces with the Claude CLI (`claude` command) as a subprocess.
/// Uses the user's existing Claude Code Max subscription instead of requiring API keys.
///
/// This is an actor to ensure thread-safe access to session state.
actor ClaudeService {
    static let shared = ClaudeService()

    /// Current session ID for conversation continuity
    private var currentSessionId: String?

    /// Model to use for requests
    private var model: String = "sonnet"

    private init() {}

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
    /// - Returns: The assistant's response
    func sendMessage(_ userMessage: String, context: ContextData?, history: [ChatMessage]) async throws -> ClaudeResponse {
        // Build the system prompt with context
        let systemPrompt = buildSystemPrompt(context: context)

        // Build arguments for the claude CLI
        // Note: We pass prompts via stdin, not argv, for security
        var args = ["--output-format", "stream-json", "--model", model]

        // Continue session if we have one
        if let sessionId = currentSessionId {
            args += ["--resume", sessionId]
        }

        // Run the claude CLI with user message via stdin (more secure than argv)
        let (output, exitCode) = try await runClaudeCLI(args, stdin: userMessage, systemPrompt: systemPrompt)

        guard exitCode == 0 else {
            throw ClaudeError.cliError("Claude CLI exited with code \(exitCode): \(output)")
        }

        // Parse the JSON response
        let response = try parseResponse(output)

        // Check for error response
        if response.is_error == true {
            throw ClaudeError.cliError(response.result)
        }

        // Save session for continuity
        if let sessionId = response.sessionId {
            currentSessionId = sessionId
            try? Database.shared.saveSession(id: sessionId, title: extractTitle(from: userMessage))
            // Associate any messages that were saved before we had a session ID
            try? Database.shared.associateOrphanedMessages(withSession: sessionId)
        }

        // Log cost using CostTracker
        if let cost = response.totalCostUsd {
            let sessionId = response.sessionId ?? currentSessionId
            CostTracker.shared.logCost(amount: cost, sessionId: sessionId)
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
    nonisolated func checkCLIAvailable() async -> Bool {
        do {
            let (output, exitCode) = try await runProcess(["which", "claude"], stdin: nil)
            return exitCode == 0 && !output.isEmpty
        } catch {
            return false
        }
    }

    /// Gets Claude CLI version
    nonisolated func getCLIVersion() async -> String? {
        do {
            let (output, exitCode) = try await runProcess(["claude", "--version"], stdin: nil)
            if exitCode == 0 {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // CLI not available
        }
        return nil
    }

    // MARK: - Private Methods

    private func runClaudeCLI(_ arguments: [String], stdin: String?, systemPrompt: String) async throws -> (String, Int32) {
        // User message is passed via stdin (more secure than argv)
        // System prompt is passed as argument (less sensitive, contains app context)
        var fullArgs = ["claude"] + arguments
        fullArgs += ["--system-prompt", systemPrompt]

        return try await runProcess(fullArgs, stdin: stdin)
    }

    private nonisolated func runProcess(_ arguments: [String], stdin: String?) async throws -> (String, Int32) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let stdinPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.standardInput = stdinPipe

                // Build a minimal, safe environment
                // Don't inherit the full parent environment which may contain secrets
                var environment: [String: String] = [:]

                // Always set PATH including common CLI locations
                // GUI apps may have minimal/missing PATH
                let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                if let existingPath = ProcessInfo.processInfo.environment["PATH"] {
                    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + existingPath
                } else {
                    environment["PATH"] = defaultPath
                }

                // Pass through only necessary environment variables
                let safeVars = ["HOME", "USER", "LANG", "LC_ALL", "TMPDIR", "XDG_CONFIG_HOME", "XDG_DATA_HOME"]
                for key in safeVars {
                    if let value = ProcessInfo.processInfo.environment[key] {
                        environment[key] = value
                    }
                }

                process.environment = environment

                do {
                    try process.run()

                    // Write stdin content if provided, then close
                    if let stdinContent = stdin, let data = stdinContent.data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                    }
                    stdinPipe.fileHandleForWriting.closeFile()

                    // Read pipes BEFORE waiting to prevent deadlock
                    // If the child writes enough to fill the pipe buffer and we're
                    // waiting for exit, we'll deadlock
                    let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    // Now wait for process to exit
                    process.waitUntilExit()

                    var output = String(data: outputData, encoding: .utf8) ?? ""

                    // If no stdout, check stderr
                    if output.isEmpty {
                        output = String(data: errorData, encoding: .utf8) ?? ""
                    }

                    continuation.resume(returning: (output, process.terminationStatus))
                } catch {
                    continuation.resume(throwing: ClaudeError.processError(error.localizedDescription))
                }
            }
        }
    }

    private func parseResponse(_ output: String) throws -> ClaudeResponse {
        guard let data = output.data(using: .utf8) else {
            throw ClaudeError.invalidResponse
        }

        // Try to parse as standard JSON response first
        do {
            let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            return response
        } catch {
            // Try to parse as stream-json (multiple JSON objects)
            return try parseStreamResponse(output)
        }
    }

    private func parseStreamResponse(_ output: String) throws -> ClaudeResponse {
        var resultText = ""
        var sessionId: String?
        var totalCost: Double?
        var isError: Bool?

        // More robust parsing: handle potential multi-line JSON or mixed content
        // Split by newlines but also handle cases where JSON might span lines
        var jsonBuffer = ""
        var braceCount = 0

        for char in output {
            jsonBuffer.append(char)

            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1

                // When we close all braces, try to parse
                if braceCount == 0 && !jsonBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
                    if let data = jsonBuffer.data(using: .utf8),
                       let message = try? JSONDecoder().decode(StreamMessage.self, from: data) {
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
                    jsonBuffer = ""
                }
            }
        }

        // If we couldn't parse anything, treat the whole output as the result
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

    private func buildSystemPrompt(context: ContextData?) -> String {
        let resourceInfo = getResourceSnapshot()

        var prompt = """
        You are Conductor, a personal AI assistant running as a macOS menubar app.
        You help users manage their day, tasks, and projects.

        Key behaviors:
        - Be concise and actionable
        - Use bullet points and clear formatting
        - Proactively suggest relevant actions
        - Remember context from the conversation

        Current date and time: \(formattedDateTime())

        ## System Resources
        \(resourceInfo)

        You can help users check and manage system resources. If the system is under heavy load,
        proactively mention it. You can run bash commands like `top -l 1`, `ps aux -r`, or `kill <pid>`
        to help diagnose and resolve resource issues.
        """

        if let context = context {
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

            if !context.recentNotes.isEmpty {
                prompt += "\n\n## Recent Notes:\n"
                for note in context.recentNotes {
                    prompt += "- \(note)\n"
                }
            }
        }

        return prompt
    }

    private func formattedDateTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        return formatter.string(from: Date())
    }

    /// Gets a quick snapshot of system resources (CPU, memory, top processes)
    private nonisolated func getResourceSnapshot() -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", """
            echo "Memory: $(memory_pressure 2>/dev/null | grep 'System-wide' | awk '{print $NF}')"
            top -l 1 -n 5 -stats pid,command,cpu,mem 2>/dev/null | tail -6
            """]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // Silently fail - resource info is optional context
        }

        return "Unable to fetch resource info"
    }

    private func extractTitle(from message: String) -> String {
        // Extract first 50 characters or first sentence as session title
        let truncated = String(message.prefix(50))
        if let periodIndex = truncated.firstIndex(of: ".") {
            return String(truncated[..<periodIndex])
        }
        if let newlineIndex = truncated.firstIndex(of: "\n") {
            return String(truncated[..<newlineIndex])
        }
        return truncated
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
