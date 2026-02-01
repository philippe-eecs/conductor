import XCTest
import SQLite
@testable import Conductor

final class ContextBuilderTests: XCTestCase {
    actor CountingEventKit: EventKitProviding {
        private(set) var todayEventsCalls = 0
        private(set) var remindersCalls = 0

        let events: [EventKitManager.CalendarEvent]
        let reminders: [EventKitManager.Reminder]

        init(events: [EventKitManager.CalendarEvent], reminders: [EventKitManager.Reminder]) {
            self.events = events
            self.reminders = reminders
        }

        func getTodayEvents() async -> [EventKitManager.CalendarEvent] {
            todayEventsCalls += 1
            return events
        }

        func getUpcomingReminders(limit: Int) async -> [EventKitManager.Reminder] {
            remindersCalls += 1
            return Array(reminders.prefix(limit))
        }

        func getMonthEvents(for date: Date) async -> [EventKitManager.CalendarEvent] {
            []
        }

        func getWeekEvents(for date: Date) async -> [EventKitManager.CalendarEvent] {
            []
        }

        func getEventsForDay(_ date: Date) async -> [EventKitManager.CalendarEvent] {
            []
        }
    }

    func test_buildContext_respectsCalendarAndRemindersPreferenceToggles() async throws {
        let db = Database(connection: try Connection(.inMemory))

        // Disable both sources.
        try db.setPreference(key: "calendar_read_enabled", value: "false")
        try db.setPreference(key: "reminders_read_enabled", value: "false")
        try db.setPreference(key: "email_integration_enabled", value: "false")

        let event = EventKitManager.CalendarEvent(
            id: "e1",
            title: "Standup",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            location: "Zoom",
            notes: nil,
            isAllDay: false
        )
        let reminder = EventKitManager.Reminder(
            id: "r1",
            title: "Call mom",
            notes: nil,
            dueDate: "Feb 2, 2026",
            isCompleted: false,
            priority: 0
        )

        let ek = CountingEventKit(events: [event], reminders: [reminder])
        let builder = ContextBuilder(eventKit: ek, database: db)

        let context = await builder.buildContext()
        XCTAssertTrue(context.todayEvents.isEmpty)
        XCTAssertTrue(context.upcomingReminders.isEmpty)

        let calls = await (ek.todayEventsCalls, ek.remindersCalls)
        XCTAssertEqual(calls.0, 0)
        XCTAssertEqual(calls.1, 0)
    }

    func test_buildContext_includesCalendarAndRemindersWhenEnabled() async throws {
        let db = Database(connection: try Connection(.inMemory))

        try db.setPreference(key: "calendar_read_enabled", value: "true")
        try db.setPreference(key: "reminders_read_enabled", value: "true")
        try db.setPreference(key: "email_integration_enabled", value: "false")

        _ = try db.saveNote(title: "Note", content: "Remember to follow up with Alex.")

        let event = EventKitManager.CalendarEvent(
            id: "e1",
            title: "Design Review",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            location: "Room 2",
            notes: nil,
            isAllDay: false
        )
        let reminder = EventKitManager.Reminder(
            id: "r1",
            title: "Submit expenses",
            notes: nil,
            dueDate: "Feb 2, 2026",
            isCompleted: false,
            priority: 5
        )

        let ek = CountingEventKit(events: [event], reminders: [reminder])
        let builder = ContextBuilder(eventKit: ek, database: db)

        let context = await builder.buildContext()
        XCTAssertEqual(context.todayEvents.count, 1)
        XCTAssertEqual(context.todayEvents.first?.title, "Design Review")
        XCTAssertEqual(context.todayEvents.first?.location, "Room 2")
        XCTAssertFalse((context.todayEvents.first?.time ?? "").isEmpty)

        XCTAssertEqual(context.upcomingReminders.count, 1)
        XCTAssertEqual(context.upcomingReminders.first?.title, "Submit expenses")
        XCTAssertEqual(context.upcomingReminders.first?.priority, 5)

        XCTAssertEqual(context.recentNotes.count, 1)
        XCTAssertNil(context.emailContext)

        let calls = await (ek.todayEventsCalls, ek.remindersCalls)
        XCTAssertEqual(calls.0, 1)
        XCTAssertEqual(calls.1, 1)
    }
}
