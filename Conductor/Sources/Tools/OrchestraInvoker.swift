import Foundation

/// Invokes Orchestra multi-agent workflows as a subprocess
final class OrchestraInvoker {
    static let shared = OrchestraInvoker()

    private init() {}

    struct OrchestraResult {
        let exitCode: Int32
        let output: String
        let error: String
    }

    /// Run an Orchestra workflow
    func runWorkflow(
        prompt: String,
        agents: [String]? = nil,
        outputPath: String? = nil
    ) async throws -> OrchestraResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        var arguments = ["orchestra", "run"]

        if let agents = agents {
            arguments.append("--agents")
            arguments.append(agents.joined(separator: ","))
        }

        if let outputPath = outputPath {
            arguments.append("--output")
            arguments.append(outputPath)
        }

        arguments.append(prompt)

        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw OrchestraError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        return OrchestraResult(
            exitCode: process.terminationStatus,
            output: output,
            error: error
        )
    }

    /// Check if Orchestra is installed
    func isInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["orchestra"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum OrchestraError: LocalizedError {
    case launchFailed(String)
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason):
            return "Failed to launch Orchestra: \(reason)"
        case .notInstalled:
            return "Orchestra is not installed"
        }
    }
}
