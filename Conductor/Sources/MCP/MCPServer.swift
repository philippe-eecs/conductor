import Foundation
import Network

/// In-process HTTP MCP server using Network.framework (NWListener).
/// Binds to 127.0.0.1:0 (OS-assigned port) and handles MCP JSON-RPC over HTTP.
/// Runs inside the app process so it shares the same TCC identity (calendar/reminders permissions).
final class MCPServer: @unchecked Sendable {
    static let shared = MCPServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.conductor.mcp-server")
    private let toolHandlers = MCPToolHandlers()

    /// The port the server is listening on, or nil if not started.
    private(set) var port: UInt16?

    /// Whether the server is currently running.
    var isRunning: Bool { port != nil }

    /// The full URL for the MCP endpoint.
    var endpointURL: String? {
        guard let port else { return nil }
        return "http://127.0.0.1:\(port)/mcp"
    }

    private init() {}

    // MARK: - Lifecycle

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
                        print("[MCP] Server listening on 127.0.0.1:\(port)")
                        // Eagerly write MCP config so it's ready before the first message
                        self?.writeMCPConfigEagerly(port: port)
                    }
                case .failed(let error):
                    print("[MCP] Server failed: \(error)")
                    self?.port = nil
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
            print("[MCP] Failed to create listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    /// The path where the MCP config file is written.
    static let configFilePath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let conductorDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)
        try? FileManager.default.createDirectory(at: conductorDir, withIntermediateDirectories: true)
        return conductorDir.appendingPathComponent("mcp-config.json").path
    }()

    /// Write MCP config immediately using the known port (avoids race with self.port).
    private func writeMCPConfigEagerly(port: UInt16) {
        let url = "http://127.0.0.1:\(port)/mcp"
        let config: [String: Any] = [
            "mcpServers": [
                "conductor-context": [
                    "type": "http",
                    "url": url
                ]
            ]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
            try data.write(to: URL(fileURLWithPath: Self.configFilePath), options: .atomic)
            print("[MCP] Wrote config to \(Self.configFilePath) (url=\(url))")
        } catch {
            print("[MCP] Failed to write config eagerly: \(error)")
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection, accumulated: Data())
    }

    private func receiveHTTPRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let content {
                buffer.append(content)
            }

            if let error {
                print("[MCP] Receive error: \(error)")
                connection.cancel()
                return
            }

            // Try to parse an HTTP request from the buffer
            if let request = self.parseHTTPRequest(from: buffer) {
                self.processHTTPRequest(request, on: connection)
            } else if isComplete {
                // Connection closed before we got a full request
                connection.cancel()
            } else {
                // Need more data
                self.receiveHTTPRequest(on: connection, accumulated: buffer)
            }
        }
    }

    // MARK: - HTTP Parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func parseHTTPRequest(from data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        guard let headerString = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let path = parts[1]

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
            if availableBody < contentLength {
                return nil // Need more data
            }
        }

        let body = data[bodyStart...]
        return HTTPRequest(method: method, path: path, headers: headers, body: Data(body.prefix(contentLength)))
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
        print("[MCP] \(request.method) \(request.path)")

        guard request.method == "POST", request.path == "/mcp" else {
            let body = Data(#"{"error":"Not Found"}"#.utf8)
            sendHTTPResponse(connection, status: 404, statusText: "Not Found", body: body)
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let method = json["method"] as? String else {
            print("[MCP] Failed to parse JSON-RPC body (\(request.body.count) bytes)")
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
        print("[MCP] method=\(method)")

        switch method {
        case "initialize":
            let result: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [
                        "tools": [:]
                    ],
                    "serverInfo": [
                        "name": "conductor-context",
                        "version": "1.0.0"
                    ]
                ]
            ]
            sendJSON(connection, result)

        case "notifications/initialized":
            // Client notification — no JSON-RPC response, but must send a valid HTTP response
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

            // Post notification for activity logging
            let argsDescription = (try? JSONSerialization.data(withJSONObject: arguments, options: []))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .mcpToolCalled,
                    object: nil,
                    userInfo: ["toolName": toolName, "arguments": argsDescription]
                )
            }

            // Handle tool calls asynchronously since they may need to access EventKit/DB
            Task {
                let toolResult = await self.toolHandlers.handleToolCall(name: toolName, arguments: arguments)
                let response: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": toolResult
                ]
                self.sendJSON(connection, response)
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
