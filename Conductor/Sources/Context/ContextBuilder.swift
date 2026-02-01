import Foundation

/// Holds all context data that will be injected into AI prompts
struct ContextData {
    var todayEvents: [EventSummary] = []
    var upcomingReminders: [ReminderSummary] = []
    var recentNotes: [String] = []
    var planningContext: PlanningContextData?
    var emailContext: EmailContextData?

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

    struct PlanningContextData {
        let todaysGoals: [GoalSummary]
        let completionRate: Double
        let overdueCount: Int
        let focusGaps: [FocusGapSummary]

        struct GoalSummary {
            let text: String
            let priority: Int
            let isCompleted: Bool
        }

        struct FocusGapSummary {
            let timeRange: String
            let duration: String
        }
    }

    struct EmailContextData {
        let unreadCount: Int
        let importantEmails: [EmailSummary]

        struct EmailSummary {
            let sender: String
            let subject: String
            let isRead: Bool
        }
    }
}

final class ContextBuilder {
    static let shared = ContextBuilder()

    private let eventKit: EventKitProviding
    private let mailService: MailService
    private let database: Database

    init(
        eventKit: EventKitProviding = EventKitManager.shared,
        mailService: MailService = .shared,
        database: Database = .shared
    ) {
        self.eventKit = eventKit
        self.mailService = mailService
        self.database = database
    }

    /// Builds the current context from all available sources
    /// Respects user permission settings for each data source
    func buildContext() async -> ContextData {
        var context = ContextData()

        // Check calendar read permission
        let calendarReadEnabled = (try? database.getPreference(key: "calendar_read_enabled")) != "false"

        // Fetch calendar events if permitted
        var events: [EventKitManager.CalendarEvent] = []
        if calendarReadEnabled {
            events = await eventKit.getTodayEvents()
            context.todayEvents = events.map { event in
                ContextData.EventSummary(
                    time: event.time,
                    title: event.title,
                    location: event.location,
                    duration: event.duration
                )
            }
        }

        // Check reminders read permission
        let remindersReadEnabled = (try? database.getPreference(key: "reminders_read_enabled")) != "false"

        // Fetch reminders if permitted
        if remindersReadEnabled {
            let reminders = await eventKit.getUpcomingReminders(limit: 10)
            context.upcomingReminders = reminders.map { reminder in
                ContextData.ReminderSummary(
                    title: reminder.title,
                    dueDate: reminder.dueDate,
                    priority: reminder.priority
                )
            }
        }

        // Load recent notes from database
        if let notes = try? database.loadNotes(limit: 5) {
            context.recentNotes = notes.map { "\($0.title): \($0.content.prefix(100))..." }
        }

        // Build planning context (uses calendar data already fetched)
        if calendarReadEnabled {
            context.planningContext = buildPlanningContext(events: events)
        }

        // Build email context (if Mail.app integration is enabled)
        let emailEnabled = (try? database.getPreference(key: "email_integration_enabled")) == "true"
        if emailEnabled {
            context.emailContext = await buildEmailContext()
        }

        return context
    }

    /// Builds email-specific context
    private func buildEmailContext() async -> ContextData.EmailContextData {
        let emailContext = await mailService.buildEmailContext()

        let emailSummaries = emailContext.importantEmails.prefix(5).map { email in
            ContextData.EmailContextData.EmailSummary(
                sender: email.sender,
                subject: email.subject,
                isRead: email.isRead
            )
        }

        return ContextData.EmailContextData(
            unreadCount: emailContext.unreadCount,
            importantEmails: Array(emailSummaries)
        )
    }

    /// Builds planning-specific context
    private func buildPlanningContext(events: [EventKitManager.CalendarEvent]) -> ContextData.PlanningContextData {
        let today = DailyPlanningService.todayDateString

        // Get today's goals
        let goals = (try? database.getGoalsForDate(today)) ?? []
        let goalSummaries = goals.map { goal in
            ContextData.PlanningContextData.GoalSummary(
                text: goal.goalText,
                priority: goal.priority,
                isCompleted: goal.isCompleted
            )
        }

        // Get completion rate
        let completionRate = (try? database.getGoalCompletionRate(forDays: 7)) ?? 0

        // Get overdue count
        let overdueGoals = (try? database.getIncompleteGoals(before: today)) ?? []

        // Get focus gaps
        let focusGaps = LocalRuleEngine.shared.findFocusGaps(events: events)
        let focusGapSummaries = focusGaps.map { gap in
            ContextData.PlanningContextData.FocusGapSummary(
                timeRange: gap.formattedTimeRange,
                duration: gap.formattedDuration
            )
        }

        return ContextData.PlanningContextData(
            todaysGoals: goalSummaries,
            completionRate: completionRate,
            overdueCount: overdueGoals.count,
            focusGaps: focusGapSummaries
        )
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

        if let emailContext = context.emailContext, emailContext.unreadCount > 0 {
            summary += "Email: \(emailContext.unreadCount) unread. "
        }

        return summary.isEmpty ? "No upcoming events or reminders." : summary
    }
}
