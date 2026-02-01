import Foundation

/// Service for interacting with Gemini via the gemini CLI
/// Used for multimodal tasks (images, PDFs, web search)
final class GeminiService {
    static let shared = GeminiService()

    private let defaultModel = "gemini-2.5-pro-preview"

    private init() {}

    // MARK: - Public API

    /// Sends a text prompt to Gemini via CLI
    func sendMessage(_ prompt: String, model: String? = nil) async throws -> String {
        let modelToUse = model ?? defaultModel
        let args = [prompt, "-m", modelToUse, "-o", "text"]
        return try await runGeminiCLI(args)
    }

    /// Analyzes an image with a prompt
    func analyzeImage(_ imagePath: String, prompt: String, model: String? = nil) async throws -> String {
        let modelToUse = model ?? defaultModel
        let args = [prompt, "-m", modelToUse, "-o", "text", "--image", imagePath]
        return try await runGeminiCLI(args)
    }

    /// Performs a web search with the given query
    func webSearch(_ query: String, model: String? = nil) async throws -> String {
        let modelToUse = model ?? defaultModel
        // Gemini with google_web_search grounding
        let searchPrompt = "Search for and summarize: \(query)"
        let args = [searchPrompt, "-m", modelToUse, "-o", "text"]
        return try await runGeminiCLI(args)
    }

    /// Checks if the Gemini CLI is available
    func checkCLIAvailable() async -> Bool {
        do {
            let (output, exitCode) = try await runProcess(["which", "gemini"])
            return exitCode == 0 && !output.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Private Methods

    private func runGeminiCLI(_ arguments: [String]) async throws -> String {
        let (output, exitCode) = try await runProcess(["gemini"] + arguments)

        guard exitCode == 0 else {
            throw GeminiError.cliError("Gemini CLI exited with code \(exitCode): \(output)")
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runProcess(_ arguments: [String]) async throws -> (String, Int32) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                let errorPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = errorPipe

                // Set up environment
                var environment = ProcessInfo.processInfo.environment
                if let path = environment["PATH"] {
                    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
                }
                process.environment = environment

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    var output = String(data: outputData, encoding: .utf8) ?? ""

                    if output.isEmpty {
                        output = String(data: errorData, encoding: .utf8) ?? ""
                    }

                    continuation.resume(returning: (output, process.terminationStatus))
                } catch {
                    continuation.resume(throwing: GeminiError.processError(error.localizedDescription))
                }
            }
        }
    }
}

enum GeminiError: LocalizedError {
    case cliNotFound
    case cliError(String)
    case processError(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Gemini CLI not found. Install with: pip install google-generativeai"
        case .cliError(let message):
            return "Gemini CLI error: \(message)"
        case .processError(let message):
            return "Process error: \(message)"
        }
    }
}
