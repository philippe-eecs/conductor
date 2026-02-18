import Foundation
import Network
import os

final class MCPServer: @unchecked Sendable {
    static let shared = MCPServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.conductor.mcp-server")
    private let toolHandlers = MCPToolHandlers()

    private(set) var port: UInt16?

    var isRunning: Bool { port != nil }

    var endpointURL: String? {
        guard let port else { return nil }
        return MCPAuthPolicy.shared.endpointURLString(port: port)
    }

    private var retryCount = 0
    private let maxRetries = 3

    private init() {}

    // MARK: - Lifecycle

    func startWithRetry() {
        retryCount = 0
        start()
    }

    func start() {
        guard listener == nil else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params, on: .any)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        self?.port = port
                        self?.retryCount = 0
                        Log.mcp.info("Server listening on 127.0.0.1:\(port, privacy: .public)")
                        self?.writeMCPConfigEagerly(port: port)
                    }
                case .failed(let error):
                    Log.mcp.error("Server failed: \(error.localizedDescription, privacy: .public)")
                    self?.port = nil
                    self?.listener?.cancel()
                    self?.listener = nil
                    self?.handleRetry()
                case .cancelled:
                    self?.port = nil
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Log.mcp.error("Failed to create listener: \(error.localizedDescription, privacy: .public)")
            handleRetry()
        }
    }

    private func handleRetry() {
        if retryCount < maxRetries {
            retryCount += 1
            Log.mcp.warning("Retrying MCP server start (\(self.retryCount)/\(self.maxRetries))...")
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.start()
            }
        } else {
            Log.mcp.fault("MCP server failed after \(self.maxRetries) retries")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .mcpServerFailed, object: nil)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    static let configFilePath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let conductorDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)
        try? FileManager.default.createDirectory(at: conductorDir, withIntermediateDirectories: true)
        return conductorDir.appendingPathComponent("mcp-config.json").path
    }()

    private func writeMCPConfigEagerly(port: UInt16) {
        let url = MCPAuthPolicy.shared.endpointURLString(port: port)
        let config: [String: Any] = [
            "mcpServers": [
                "conductor-context": [
                    "type": "http",
                    "url": url,
                    "headers": ["Authorization": MCPAuthPolicy.shared.authorizationHeaderValue()]
                ]
            ]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
            try data.write(to: URL(fileURLWithPath: Self.configFilePath), options: .atomic)
            Log.mcp.info("Wrote config to \(Self.configFilePath, privacy: .public)")
        } catch {
            Log.mcp.error("Failed to write config eagerly: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection, accumulated: Data())
    }

    private static let idleTimeoutSeconds: Int = 30

    private func receiveHTTPRequest(on connection: NWConnection, accumulated: Data) {
        let timeout = DispatchWorkItem { [weak self] in
            Log.mcp.warning("Connection idle timeout — cancelling")
            self?.sendHTTPResponse(connection, status: 408, statusText: "Request Timeout",
                                   body: Data(#"{"error":"Request timeout"}"#.utf8))
        }
        queue.asyncAfter(deadline: .now() + .seconds(Self.idleTimeoutSeconds), execute: timeout)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            timeout.cancel()

            guard let self else {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let content { buffer.append(content) }

            if buffer.count > MCPAuthPolicy.shared.maxRequestBodyBytes {
                let body = Data(#"{"error":"Request too large"}"#.utf8)
                self.sendHTTPResponse(connection, status: 413, statusText: "Payload Too Large", body: body)
                return
            }

            if let error {
                Log.mcp.error("Receive error: \(error.localizedDescription, privacy: .public)")
                connection.cancel()
                return
            }

            if let request = self.parseHTTPRequest(from: buffer) {
                self.processHTTPRequest(request, on: connection)
            } else if isComplete {
                connection.cancel()
            } else {
                self.receiveHTTPRequest(on: connection, accumulated: buffer)
            }
        }
    }

    // MARK: - HTTP Parsing

    private struct HTTPRequest {
        let method: String
        let rawPath: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func parseHTTPRequest(from data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        guard let headerString = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let rawPath = parts[1]
        let path = MCPAuthPolicy.shared.normalizedPath(from: rawPath)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let bodyStart = headerEnd.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0

        if contentLength > 0 {
            let availableBody = data.count - data.distance(from: data.startIndex, to: bodyStart)
            if availableBody < contentLength { return nil }
        }

        let body = data[bodyStart...]
        return HTTPRequest(method: method, rawPath: rawPath, path: path, headers: headers, body: Data(body.prefix(contentLength)))
    }

    // MARK: - HTTP Response

    private func sendHTTPResponse(_ connection: NWConnection, status: Int, statusText: String, body: Data) {
        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"

        var responseData = Data(response.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendJSON(_ connection: NWConnection, _ value: Any) {
        do {
            let data = try JSONSerialization.data(withJSONObject: value)
            sendHTTPResponse(connection, status: 200, statusText: "OK", body: data)
        } catch {
            let errorBody = Data(#"{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal serialization error"}}"#.utf8)
            sendHTTPResponse(connection, status: 500, statusText: "Internal Server Error", body: errorBody)
        }
    }

    // MARK: - Request Processing

    private func processHTTPRequest(_ request: HTTPRequest, on connection: NWConnection) {
        Log.mcp.info("\(request.method, privacy: .public) \(request.path, privacy: .public)")

        guard request.method == "POST", request.path == "/mcp" else {
            let body = Data(#"{"error":"Not Found"}"#.utf8)
            sendHTTPResponse(connection, status: 404, statusText: "Not Found", body: body)
            return
        }

        guard MCPAuthPolicy.shared.isAuthorized(headers: request.headers, rawPath: request.rawPath) else {
            let body = Data(#"{"error":"Unauthorized"}"#.utf8)
            sendHTTPResponse(connection, status: 401, statusText: "Unauthorized", body: body)
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let method = json["method"] as? String else {
            let errorResp: [String: Any] = [
                "jsonrpc": "2.0",
                "error": ["code": -32700, "message": "Parse error"],
                "id": NSNull()
            ]
            sendJSON(connection, errorResp)
            return
        }

        let id = json["id"] ?? NSNull()
        let params = json["params"] as? [String: Any] ?? [:]
        Log.mcp.info("method=\(method, privacy: .public)")

        switch method {
        case "initialize":
            let result: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "conductor-context", "version": "2.0.0"]
                ]
            ]
            sendJSON(connection, result)

        case "notifications/initialized":
            let emptyBody = Data("{}".utf8)
            sendHTTPResponse(connection, status: 200, statusText: "OK", body: emptyBody)

        case "tools/list":
            let tools = MCPToolHandlers.toolDefinitions()
            let result: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "result": ["tools": tools]
            ]
            sendJSON(connection, result)

        case "tools/call":
            let toolName = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]

            guard MCPToolHandlers.allowedToolNames.contains(toolName) else {
                let errorResp: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": ["code": -32602, "message": "Tool not allowed: \(toolName)"]
                ]
                sendJSON(connection, errorResp)
                return
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .mcpToolCalled,
                    object: nil,
                    userInfo: ["toolName": toolName]
                )
            }

            Task {
                let toolResult = await self.toolHandlers.handleToolCall(name: toolName, arguments: arguments)
                self.queue.async {
                    let response: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": id,
                        "result": toolResult
                    ]
                    self.sendJSON(connection, response)
                }
            }

        default:
            let errorResp: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "error": ["code": -32601, "message": "Method not found: \(method)"]
            ]
            sendJSON(connection, errorResp)
        }
    }
}
