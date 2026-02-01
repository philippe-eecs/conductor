import Foundation

/// Holds all context data that will be injected into AI prompts
struct ContextData {
    var todayEvents: [EventSummary] = []
    var upcomingReminders: [ReminderSummary] = []
    var recentNotes: [String] = []

    struct EventSummary {
        let time: String
        let title: String
        let location: String?
        let duration: String
    }

    struct ReminderSummary {
        let title: String
        let dueDate: String?
        let priority: Int
    }
}

final class ContextBuilder {
    static let shared = ContextBuilder()

    private let eventKitManager = EventKitManager.shared

    private init() {}

    /// Builds the current context from all available sources
    func buildContext() async -> ContextData {
        var context = ContextData()

        // Fetch calendar events
        let events = await eventKitManager.getTodayEvents()
        context.todayEvents = events.map { event in
            ContextData.EventSummary(
                time: event.time,
                title: event.title,
                location: event.location,
                duration: event.duration
            )
        }

        // Fetch reminders
        let reminders = await eventKitManager.getUpcomingReminders(limit: 10)
        context.upcomingReminders = reminders.map { reminder in
            ContextData.ReminderSummary(
                title: reminder.title,
                dueDate: reminder.dueDate,
                priority: reminder.priority
            )
        }

        // Load recent notes from database
        if let notes = try? Database.shared.loadNotes(limit: 5) {
            context.recentNotes = notes.map { "\($0.title): \($0.content.prefix(100))..." }
        }

        return context
    }

    /// Builds a quick summary of current context for proactive checks
    func buildQuickSummary() async -> String {
        let context = await buildContext()

        var summary = ""

        if !context.todayEvents.isEmpty {
            summary += "Today: \(context.todayEvents.count) events. "
        }

        if !context.upcomingReminders.isEmpty {
            summary += "Reminders: \(context.upcomingReminders.count) pending. "
        }

        return summary.isEmpty ? "No upcoming events or reminders." : summary
    }
}
