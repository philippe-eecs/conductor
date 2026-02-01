import XCTest
import SQLite
@testable import Conductor

final class DatabaseTests: XCTestCase {
    func test_loadRecentMessages_returnsMostRecentN_inChronologicalOrder() throws {
        let db = Database(connection: try Connection(.inMemory))

        let t1 = Date(timeIntervalSince1970: 1)
        let t2 = Date(timeIntervalSince1970: 2)
        let t3 = Date(timeIntervalSince1970: 3)

        let m1 = ChatMessage(role: .user, content: "m1", timestamp: t1)
        let m2 = ChatMessage(role: .user, content: "m2", timestamp: t2)
        let m3 = ChatMessage(role: .user, content: "m3", timestamp: t3)

        try db.saveMessage(m1, forSession: nil)
        try db.saveMessage(m2, forSession: nil)
        try db.saveMessage(m3, forSession: nil)

        let recent = try db.loadRecentMessages(limit: 2, forSession: nil)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].content, "m2")
        XCTAssertEqual(recent[1].content, "m3")
    }

    func test_associateOrphanedMessages_movesRecentNullSessionMessagesIntoSession() throws {
        let db = Database(connection: try Connection(.inMemory))
        let message = ChatMessage(role: .user, content: "orphan")
        try db.saveMessage(message, forSession: nil)

        try db.associateOrphanedMessages(withSession: "s1")
        let sessionMessages = try db.loadRecentMessages(limit: 10, forSession: "s1")
        XCTAssertEqual(sessionMessages.map(\.content), ["orphan"])
    }

    func test_preferences_setGetDelete() throws {
        let db = Database(connection: try Connection(.inMemory))

        try db.setPreference(key: "k", value: "v")
        XCTAssertEqual(try db.getPreference(key: "k"), "v")

        try db.deletePreference(key: "k")
        XCTAssertNil(try db.getPreference(key: "k"))
    }

    func test_saveSession_upsertsTitleAndLastUsed() throws {
        let db = Database(connection: try Connection(.inMemory))

        try db.saveSession(id: "s1", title: "First")
        try db.saveSession(id: "s1", title: "Updated")

        let sessions = try db.getRecentSessions(limit: 10)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "s1")
        XCTAssertEqual(sessions[0].title, "Updated")
    }
}

