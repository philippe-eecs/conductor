import XCTest
@testable import Conductor

final class EventKitIntegrationTests: XCTestCase {
    func test_getTodayEvents_returnsArrayOrSkipsWithoutPermission() async throws {
        let status = EventKitManager.shared.calendarAuthorizationStatus()
        guard status == .fullAccess else {
            throw XCTSkip("Calendar access not granted on this machine.")
        }

        let events = await EventKitManager.shared.getTodayEvents()
        // Non-deterministic contents; this is a smoke test that it doesn't crash/hang.
        XCTAssertNotNil(events)
    }

    func test_getUpcomingReminders_returnsEmptyWithoutPermission() async throws {
        let status = EventKitManager.shared.remindersAuthorizationStatus()
        if status != .fullAccess {
            let reminders = await EventKitManager.shared.getUpcomingReminders(limit: 5)
            XCTAssertEqual(reminders.count, 0)
        } else {
            let reminders = await EventKitManager.shared.getUpcomingReminders(limit: 5)
            XCTAssertNotNil(reminders)
        }
    }

    func test_getMonthEvents_returnsArrayOrSkipsWithoutPermission() async throws {
        let status = EventKitManager.shared.calendarAuthorizationStatus()
        guard status == .fullAccess else {
            throw XCTSkip("Calendar access not granted on this machine.")
        }

        let events = await EventKitManager.shared.getMonthEvents(for: Date())
        XCTAssertNotNil(events)
    }

    func test_getWeekEvents_returnsArrayOrSkipsWithoutPermission() async throws {
        let status = EventKitManager.shared.calendarAuthorizationStatus()
        guard status == .fullAccess else {
            throw XCTSkip("Calendar access not granted on this machine.")
        }

        let events = await EventKitManager.shared.getWeekEvents(for: Date())
        XCTAssertNotNil(events)
    }
}
