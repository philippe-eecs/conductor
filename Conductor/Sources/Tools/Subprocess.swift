import Foundation

struct SubprocessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol SubprocessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL?,
        stdin: Data?
    ) async throws -> SubprocessResult
}

enum SubprocessError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason):
            return "Failed to launch subprocess: \(reason)"
        }
    }
}

struct SystemSubprocessRunner: SubprocessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectoryURL: URL?,
        stdin: Data?
    ) async throws -> SubprocessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.environment = environment
                process.currentDirectoryURL = currentDirectoryURL

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                var stdoutData = Data()
                var stderrData = Data()
                let lock = NSLock()

                stdoutHandle.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { return }
                    lock.lock()
                    stdoutData.append(chunk)
                    lock.unlock()
                }

                stderrHandle.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { return }
                    lock.lock()
                    stderrData.append(chunk)
                    lock.unlock()
                }

                if let stdin {
                    let stdinPipe = Pipe()
                    process.standardInput = stdinPipe
                    do {
                        try process.run()
                        try stdinPipe.fileHandleForWriting.write(contentsOf: stdin)
                        try? stdinPipe.fileHandleForWriting.close()
                    } catch {
                        stdoutHandle.readabilityHandler = nil
                        stderrHandle.readabilityHandler = nil
                        continuation.resume(throwing: SubprocessError.launchFailed(error.localizedDescription))
                        return
                    }
                } else {
                    do {
                        try process.run()
                    } catch {
                        stdoutHandle.readabilityHandler = nil
                        stderrHandle.readabilityHandler = nil
                        continuation.resume(throwing: SubprocessError.launchFailed(error.localizedDescription))
                        return
                    }
                }

                process.waitUntilExit()

                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil

                lock.lock()
                stdoutData.append(stdoutHandle.readDataToEndOfFile())
                stderrData.append(stderrHandle.readDataToEndOfFile())
                lock.unlock()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(returning: SubprocessResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                ))
            }
        }
    }
}
