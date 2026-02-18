import Foundation

struct TemporalContext {
    let now: Date
    let timezoneId: String
    let timezoneAbbrev: String
    let minimumSchedulableStart: Date

    var nowLocalISO: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: now)
    }

    var minimumSchedulableStartISO: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: minimumSchedulableStart)
    }

    static func current(now: Date = Date()) -> TemporalContext {
        TemporalContext(
            now: now,
            timezoneId: TimeZone.current.identifier,
            timezoneAbbrev: TimeZone.current.abbreviation() ?? "Local",
            minimumSchedulableStart: roundedMinimumStart(from: now)
        )
    }

    static func roundedMinimumStart(
        from now: Date = Date(),
        bufferMinutes: Int = 15,
        roundingMinutes: Int = 5
    ) -> Date {
        let base = now.addingTimeInterval(TimeInterval(max(0, bufferMinutes) * 60))
        let interval = max(1, roundingMinutes) * 60
        let rounded = ceil(base.timeIntervalSince1970 / Double(interval)) * Double(interval)
        return Date(timeIntervalSince1970: rounded)
    }

    func runtimePreamble() -> String {
        let localDate = SharedDateFormatters.fullDate.string(from: now)
        let localTime = SharedDateFormatters.time12Hour.string(from: now)
        let earliest = SharedDateFormatters.time12Hour.string(from: minimumSchedulableStart)
        return """
        Runtime temporal context (authoritative):
        - Local date: \(localDate)
        - Local time: \(localTime)
        - Timezone: \(timezoneId) (\(timezoneAbbrev))
        - Earliest valid scheduling start: \(earliest) (\(minimumSchedulableStartISO))

        Scheduling guardrails:
        - Never propose times in the past.
        - Never propose times earlier than the earliest valid scheduling start for same-day planning.
        """
    }
}
