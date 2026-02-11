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
        let snapshot = perform {
            (nextScheduledEvent, scheduledJobs, triggeredJobsToday)
        }
        let (nextEvent, jobs, triggered) = snapshot

        var state = SchedulerState()
        state.nextEvent = nextEvent

        // Build today's job statuses
        let now = Date()
        state.todaysJobs = jobs.compactMap { job -> SchedulerState.JobStatus? in
            guard case .daily = job.schedule else { return nil }

            let completed = triggered.contains(job.id)
            let nextRun = job.nextRunDate(after: now)

            return SchedulerState.JobStatus(
                id: job.id,
                name: job.name,
                scheduledTime: nextRun,
                isCompleted: completed
            )
        }

        // Build upcoming jobs (non-daily)
        state.upcomingJobs = jobs.compactMap { job -> SchedulerState.JobStatus? in
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

    @discardableResult
    func runJobNow(id: String, force: Bool = false) -> Bool {
        let jobToRun: ScheduledJob? = perform {
            guard let job = scheduledJobs.first(where: { $0.id == id }) else { return nil }
            if triggeredJobsToday.contains(job.id), !force {
                return nil
            }
            triggeredJobsToday.insert(job.id)
            return job
        }

        guard let jobToRun else { return false }

        Task {
            await MainActor.run {
                AppState.shared.logActivity(.scheduler, "Manual run: \(jobToRun.name)")
            }
            await jobToRun.action()
            recalculateNextEvent()
        }

        return true
    }

    /// Returns upcoming meeting warnings for today
    func getTodayMeetingWarnings() -> [SchedulerState.MeetingWarning] {
        guard canReadCalendarEvents() else { return [] }
        return perform {
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
            // Daily Brief - default 8:00 AM
            ScheduledJob(
                id: "morning_brief",
                name: "Daily Brief",
                schedule: .daily(hour: 8, minute: 0),
                preferenceHourKey: "morning_brief_hour",
                action: { await self.triggerMorningBrief() }
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

    private func canReadCalendarEvents() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        switch status {
        case .authorized, .fullAccess:
            return true
        case .notDetermined, .restricted, .denied, .writeOnly:
            return false
        @unknown default:
            return false
        }
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
        guard canReadCalendarEvents() else { return nil }
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
        switch event {
        case .meetingWarning(let ekEvent, let minutes):
            Task {
                await handleMeetingWarning(ekEvent, minutes: minutes)
                recalculateNextEvent()
            }

        case .job(let job):
            perform {
                _ = triggeredJobsToday.insert(job.id)
            }
            Task {
                await MainActor.run {
                    AppState.shared.logActivity(.scheduler, "Running: \(job.name)")
                }
                await job.action()
                recalculateNextEvent()
            }
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
        // Check if this specific check-in is enabled
        guard (try? Database.shared.getPreference(key: "morning_brief_enabled")) != "false" else { return }
        guard !LocalRuleEngine.shared.isQuietHours() else { return }

        let notificationType = CheckinNotificationType(
            rawValue: (try? Database.shared.getPreference(key: "morning_brief_notification_type")) ?? "notification"
        ) ?? .notification

        guard notificationType != .none else { return }

        let alert = ProactiveAlert(
            title: "Good morning!",
            body: "Your daily brief is ready. Tap to review your plan.",
            category: .briefing,
            priority: .medium
        )

        if FatigueManager.shared.shouldShow(alert: alert) {
            await sendCheckinNotification(alert: alert, type: notificationType)
            FatigueManager.shared.recordShown(alert: alert)
        }

        // Run agent tasks for this phase
        AgentTaskScheduler.shared.runCheckinTasks(phase: "morning")
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

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        SharedDateFormatters.time12Hour.string(from: date)
    }

    /// Sends a check-in notification based on the configured notification type
    private func sendCheckinNotification(alert: ProactiveAlert, type: CheckinNotificationType) async {
        switch type {
        case .notification:
            await NotificationManager.shared.sendActionableNotification(alert)
        case .voice:
            await speakNotification(alert)
        case .both:
            await NotificationManager.shared.sendActionableNotification(alert)
            await speakNotification(alert)
        case .none:
            break
        }
    }

    /// Speaks the notification using text-to-speech
    private func speakNotification(_ alert: ProactiveAlert) async {
        await MainActor.run {
            let message = "\(alert.title). \(alert.body)"
            SpeechManager.shared.speak(message)
        }
    }
}

// MARK: - Check-in Notification Type

enum CheckinNotificationType: String {
    case notification = "notification"
    case voice = "voice"
    case both = "both"
    case none = "none"
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
