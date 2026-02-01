import Foundation

/// Runs local rules without AI to detect notable conditions
final class LocalRuleEngine {
    static let shared = LocalRuleEngine()

    private init() {}

    /// Check for alerts based on current events and state
    func checkForAlerts(events: [EventKitManager.CalendarEvent]) -> [ProactiveAlert] {
        var alerts: [ProactiveAlert] = []

        let now = Date()

        for event in events {
            // Skip all-day events for time-based alerts
            guard !event.isAllDay else { continue }

            // Check for upcoming meetings
            let minutesUntil = event.startDate.timeIntervalSince(now) / 60

            // 15-minute warning
            if minutesUntil > 14 && minutesUntil <= 15 {
                alerts.append(ProactiveAlert(
                    title: "Meeting in 15 minutes",
                    body: event.title + (event.location.map { " at \($0)" } ?? ""),
                    category: .meeting,
                    priority: .medium
                ))
            }

            // 5-minute warning
            if minutesUntil > 4 && minutesUntil <= 5 {
                alerts.append(ProactiveAlert(
                    title: "Meeting in 5 minutes",
                    body: event.title + (event.location.map { " at \($0)" } ?? ""),
                    category: .meeting,
                    priority: .high
                ))
            }

            // Meeting starting now
            if minutesUntil > -1 && minutesUntil <= 0 {
                alerts.append(ProactiveAlert(
                    title: "Meeting starting now",
                    body: event.title + (event.location.map { " at \($0)" } ?? ""),
                    category: .meeting,
                    priority: .high
                ))
            }
        }

        // Check for conflicting events
        let conflicts = findConflicts(events: events)
        for conflict in conflicts {
            alerts.append(ProactiveAlert(
                title: "Calendar conflict",
                body: "\(conflict.0.title) overlaps with \(conflict.1.title)",
                category: .meeting,
                priority: .medium
            ))
        }

        return alerts
    }

    /// Find overlapping events
    private func findConflicts(
        events: [EventKitManager.CalendarEvent]
    ) -> [(EventKitManager.CalendarEvent, EventKitManager.CalendarEvent)] {
        var conflicts: [(EventKitManager.CalendarEvent, EventKitManager.CalendarEvent)] = []

        let sortedEvents = events.filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }

        for i in 0..<sortedEvents.count {
            for j in (i+1)..<sortedEvents.count {
                let event1 = sortedEvents[i]
                let event2 = sortedEvents[j]

                // Check if event2 starts before event1 ends
                if event2.startDate < event1.endDate {
                    conflicts.append((event1, event2))
                }
            }
        }

        return conflicts
    }

    /// Check if current time is within quiet hours
    func isQuietHours() -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        // Quiet hours: 10pm to 7am
        return hour >= 22 || hour < 7
    }

    /// Check if it's time for morning briefing (8am)
    func shouldShowMorningBriefing() -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date())

        return components.hour == 8 && components.minute == 0
    }

    /// Check if it's time for evening briefing (6pm)
    func shouldShowEveningBriefing() -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date())

        return components.hour == 18 && components.minute == 0
    }
}
