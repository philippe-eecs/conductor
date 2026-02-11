import XCTest
@testable import Conductor

final class AssistantActionModelsTests: XCTestCase {
    func test_decodeEnvelope_withWebTaskAndHumanSteps() throws {
        let json = """
        {
          "actions": [
            {
              "id": "a1",
              "type": "webTask",
              "title": "Log into Example Bank and download statement",
              "requiresUserApproval": true,
              "humanSteps": [
                { "id": "s1", "kind": "login", "instructions": "Please sign in in the embedded browser." },
                { "id": "s2", "kind": "twoFactor", "instructions": "Approve the 2FA prompt on your phone." }
              ],
              "payload": { "url": "https://example.com" }
            }
          ],
          "notes": "Waiting for user interaction."
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AssistantActionEnvelope.self, from: data)

        XCTAssertEqual(decoded.actions.count, 1)
        XCTAssertEqual(decoded.actions[0].id, "a1")
        XCTAssertEqual(decoded.actions[0].type, .webTask)
        XCTAssertEqual(decoded.actions[0].humanSteps?.count, 2)
        XCTAssertEqual(decoded.actions[0].payload?["url"], "https://example.com")
        XCTAssertEqual(decoded.notes, "Waiting for user interaction.")
    }
}

