import Foundation
import EventKit

/// Event-driven scheduler that reacts to system events and schedules jobs
/// at specific times rather than polling.
final class EventScheduler {
    static let shared = EventScheduler()

    private let eventStore = EKEventStore()
    private var nextEventTimer: DispatchSourceTimer?
    private var scheduledJobs: [ScheduledJob] = []
    private let queue = DispatchQueue(label: "com.conductor.scheduler", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()

    // Track what we've already triggered today to avoid duplicates
    private var triggeredJobsToday: Set<String> = []
    private var lastResetDate: String = ""

    // Public state for UI visibility
    private(set) var nextScheduledEvent: SchedulerState.NextEvent?
    private(set) var todaysJobs: [SchedulerState.JobStatus] = []

    private init() {
        queue.setSpecific(key: queueKey, value: 1)
    }

    private func perform<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return body()
        }
        return queue.sync {
            body()
        }
    }

    // MARK: - Public State

    /// Returns current scheduler state for UI display
    func getSchedulerState() -> SchedulerState {
        var state = SchedulerState()
        state.nextEvent = nextScheduledEvent

        // Build today's job statuses
        let now = Date()
        state.todaysJobs = scheduledJobs.compactMap { job -> SchedulerState.JobStatus? in
            guard case .daily = job.schedule else { return nil }

            let completed = triggeredJobsToday.contains(job.id)
            let nextRun = job.nextRunDate(after: now)

            return SchedulerState.JobStatus(
                id: job.id,
                name: job.name,
                scheduledTime: nextRun,
                isCompleted: completed
            )
        }

        // Build upcoming jobs (non-daily)
        state.upcomingJobs = scheduledJobs.compactMap { job -> SchedulerState.JobStatus? in
            switch job.schedule {
            case .daily:
                return nil // Already in todaysJobs
            case .weekly, .monthly:
                guard let nextRun = job.nextRunDate(after: now) else { return nil }
                return SchedulerState.JobStatus(
                    id: job.id,
                    name: job.name,
                    scheduledTime: nextRun,
                    isCompleted: false
                )
            }
        }.sorted { ($0.scheduledTime ?? .distantFuture) < ($1.scheduledTime ?? .distantFuture) }

        return state
    }

    /// Returns upcoming meeting warnings for today
    func getTodayMeetingWarnings() -> [SchedulerState.MeetingWarning] {
        perform {
            let calendar = Calendar.current
            let now = Date()
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)!

            let predicate = eventStore.predicateForEvents(
                withStart: now,
                end: endOfDay,
                calendars: nil
            )
            let events = eventStore.events(matching: predicate)

            var warnings: [SchedulerState.MeetingWarning] = []

            for event in events {
                guard !event.isAllDay else { continue }

                let warn15 = event.startDate.addingTimeInterval(-15 * 60)
                if warn15 > now {
                    let timeUntil = warn15.timeIntervalSince(now)
                    warnings.append(SchedulerState.MeetingWarning(
                        eventTitle: event.title,
                        eventStart: event.startDate,
                        warningTime: warn15,
                        minutesBefore: 15,
                        minutesUntilWarning: Int(timeUntil / 60)
                    ))
                }
            }

            return warnings.sorted { $0.warningTime < $1.warningTime }
        }
    }

    // MARK: - Lifecycle

    func start() {
        // Subscribe to calendar changes
        subscribeToCalendarChanges()

        // Subscribe to reminders changes
        subscribeToReminderChanges()

        // Set up daily/weekly jobs
        setupScheduledJobs()

        // Calculate and schedule next event
        recalculateNextEvent()

        print("EventScheduler started (event-driven mode)")

        // Log to activity on main thread
        Task { @MainActor in
            AppState.shared.logActivity(.scheduler, "Event scheduler started")
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        nextEventTimer?.cancel()
        nextEventTimer = nil
        print("EventScheduler stopped")
    }

    // MARK: - Event Subscriptions

    private func subscribeToCalendarChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarDidChange),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }

    private func subscribeToReminderChanges() {
        // EKEventStore.changed covers reminders too
        // Already subscribed above
    }

    @objc private func calendarDidChange(_ notification: Notification) {
        print("Calendar/Reminders changed - recalculating schedule")
        recalculateNextEvent()
    }

    // MARK: - Scheduled Jobs

    private func setupScheduledJobs() {
        scheduledJobs = [
            // Morning Brief - default 8:00 AM
            ScheduledJob(
                id: "morning_brief",
                name: "Morning Brief",
                schedule: .daily(hour: 8, minute: 0),
                preferenceHourKey: "morning_brief_hour",
                action: { await self.triggerMorningBrief() }
            ),

            // Mid-morning Check-in - 10:30 AM
            ScheduledJob(
                id: "midmorning_checkin",
                name: "Mid-morning Check-in",
                schedule: .daily(hour: 10, minute: 30),
                preferenceHourKey: "midmorning_checkin_hour",
                preferenceMinuteKey: "midmorning_checkin_minute",
                action: { await self.triggerMidMorningCheckin() }
            ),

            // Afternoon Check-in - 1:30 PM
            ScheduledJob(
                id: "afternoon_checkin",
                name: "Afternoon Check-in",
                schedule: .daily(hour: 13, minute: 30),
                preferenceHourKey: "afternoon_checkin_hour",
                preferenceMinuteKey: "afternoon_checkin_minute",
                action: { await self.triggerAfternoonCheckin() }
            ),

            // Wind-down Check-in - 4:30 PM
            ScheduledJob(
                id: "winddown_checkin",
                name: "Wind-down Check-in",
                schedule: .daily(hour: 16, minute: 30),
                preferenceHourKey: "winddown_checkin_hour",
                preferenceMinuteKey: "winddown_checkin_minute",
                action: { await self.triggerWinddownCheckin() }
            ),

            // Evening Shutdown - default 6:00 PM
            ScheduledJob(
                id: "evening_shutdown",
                name: "Evening Shutdown",
                schedule: .daily(hour: 18, minute: 0),
                preferenceHourKey: "evening_brief_hour",
                action: { await self.triggerEveningShutdown() }
            ),

            // Weekly Review - Monday 8:30 AM
            ScheduledJob(
                id: "weekly_review",
                name: "Weekly Review",
                schedule: .weekly(weekday: 2, hour: 8, minute: 30), // Monday
                action: { await self.triggerWeeklyReview() }
            ),

            // Monthly Review - 1st of month, 9:00 AM
            ScheduledJob(
                id: "monthly_review",
                name: "Monthly Review",
                schedule: .monthly(day: 1, hour: 9, minute: 0),
                action: { await self.triggerMonthlyReview() }
            )
        ]
    }

    // MARK: - Smart Scheduling

    func recalculateNextEvent() {
        queue.async { [weak self] in
            self?.doRecalculate()
        }
    }

    private func doRecalculate() {
        // Reset triggered jobs if it's a new day
        let today = DailyPlanningService.todayDateString
        if lastResetDate != today {
            triggeredJobsToday.removeAll()
            lastResetDate = today
        }

        var upcomingEvents: [(date: Date, event: ScheduledEvent)] = []
        let now = Date()

        // 1. Add meeting warnings from calendar
        if let meetingEvents = getMeetingWarnings() {
            upcomingEvents.append(contentsOf: meetingEvents)
        }

        // 2. Add scheduled jobs
        for job in scheduledJobs {
            // Skip if already triggered today (for daily jobs)
            if triggeredJobsToday.contains(job.id) {
                continue
            }

            if let nextRun = job.nextRunDate(after: now) {
                upcomingEvents.append((nextRun, .job(job)))
            }
        }

        // Sort by date and get the next one
        upcomingEvents.sort { $0.date < $1.date }

        guard let next = upcomingEvents.first else {
            print("No upcoming events scheduled")
            return
        }

        scheduleTimer(for: next.date, event: next.event)
    }

    private func getMeetingWarnings() -> [(date: Date, event: ScheduledEvent)]? {
        let calendar = Calendar.current
        let now = Date()
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)!

        // Get today's events
        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endOfDay,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate)

        var warnings: [(date: Date, event: ScheduledEvent)] = []

        for event in events {
            guard !event.isAllDay else { continue }

            // 15-minute warning
            let warn15 = event.startDate.addingTimeInterval(-15 * 60)
            if warn15 > now {
                warnings.append((warn15, .meetingWarning(event, minutes: 15)))
            }

            // 5-minute warning
            let warn5 = event.startDate.addingTimeInterval(-5 * 60)
            if warn5 > now {
                warnings.append((warn5, .meetingWarning(event, minutes: 5)))
            }

            // Starting now
            if event.startDate > now {
                warnings.append((event.startDate, .meetingWarning(event, minutes: 0)))
            }
        }

        return warnings.isEmpty ? nil : warnings
    }

    private func scheduleTimer(for date: Date, event: ScheduledEvent) {
        // Cancel existing timer
        nextEventTimer?.cancel()

        let delay = max(0, date.timeIntervalSince(Date()))

        print("Scheduling \(event.description) for \(formatDate(date)) (in \(Int(delay))s)")

        // Update public state
        switch event {
        case .meetingWarning(let ekEvent, let minutes):
            nextScheduledEvent = SchedulerState.NextEvent(
                description: "\(ekEvent.title ?? "Meeting") in \(minutes) min",
                time: date,
                category: .meetingWarning
            )
        case .job(let job):
            nextScheduledEvent = SchedulerState.NextEvent(
                description: job.name,
                time: date,
                category: .scheduledJob
            )
        }

        nextEventTimer = DispatchSource.makeTimerSource(queue: queue)
        nextEventTimer?.schedule(deadline: .now() + delay)
        nextEventTimer?.setEventHandler { [weak self] in
            self?.handleScheduledEvent(event)
        }
        nextEventTimer?.resume()
    }

    private func handleScheduledEvent(_ event: ScheduledEvent) {
        Task {
            switch event {
            case .meetingWarning(let ekEvent, let minutes):
                await handleMeetingWarning(ekEvent, minutes: minutes)

            case .job(let job):
                // Mark as triggered to avoid duplicates
                triggeredJobsToday.insert(job.id)

                // Log to activity
                await MainActor.run {
                    AppState.shared.logActivity(.scheduler, "Running: \(job.name)")
                }

                await job.action()
            }

            // Recalculate next event
            recalculateNextEvent()
        }
    }

    // MARK: - Event Handlers

    private func handleMeetingWarning(_ event: EKEvent, minutes: Int) async {
        // Check quiet hours
        guard !LocalRuleEngine.shared.isQuietHours() else { return }

        let title: String
        switch minutes {
        case 15:
            title = "Meeting in 15 minutes"
        case 5:
            title = "Meeting in 5 minutes"
        default:
            title = "Meeting starting now"
        }

        let eventTitle = event.title ?? "Untitled"

        // Log to activity
        await MainActor.run {
            AppState.shared.logActivity(.scheduler, "\(title): \(eventTitle)")
        }

        let alert = ProactiveAlert(
            title: title,
            body: eventTitle + (event.location.map { " at \($0)" } ?? ""),
            category: .meeting,
            priority: minutes <= 5 ? .high : .medium
        )

        if FatigueManager.shared.shouldShow(alert: alert) {
            await ProactiveEngine.shared.sendNotificationPublic(alert)
            FatigueManager.shared.recordShown(alert: alert)
        }
    }

    private func triggerMorningBrief() async {
        // Check if planning is enabled
        guard (try? Database.shared.getPreference(key: "planning_enabled")) != "false" else { return }
        guard !LocalRuleEngine.shared.isQuietHours() else { return }

        let alert = ProactiveAlert(
            title: "Good morning!",
            body: "Your daily brief is ready. Tap to review your plan.",
            category: .briefing,
            priority: .medium
        )

        if FatigueManager.shared.shouldShow(alert: alert) {
            await ProactiveEngine.shared.sendNotificationPublic(alert)
            FatigueManager.shared.recordShown(alert: alert)
        }
    }

    private func triggerEveningShutdown() async {
        guard (try? Database.shared.getPreference(key: "planning_enabled")) != "false" else { return }
        guard !LocalRuleEngine.shared.isQuietHours() else { return }

        // Check if user is in a meeting
        let events = await EventKitManager.shared.getTodayEvents()
        guard !LocalRuleEngine.shared.isInMeeting(events: events) else {
            // Reschedule for 30 minutes later
            print("User in meeting, deferring evening shutdown")
            return
        }

        let alert = ProactiveAlert(
            title: "Time for daily shutdown",
            body: "Review your progress and plan for tomorrow.",
            category: .briefing,
            priority: .medium
        )

        if FatigueManager.shared.shouldShow(alert: alert) {
            await ProactiveEngine.shared.sendNotificationPublic(alert)
            FatigueManager.shared.recordShown(alert: alert)
        }
    }

    private func triggerWeeklyReview() async {
        guard (try? Database.shared.getPreference(key: "planning_enabled")) != "false" else { return }

        let alert = ProactiveAlert(
            title: "Weekly planning time",
            body: "Start your week with intention. Review your goals.",
            category: .briefing,
            priority: .medium
        )

        if FatigueManager.shared.shouldShow(alert: alert) {
            await ProactiveEngine.shared.sendNotificationPublic(alert)
            FatigueManager.shared.recordShown(alert: alert)
        }
    }

    private func triggerMonthlyReview() async {
        guard (try? Database.shared.getPreference(key: "planning_enabled")) != "false" else { return }

        let alert = ProactiveAlert(
            title: "Monthly review",
            body: "Reflect on last month's progress and set goals for the new month.",
            category: .briefing,
            priority: .medium
        )

        if FatigueManager.shared.shouldShow(alert: alert) {
            await ProactiveEngine.shared.sendNotificationPublic(alert)
            FatigueManager.shared.recordShown(alert: alert)
        }
    }

    // MARK: - Check-in Prompts

    private func triggerMidMorningCheckin() async {
        guard (try? Database.shared.getPreference(key: "checkins_enabled")) != "false" else { return }
        guard !LocalRuleEngine.shared.isQuietHours() else { return }

        // Check if user is in a meeting
        let events = await EventKitManager.shared.getTodayEvents()
        guard !LocalRuleEngine.shared.isInMeeting(events: events) else { return }

        // Get top goal for context
        let today = DailyPlanningService.todayDateString
        let goals = (try? Database.shared.getGoalsForDate(today)) ?? []
        let topGoal = goals.first { !$0.isCompleted }

        let body: String
        if let goal = topGoal {
            body = "Quick check-in: How's \"\(goal.goalText)\" going?"
        } else {
            body = "Quick check-in: How's your morning going so far?"
        }

        let alert = ProactiveAlert(
            title: "Mid-morning check",
            body: body,
            category: .suggestion,
            priority: .low
        )

        if FatigueManager.shared.shouldShow(alert: alert) {
            await NotificationManager.shared.sendActionableNotification(alert)
            FatigueManager.shared.recordShown(alert: alert)
        }
    }

    private func triggerAfternoonCheckin() async {
        guard (try? Database.shared.getPreference(key: "checkins_enabled")) != "false" else { return }
        guard !LocalRuleEngine.shared.isQuietHours() else { return }

        let events = await EventKitManager.shared.getTodayEvents()
        guard !LocalRuleEngine.shared.isInMeeting(events: events) else { return }

        // Get pending tasks count
        let today = DailyPlanningService.todayDateString
        let goals = (try? Database.shared.getGoalsForDate(today)) ?? []
        let pendingCount = goals.filter { !$0.isCompleted }.count

        let body: String
        if pendingCount > 0 {
            body = "Afternoon check: \(pendingCount) item\(pendingCount == 1 ? "" : "s") still pending. Focus on any?"
        } else {
            body = "Afternoon check: Great progress! Any new priorities?"
        }

        let alert = ProactiveAlert(
            title: "Afternoon check",
            body: body,
            category: .suggestion,
            priority: .low
        )

        if FatigueManager.shared.shouldShow(alert: alert) {
            await NotificationManager.shared.sendActionableNotification(alert)
            FatigueManager.shared.recordShown(alert: alert)
        }
    }

    private func triggerWinddownCheckin() async {
        guard (try? Database.shared.getPreference(key: "checkins_enabled")) != "false" else { return }
        guard !LocalRuleEngine.shared.isQuietHours() else { return }

        let events = await EventKitManager.shared.getTodayEvents()
        guard !LocalRuleEngine.shared.isInMeeting(events: events) else { return }

        // Get today's progress
        let today = DailyPlanningService.todayDateString
        let goals = (try? Database.shared.getGoalsForDate(today)) ?? []
        let completedCount = goals.filter { $0.isCompleted }.count
        let totalCount = goals.count

        let body: String
        if totalCount > 0 {
            if completedCount == totalCount {
                body = "Day's winding down. All \(totalCount) goals complete! Ready to wrap up?"
            } else {
                body = "Day's winding down. \(completedCount)/\(totalCount) complete. Want to review progress?"
            }
        } else {
            body = "Day's winding down. Want to review your progress?"
        }

        let alert = ProactiveAlert(
            title: "Wind-down time",
            body: body,
            category: .suggestion,
            priority: .low
        )

        if FatigueManager.shared.shouldShow(alert: alert) {
            await NotificationManager.shared.sendActionableNotification(alert)
            FatigueManager.shared.recordShown(alert: alert)
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        SharedDateFormatters.time12Hour.string(from: date)
    }
}

// MARK: - Supporting Types

enum ScheduledEvent {
    case meetingWarning(EKEvent, minutes: Int)
    case job(ScheduledJob)

    var description: String {
        switch self {
        case .meetingWarning(let event, let minutes):
            return "Meeting warning (\(minutes)m): \(event.title ?? "Untitled")"
        case .job(let job):
            return "Job: \(job.name)"
        }
    }
}

struct ScheduledJob {
    let id: String
    let name: String
    let schedule: JobSchedule
    var preferenceHourKey: String?
    var preferenceMinuteKey: String?
    let action: () async -> Void

    func nextRunDate(after date: Date, calendar: Calendar = .current, preferences: PreferenceReading = Database.shared) -> Date? {

        switch schedule {
        case .daily(let hour, let minute):
            let actualHour: Int = preferenceHourKey
                .flatMap { preferences.preferenceValue(for: $0) }
                .flatMap(Int.init) ?? hour

            let actualMinute: Int = preferenceMinuteKey
                .flatMap { preferences.preferenceValue(for: $0) }
                .flatMap(Int.init) ?? minute

            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = actualHour
            components.minute = actualMinute
            components.second = 0

            guard let todayRun = calendar.date(from: components) else { return nil }

            if todayRun > date {
                return todayRun
            } else {
                // Tomorrow
                return calendar.date(byAdding: .day, value: 1, to: todayRun)
            }

        case .weekly(let weekday, let hour, let minute):
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute

            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)

        case .monthly(let day, let hour, let minute):
            var components = calendar.dateComponents([.year, .month], from: date)
            components.day = day
            components.hour = hour
            components.minute = minute

            guard let thisMonthRun = calendar.date(from: components) else { return nil }

            if thisMonthRun > date {
                return thisMonthRun
            } else {
                // Next month
                components.month = (components.month ?? 1) + 1
                if components.month! > 12 {
                    components.month = 1
                    components.year = (components.year ?? 2024) + 1
                }
                return calendar.date(from: components)
            }
        }
    }
}

enum JobSchedule {
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)  // weekday: 1=Sunday, 2=Monday, etc.
    case monthly(day: Int, hour: Int, minute: Int)
}

// MARK: - Scheduler State for UI

struct SchedulerState {
    var nextEvent: NextEvent?
    var todaysJobs: [JobStatus] = []
    var upcomingJobs: [JobStatus] = []

    struct NextEvent {
        let description: String
        let time: Date
        let category: Category

        enum Category {
            case meetingWarning
            case scheduledJob
        }

        var formattedTime: String {
            SharedDateFormatters.time12Hour.string(from: time)
        }

        var timeUntil: String {
            let interval = time.timeIntervalSince(Date())
            if interval < 60 {
                return "now"
            } else if interval < 3600 {
                return "\(Int(interval / 60)) min"
            } else {
                return "\(Int(interval / 3600)) hr"
            }
        }
    }

    struct JobStatus: Identifiable {
        let id: String
        let name: String
        let scheduledTime: Date?
        let isCompleted: Bool

        var formattedTime: String {
            guard let time = scheduledTime else { return "" }
            return SharedDateFormatters.time12Hour.string(from: time)
        }

        var formattedDate: String {
            guard let time = scheduledTime else { return "" }
            return SharedDateFormatters.shortDayDate.string(from: time)
        }
    }

    struct MeetingWarning: Identifiable {
        let id = UUID()
        let eventTitle: String
        let eventStart: Date
        let warningTime: Date
        let minutesBefore: Int
        let minutesUntilWarning: Int

        var formattedEventTime: String {
            SharedDateFormatters.time12Hour.string(from: eventStart)
        }
    }
}
