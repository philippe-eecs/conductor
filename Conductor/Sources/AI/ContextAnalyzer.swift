import Foundation

/// Represents what context Claude needs to answer a query
struct ContextNeed: Codable {
    /// Types of context that can be requested
    enum ContextType: Codable, Hashable {
        case calendar(filter: String?)
        case reminders(filter: String?)
        case goals
        case email(filter: String?)
        case notes
        case custom(description: String)

        var displayName: String {
            switch self {
            case .calendar: return "Calendar"
            case .reminders: return "Reminders"
            case .goals: return "Goals"
            case .email: return "Email"
            case .notes: return "Notes"
            case .custom(let desc): return desc
            }
        }

        var icon: String {
            switch self {
            case .calendar: return "calendar"
            case .reminders: return "checklist"
            case .goals: return "target"
            case .email: return "envelope"
            case .notes: return "note.text"
            case .custom: return "doc.text"
            }
        }
    }

    var types: [ContextType]
    var reasoning: String

    /// Whether any context is actually needed
    var needsContext: Bool {
        !types.isEmpty
    }

    /// Create an empty context need (no context required)
    static var none: ContextNeed {
        ContextNeed(types: [], reasoning: "No additional context needed for this query.")
    }
}

/// Response structure from Claude's context analysis
private struct ContextAnalysisResponse: Codable {
    let needs: [String]
    let filters: [String: String]?
    let reasoning: String
}

/// Analyzes user queries to determine what context would be helpful
/// Uses a lightweight model call with NO user data sent
final class ContextAnalyzer {
    static let shared = ContextAnalyzer()

    private let subprocessRunner: any SubprocessRunning
    private let claudeExecutableURLProvider: @Sendable () throws -> URL

    init(
        subprocessRunner: any SubprocessRunning = SystemSubprocessRunner(),
        claudeExecutableURLProvider: @escaping @Sendable () throws -> URL = {
            if let url = ExecutableResolver.resolve(name: "claude") {
                return url
            }
            throw ClaudeError.cliNotFound
        }
    ) {
        self.subprocessRunner = subprocessRunner
        self.claudeExecutableURLProvider = claudeExecutableURLProvider
    }

    /// Asks Claude what context would help answer the query
    /// Uses a small/fast model, sends NO user data - only the query structure
    func analyzeContextNeeds(for query: String) async throws -> ContextNeed {
        let prompt = buildAnalysisPrompt(query: query)

        // Use haiku for speed/cost - this is a lightweight analysis
        let args = ["--print", "--input-format", "text", "--output-format", "json", "--model", "haiku", "--tools", ""]

        let result = try await runClaudeCLI(args, stdin: (prompt + "\n").data(using: .utf8))

        guard result.exitCode == 0 else {
            // Fall back to requesting all context on error
            return ContextNeed(
                types: [.calendar(filter: nil), .reminders(filter: nil), .goals],
                reasoning: "Unable to analyze query - providing full context."
            )
        }

        return try parseAnalysisResponse(result.stdout)
    }

    /// Quick check if a query seems to need context at all
    /// This is a heuristic check to skip analysis for simple queries
    func quickContextCheck(for query: String) -> Bool {
        let lowercased = query.lowercased()

        // Patterns that typically need context
        let contextPatterns = [
            "calendar", "schedule", "meeting", "event", "appointment",
            "reminder", "remind", "todo", "task",
            "goal", "plan", "today", "tomorrow", "this week", "next week",
            "email", "mail", "message",
            "what's on", "what do i have", "am i free", "busy",
            "when is", "where is", "who is"
        ]

        return contextPatterns.contains { lowercased.contains($0) }
    }

    // MARK: - Private Methods

    private func buildAnalysisPrompt(query: String) -> String {
        """
        Analyze what context would help answer this user query. Do NOT answer the query itself.

        User query: "\(query)"

        Determine what personal context data would help provide a good answer.
        Available context types: calendar, reminders, goals, email, notes

        Respond with JSON only:
        {
          "needs": ["calendar", "reminders"],
          "filters": { "calendar": "meetings with Bob" },
          "reasoning": "Brief explanation of why this context is needed"
        }

        Rules:
        - Only request context that's actually relevant to the query
        - Use filters to narrow down context when the query mentions specific items
        - If no context is needed (e.g., general questions), return empty needs array
        - Keep reasoning under 50 words

        JSON response:
        """
    }

    private func parseAnalysisResponse(_ output: String) throws -> ContextNeed {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON from response
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            throw ContextAnalyzerError.invalidResponse
        }

        let jsonString = String(trimmed[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8) else {
            throw ContextAnalyzerError.invalidResponse
        }

        // First try parsing as JSON response from Claude
        if let response = try? JSONDecoder().decode(ClaudeService.ClaudeResponse.self, from: data) {
            // Parse the result field as our analysis response
            if let resultData = response.result.data(using: .utf8),
               let analysis = try? JSONDecoder().decode(ContextAnalysisResponse.self, from: resultData) {
                return buildContextNeed(from: analysis)
            }
        }

        // Try direct parse
        let analysis = try JSONDecoder().decode(ContextAnalysisResponse.self, from: data)
        return buildContextNeed(from: analysis)
    }

    private func buildContextNeed(from analysis: ContextAnalysisResponse) -> ContextNeed {
        var types: [ContextNeed.ContextType] = []
        let filters = analysis.filters ?? [:]

        for need in analysis.needs {
            switch need.lowercased() {
            case "calendar":
                types.append(.calendar(filter: filters["calendar"]))
            case "reminders":
                types.append(.reminders(filter: filters["reminders"]))
            case "goals":
                types.append(.goals)
            case "email":
                types.append(.email(filter: filters["email"]))
            case "notes":
                types.append(.notes)
            default:
                types.append(.custom(description: need))
            }
        }

        return ContextNeed(types: types, reasoning: analysis.reasoning)
    }

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
        let claudeURL = try claudeExecutableURLProvider()
        return try await subprocessRunner.run(
            executableURL: claudeURL,
            arguments: arguments,
            environment: subprocessEnvironment(),
            currentDirectoryURL: workingDirectoryURL(),
            stdin: stdin
        )
    }
}

// MARK: - Errors

enum ContextAnalyzerError: LocalizedError {
    case invalidResponse
    case analysisError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from context analysis"
        case .analysisError(let message):
            return "Context analysis error: \(message)"
        }
    }
}
