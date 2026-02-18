import Foundation

struct SlotCandidate: Codable, Equatable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let score: Double
    let reason: String
    let conflicts: [String]

    init(
        id: String = UUID().uuidString,
        start: Date,
        end: Date,
        score: Double,
        reason: String,
        conflicts: [String] = []
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.score = score
        self.reason = reason
        self.conflicts = conflicts
    }
}

@MainActor
final class SlotSuggestionService {
    static let shared = SlotSuggestionService()

    private init() {}

    func suggestSlots(
        for date: Date = Date(),
        durationMinutes: Int = 30,
        maxCount: Int = 5,
        themeId: String? = nil
    ) async -> [SlotCandidate] {
        let calendar = Calendar.current
        let roundedNow = TemporalContext.roundedMinimumStart(from: Date())
        let isToday = calendar.isDateInToday(date)

        var startCursor: Date
        if isToday {
            startCursor = roundedNow
        } else {
            startCursor = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }

        if let themeId,
           let theme = (try? Database.shared.getTheme(id: themeId)) ?? nil,
           let preferred = parsePreferredTime(theme.defaultStartTime, on: date) {
            startCursor = max(startCursor, preferred)
        }

        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(22 * 3600)
        guard startCursor < dayEnd else { return [] }

        let dayEvents = await EventKitManager.shared.getEventsForDay(date)
        let dayBlocks = (try? Database.shared.getThemeBlocksForDay(date)) ?? []

        let busyIntervals: [(start: Date, end: Date, reason: String)] =
            dayEvents.map { ($0.startDate, $0.endDate, "Calendar: \($0.title)") } +
            dayBlocks.map { ($0.startTime, $0.endTime, "Theme block") }

        let step = TimeInterval(15 * 60)
        let duration = TimeInterval(max(15, durationMinutes) * 60)
        var candidates: [SlotCandidate] = []

        var cursor = startCursor
        while cursor.addingTimeInterval(duration) <= dayEnd {
            let end = cursor.addingTimeInterval(duration)
            let conflicts = busyIntervals.filter { interval in
                interval.start < end && interval.end > cursor
            }

            if conflicts.isEmpty {
                let distanceFromNow = max(0, cursor.timeIntervalSince(Date()))
                let score = max(0, 1.0 - (distanceFromNow / (12 * 3600)))
                let reason = candidateReason(start: cursor, dayEvents: dayEvents)
                candidates.append(
                    SlotCandidate(
                        start: cursor,
                        end: end,
                        score: score,
                        reason: reason,
                        conflicts: []
                    )
                )
            }

            if candidates.count >= maxCount * 3 {
                break
            }

            cursor = cursor.addingTimeInterval(step)
        }

        return Array(candidates
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score > rhs.score
                }
                return lhs.start < rhs.start
            }
            .prefix(maxCount))
    }

    private func parsePreferredTime(_ hhmm: String?, on date: Date) -> Date? {
        guard let hhmm else { return nil }
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    private func candidateReason(start: Date, dayEvents: [EventKitManager.CalendarEvent]) -> String {
        guard let previous = dayEvents
            .filter({ $0.endDate <= start })
            .sorted(by: { $0.endDate > $1.endDate })
            .first else {
            return "Open window"
        }
        return "After \(previous.title)"
    }
}
