import Foundation
import os

/// Auth policy for local MCP HTTP endpoint.
/// Uses a per-launch bearer token and short-lived validity window.
final class MCPAuthPolicy {
    static let shared = MCPAuthPolicy()

    let maxRequestBodyBytes: Int = 256 * 1024

    private let token: String
    private let expiresAt: Date

    init(token: String? = nil, expiresAt: Date? = nil) {
        self.token = token ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        self.expiresAt = expiresAt ?? Date().addingTimeInterval(12 * 60 * 60)
    }

    func endpointURLString(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/mcp"
    }

    func authorizationHeaderValue() -> String {
        "Bearer \(token)"
    }

    func isAuthorized(headers: [String: String], rawPath: String) -> Bool {
        guard Date() < expiresAt else { return false }

        if let authHeader = headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           authHeader.lowercased().hasPrefix("bearer ") {
            let provided = String(authHeader.dropFirst("bearer ".count))
            if provided == token {
                return true
            }
        }

        // Backward compat: accept query-param auth but log a warning
        guard let comps = URLComponents(string: "http://localhost\(rawPath)"),
              let queryItems = comps.queryItems else {
            return false
        }

        if let queryToken = queryItems.first(where: { $0.name == "auth" })?.value,
           queryToken == token {
            Log.mcp.warning("Client authenticated via query-param token — migrate to Authorization header")
            return true
        }

        return false
    }

    func normalizedPath(from rawPath: String) -> String {
        guard let comps = URLComponents(string: "http://localhost\(rawPath)") else {
            return rawPath
        }
        return comps.path
    }
}
