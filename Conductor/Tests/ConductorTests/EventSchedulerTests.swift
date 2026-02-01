import XCTest
@testable import Conductor

final class EventSchedulerTests: XCTestCase {
    private struct StubPreferences: PreferenceReading {
        var values: [String: String] = [:]
        func preferenceValue(for key: String) -> String? { values[key] }
    }

    func test_scheduledJob_nextRunDate_usesDefaultTimeWhenNoPreferences() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let job = ScheduledJob(
            id: "midmorning_checkin",
            name: "Mid-morning Check-in",
            schedule: .daily(hour: 10, minute: 30),
            preferenceHourKey: "midmorning_checkin_hour",
            preferenceMinuteKey: "midmorning_checkin_minute",
            action: {}
        )

        let now = Date(timeIntervalSince1970: 1_767_000_000) // deterministic "now"
        let next = job.nextRunDate(after: now, calendar: calendar, preferences: StubPreferences())
        XCTAssertNotNil(next)

        let components = calendar.dateComponents([.hour, .minute], from: next!)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 30)
    }

    func test_scheduledJob_nextRunDate_usesHourAndMinutePreferences() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let job = ScheduledJob(
            id: "midmorning_checkin",
            name: "Mid-morning Check-in",
            schedule: .daily(hour: 10, minute: 30),
            preferenceHourKey: "midmorning_checkin_hour",
            preferenceMinuteKey: "midmorning_checkin_minute",
            action: {}
        )

        let prefs = StubPreferences(values: [
            "midmorning_checkin_hour": "11",
            "midmorning_checkin_minute": "45",
        ])

        let now = Date(timeIntervalSince1970: 1_767_000_000)
        let next = job.nextRunDate(after: now, calendar: calendar, preferences: prefs)
        XCTAssertNotNil(next)

        let components = calendar.dateComponents([.hour, .minute], from: next!)
        XCTAssertEqual(components.hour, 11)
        XCTAssertEqual(components.minute, 45)
    }

    func test_scheduledJob_nextRunDate_rollsToTomorrowWhenTimeAlreadyPassed() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let prefs = StubPreferences(values: [
            "midmorning_checkin_hour": "11",
            "midmorning_checkin_minute": "45",
        ])

        let job = ScheduledJob(
            id: "midmorning_checkin",
            name: "Mid-morning Check-in",
            schedule: .daily(hour: 10, minute: 30),
            preferenceHourKey: "midmorning_checkin_hour",
            preferenceMinuteKey: "midmorning_checkin_minute",
            action: {}
        )

        let nowComponents = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 2,
            day: 1,
            hour: 12,
            minute: 0,
            second: 0
        )
        let now = calendar.date(from: nowComponents)!

        let next = job.nextRunDate(after: now, calendar: calendar, preferences: prefs)
        XCTAssertNotNil(next)

        let nextComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next!)
        XCTAssertEqual(nextComponents.year, 2026)
        XCTAssertEqual(nextComponents.month, 2)
        XCTAssertEqual(nextComponents.day, 2)
        XCTAssertEqual(nextComponents.hour, 11)
        XCTAssertEqual(nextComponents.minute, 45)
    }
}

