import XCTest
@testable import Conductor

final class MCPAuthPolicyTests: XCTestCase {
    func test_isAuthorized_acceptsBearerAndQueryToken() {
        let policy = MCPAuthPolicy(token: "token123", expiresAt: Date().addingTimeInterval(300))

        XCTAssertTrue(policy.isAuthorized(headers: ["authorization": "Bearer token123"], rawPath: "/mcp"))
        XCTAssertTrue(policy.isAuthorized(headers: [:], rawPath: "/mcp?auth=token123"))
        XCTAssertFalse(policy.isAuthorized(headers: ["authorization": "Bearer wrong"], rawPath: "/mcp"))
        XCTAssertFalse(policy.isAuthorized(headers: [:], rawPath: "/mcp?auth=wrong"))
    }

    func test_isAuthorized_rejectsExpiredToken() {
        let policy = MCPAuthPolicy(token: "token123", expiresAt: Date().addingTimeInterval(-5))

        XCTAssertFalse(policy.isAuthorized(headers: ["authorization": "Bearer token123"], rawPath: "/mcp"))
        XCTAssertFalse(policy.isAuthorized(headers: [:], rawPath: "/mcp?auth=token123"))
    }

    func test_normalizedPath_stripsQuery() {
        let policy = MCPAuthPolicy(token: "token123", expiresAt: Date().addingTimeInterval(300))
        XCTAssertEqual(policy.normalizedPath(from: "/mcp?auth=token123"), "/mcp")
        XCTAssertEqual(policy.normalizedPath(from: "/mcp"), "/mcp")
    }

    func test_endpointURLString_doesNotContainToken() {
        let policy = MCPAuthPolicy(token: "secret42", expiresAt: Date().addingTimeInterval(300))
        let url = policy.endpointURLString(port: 12345)
        XCTAssertFalse(url.contains("secret42"), "Token should not appear in the endpoint URL")
        XCTAssertEqual(url, "http://127.0.0.1:12345/mcp")
    }

    func test_authorizationHeaderValue_returnsBearerFormat() {
        let policy = MCPAuthPolicy(token: "abc123", expiresAt: Date().addingTimeInterval(300))
        XCTAssertEqual(policy.authorizationHeaderValue(), "Bearer abc123")
    }
}
