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

    /// Check if it's time for weekly planning (Monday 8:30am)
    func shouldShowWeeklyPlanning() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)

        // Monday is weekday 2 in Calendar
        return components.weekday == 2 && components.hour == 8 && components.minute == 30
    }

    /// Check if user is currently in a meeting
    func isInMeeting(events: [EventKitManager.CalendarEvent]) -> Bool {
        let now = Date()

        for event in events {
            guard !event.isAllDay else { continue }

            if event.startDate <= now && event.endDate > now {
                return true
            }
        }

        return false
    }

    /// Find focus gaps in the calendar (periods of 2+ hours without meetings)
    func findFocusGaps(events: [EventKitManager.CalendarEvent], minimumMinutes: Int = 120) -> [FocusGap] {
        let calendar = Calendar.current
        let now = Date()

        // Work hours: 9am to 6pm
        guard let startOfWorkday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now),
              let endOfWorkday = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) else {
            return []
        }

        // Only consider future events
        let futureEvents = events
            .filter { !$0.isAllDay && $0.endDate > now && $0.startDate < endOfWorkday }
            .sorted { $0.startDate < $1.startDate }

        var gaps: [FocusGap] = []
        var currentTime = max(now, startOfWorkday)

        for event in futureEvents {
            // If there's a gap before this event
            if event.startDate > currentTime {
                let gapMinutes = Int(event.startDate.timeIntervalSince(currentTime) / 60)

                if gapMinutes >= minimumMinutes {
                    gaps.append(FocusGap(
                        startTime: currentTime,
                        endTime: event.startDate,
                        durationMinutes: gapMinutes
                    ))
                }
            }

            // Move current time to after this event
            currentTime = max(currentTime, event.endDate)
        }

        // Check for gap after last event until end of workday
        if currentTime < endOfWorkday {
            let gapMinutes = Int(endOfWorkday.timeIntervalSince(currentTime) / 60)

            if gapMinutes >= minimumMinutes {
                gaps.append(FocusGap(
                    startTime: currentTime,
                    endTime: endOfWorkday,
                    durationMinutes: gapMinutes
                ))
            }
        }

        return gaps
    }

    /// Get overdue reminders count
    func getOverdueCount(reminders: [EventKitManager.Reminder]) -> Int {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        return reminders.filter { reminder in
            guard !reminder.isCompleted,
                  let dueDateString = reminder.dueDate else { return false }

            if let dueDate = dateFormatter.date(from: dueDateString) {
                return dueDate < now
            }
            return false
        }.count
    }

    /// Check if morning briefing should be shown based on preferences
    func shouldShowMorningBriefing(preferredHour: Int, preferredMinute: Int = 0) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date())

        return components.hour == preferredHour && components.minute == preferredMinute
    }

    /// Check if evening briefing should be shown based on preferences
    func shouldShowEveningBriefing(preferredHour: Int, preferredMinute: Int = 0) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date())

        return components.hour == preferredHour && components.minute == preferredMinute
    }

    /// Check if there's a high-priority task that could use a suggested focus block
    func shouldSuggestFocusBlock(
        events: [EventKitManager.CalendarEvent],
        hasHighPriorityTasks: Bool
    ) -> FocusGap? {
        guard hasHighPriorityTasks else { return nil }

        let gaps = findFocusGaps(events: events)
        return gaps.first
    }
}

// MARK: - Supporting Types

struct FocusGap {
    let startTime: Date
    let endTime: Date
    let durationMinutes: Int

    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }

    var formattedDuration: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}
