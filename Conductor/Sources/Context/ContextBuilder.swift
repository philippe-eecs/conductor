import Foundation

/// Holds all context data that will be injected into AI prompts
struct ContextData {
    var todayEvents: [EventSummary] = []
    var upcomingReminders: [ReminderSummary] = []
    var recentNotes: [String] = []
    var planningContext: PlanningContextData?
    var emailContext: EmailContextData?

    var activeThemes: [ThemeSummary] = []

    var calendarReadEnabled: Bool = true
    var remindersReadEnabled: Bool = true
    var emailEnabled: Bool = false
    var calendarAuthorization: EventKitManager.AuthorizationStatus = .notDetermined
    var remindersAuthorization: EventKitManager.AuthorizationStatus = .notDetermined

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

    struct ThemeSummary {
        let name: String
        let color: String
        let taskCount: Int
        let description: String?
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

    /// Builds context based on analyzed context needs with optional filtering
    func buildContext(for needs: ContextNeed) async -> ContextData {
        var context = ContextData()

        context.calendarReadEnabled = (try? database.getPreference(key: "calendar_read_enabled")) != "false"
        context.remindersReadEnabled = (try? database.getPreference(key: "reminders_read_enabled")) != "false"
        context.emailEnabled = (try? database.getPreference(key: "email_integration_enabled")) == "true"
        context.calendarAuthorization = eventKit.calendarAuthorizationStatus()
        context.remindersAuthorization = eventKit.remindersAuthorizationStatus()
        let planningEnabled = (try? database.getPreference(key: "planning_enabled")) != "false"

        for need in needs.types {
            switch need {
            case .calendar(let filter):
                if context.calendarReadEnabled, context.calendarAuthorization == .fullAccess {
                    let events = await eventKit.getTodayEvents()
                    let filteredEvents = filterEvents(events, with: filter)
                    context.todayEvents = filteredEvents.map { event in
                        ContextData.EventSummary(
                            time: event.time,
                            title: event.title,
                            location: event.location,
                            duration: event.duration
                        )
                    }
                }

            case .reminders(let filter):
                if context.remindersReadEnabled, context.remindersAuthorization == .fullAccess {
                    let reminders = await eventKit.getUpcomingReminders(limit: 10)
                    let filteredReminders = filterReminders(reminders, with: filter)
                    context.upcomingReminders = filteredReminders.map { reminder in
                        ContextData.ReminderSummary(
                            title: reminder.title,
                            dueDate: reminder.dueDate,
                            priority: reminder.priority
                        )
                    }
                }

            case .goals:
                guard planningEnabled else { break }
                let events = (context.calendarReadEnabled && context.calendarAuthorization == .fullAccess)
                    ? await eventKit.getTodayEvents()
                    : []
                context.planningContext = buildPlanningContext(events: events)

            case .email(let filter):
                if context.emailEnabled {
                    let emailContext = await buildEmailContext()
                    if let filter = filter {
                        // Filter emails by sender or subject
                        let filteredEmails = emailContext.importantEmails.filter { email in
                            email.sender.localizedCaseInsensitiveContains(filter) ||
                            email.subject.localizedCaseInsensitiveContains(filter)
                        }
                        context.emailContext = ContextData.EmailContextData(
                            unreadCount: emailContext.unreadCount,
                            importantEmails: filteredEmails
                        )
                    } else {
                        context.emailContext = emailContext
                    }
                }

            case .notes:
                if let notes = try? database.loadNotes(limit: 5) {
                    context.recentNotes = notes.map { "\($0.title): \($0.content.prefix(100))..." }
                }

            case .custom:
                // Custom context is handled separately via user input
                break
            }
        }

        return context
    }

    /// Filter events based on a search string
    private func filterEvents(_ events: [EventKitManager.CalendarEvent], with filter: String?) -> [EventKitManager.CalendarEvent] {
        guard let filter = filter, !filter.isEmpty else {
            return events
        }
        return events.filter { event in
            event.title.localizedCaseInsensitiveContains(filter) ||
            (event.location?.localizedCaseInsensitiveContains(filter) ?? false)
        }
    }

    /// Filter reminders based on a search string
    private func filterReminders(_ reminders: [EventKitManager.Reminder], with filter: String?) -> [EventKitManager.Reminder] {
        guard let filter = filter, !filter.isEmpty else {
            return reminders
        }
        return reminders.filter { reminder in
            reminder.title.localizedCaseInsensitiveContains(filter)
        }
    }

    /// Builds the current context from all available sources
    /// Respects user permission settings for each data source
    func buildContext() async -> ContextData {
        var context = ContextData()

        // Check permissions upfront
        context.calendarReadEnabled = (try? database.getPreference(key: "calendar_read_enabled")) != "false"
        context.remindersReadEnabled = (try? database.getPreference(key: "reminders_read_enabled")) != "false"
        context.emailEnabled = (try? database.getPreference(key: "email_integration_enabled")) == "true"
        context.calendarAuthorization = eventKit.calendarAuthorizationStatus()
        context.remindersAuthorization = eventKit.remindersAuthorizationStatus()
        let planningEnabled = (try? database.getPreference(key: "planning_enabled")) != "false"

        let canReadCalendar = context.calendarReadEnabled && context.calendarAuthorization == .fullAccess
        let canReadReminders = context.remindersReadEnabled && context.remindersAuthorization == .fullAccess
        let emailEnabled = context.emailEnabled

        // Fetch calendar, reminders, and email in parallel
        async let eventsTask: [EventKitManager.CalendarEvent] = canReadCalendar
            ? eventKit.getTodayEvents()
            : []
        async let remindersTask: [EventKitManager.Reminder] = canReadReminders
            ? eventKit.getUpcomingReminders(limit: 10)
            : []
        async let emailTask: ContextData.EmailContextData? = emailEnabled
            ? buildEmailContext()
            : nil

        // Await all parallel fetches
        let (events, reminders, emailContext) = await (eventsTask, remindersTask, emailTask)

        // Process calendar events
        if canReadCalendar {
            context.todayEvents = events.map { event in
                ContextData.EventSummary(
                    time: event.time,
                    title: event.title,
                    location: event.location,
                    duration: event.duration
                )
            }
        }

        // Process reminders
        if canReadReminders {
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
        if planningEnabled {
            context.planningContext = buildPlanningContext(events: events)
        }

        // Set email context
        context.emailContext = emailContext

        // Load active themes
        if let themes = try? database.getThemes(), !themes.isEmpty {
            context.activeThemes = themes.compactMap { theme in
                let count = (try? database.getTaskCountForTheme(id: theme.id)) ?? 0
                return ContextData.ThemeSummary(
                    name: theme.name,
                    color: theme.color,
                    taskCount: count,
                    description: theme.themeDescription
                )
            }
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

    /// Builds data for day overview rich response
    func buildDayOverviewData(for date: Date = Date()) async -> DayOverviewData {
        // Fetch calendar events
        let calendarReadEnabled = (try? database.getPreference(key: "calendar_read_enabled")) != "false"
        let calendarAuth = eventKit.calendarAuthorizationStatus()
        let canReadCalendar = calendarReadEnabled && calendarAuth == .fullAccess

        var timeBlocks: [DayOverviewData.TimeBlockData] = []

        if canReadCalendar {
            let events = await eventKit.getTodayEvents()
            for event in events {
                // Parse time string to create start/end dates
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: date)

                // Try to parse event time (format like "9:00 AM")
                if let startDate = parseEventTime(event.time, relativeTo: startOfDay) {
                    // Parse duration (format like "30m" or "1h")
                    let durationMinutes = parseDuration(event.duration)
                    let endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))

                    timeBlocks.append(DayOverviewData.TimeBlockData(
                        id: UUID().uuidString,
                        title: event.title,
                        startTime: startDate,
                        endTime: endDate,
                        colorName: "blue",
                        type: "event"
                    ))
                }
            }
        }

        // Fetch focus blocks
        let focusBlocks = (try? database.getFocusBlocksForDay(date)) ?? []
        for block in focusBlocks {
            if let group = try? database.getFocusGroup(id: block.groupId) {
                timeBlocks.append(DayOverviewData.TimeBlockData(
                    id: block.id,
                    title: group.name,
                    startTime: block.startTime,
                    endTime: block.endTime,
                    colorName: group.color,
                    type: "focusBlock"
                ))
            }
        }

        // Fetch tasks for today
        let tasks = (try? database.getTasksForDay(date, includeCompleted: true, includeOverdue: true)) ?? []
        let taskData = tasks.map { task in
            DayOverviewData.TaskData(
                id: task.id,
                title: task.title,
                isCompleted: task.isCompleted,
                priority: task.priority.label.lowercased(),
                dueTime: task.dueDate
            )
        }

        // Fetch goals for today
        let dateString = DailyPlanningService.todayDateString
        let goals = (try? database.getGoalsForDate(dateString)) ?? []
        let goalData = goals.map { goal in
            DayOverviewData.GoalData(
                id: goal.id,
                text: goal.goalText,
                isCompleted: goal.isCompleted,
                priority: goal.priority
            )
        }

        // Fetch email action count
        let actionEmails = (try? database.getEmailActionNeededCount()) ?? 0

        return DayOverviewData(
            date: date,
            events: timeBlocks,
            tasks: taskData,
            goals: goalData,
            actionEmails: actionEmails
        )
    }

    /// Parse event time string like "9:00 AM" to Date
    private func parseEventTime(_ timeString: String, relativeTo date: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        if let time = formatter.date(from: timeString) {
            let calendar = Calendar.current
            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
            return calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: date)
        }

        // Try 24-hour format
        formatter.dateFormat = "HH:mm"
        if let time = formatter.date(from: timeString) {
            let calendar = Calendar.current
            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
            return calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: date)
        }

        return nil
    }

    /// Parse duration string like "30m", "1h", "1h 30m" to minutes
    private func parseDuration(_ durationString: String) -> Int {
        var totalMinutes = 0

        // Check for hours
        if let hourMatch = durationString.range(of: #"(\d+)\s*h"#, options: .regularExpression) {
            let hourStr = durationString[hourMatch].replacingOccurrences(of: "h", with: "").trimmingCharacters(in: .whitespaces)
            if let hours = Int(hourStr) {
                totalMinutes += hours * 60
            }
        }

        // Check for minutes
        if let minMatch = durationString.range(of: #"(\d+)\s*m"#, options: .regularExpression) {
            let minStr = durationString[minMatch].replacingOccurrences(of: "m", with: "").trimmingCharacters(in: .whitespaces)
            if let mins = Int(minStr) {
                totalMinutes += mins
            }
        }

        return totalMinutes > 0 ? totalMinutes : 30 // Default 30 min
    }
}
