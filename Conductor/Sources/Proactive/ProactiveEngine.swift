import Foundation
import UserNotifications

/// Proactive engine that coordinates event-driven scheduling and notifications
final class ProactiveEngine {
    static let shared = ProactiveEngine()

    private let eventKitManager = EventKitManager.shared
    private let localRuleEngine = LocalRuleEngine.shared
    private let fatigueManager = FatigueManager.shared
    private let eventScheduler = EventScheduler.shared

    private var isRunning = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Request notification permissions
        if RuntimeEnvironment.supportsUserNotifications {
            requestNotificationPermission()
        } else {
            NSLog("ProactiveEngine notifications disabled (not running inside a .app bundle).")
        }

        // Start event-driven scheduler (handles meeting warnings, daily/weekly/monthly jobs)
        eventScheduler.start()

        print("ProactiveEngine started (event-driven mode)")
    }

    func stop() {
        eventScheduler.stop()
        isRunning = false

        print("ProactiveEngine stopped")
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            print("Notification permission granted: \(granted)")
        }
    }

    // MARK: - Focus Block Suggestions

    /// Called by EventScheduler or manually to check for focus block opportunities
    func checkFocusBlockSuggestions() async {
        // Check if focus suggestions are enabled
        let focusSuggestionsEnabled = (try? Database.shared.getPreference(key: "focus_suggestions_enabled")) != "false"
        guard focusSuggestionsEnabled else { return }

        let events = await eventKitManager.getTodayEvents()

        // Check if there are incomplete high-priority goals
        let today = DailyPlanningService.todayDateString
        let goals = (try? Database.shared.getGoalsForDate(today)) ?? []
        let hasIncompleteGoals = goals.contains { !$0.isCompleted }

        if let gap = localRuleEngine.shouldSuggestFocusBlock(
            events: events,
            hasHighPriorityTasks: hasIncompleteGoals
        ) {
            let alert = ProactiveAlert(
                title: "Focus block available",
                body: "You have \(gap.formattedDuration) free (\(gap.formattedTimeRange)). Block time for deep work?",
                category: .suggestion,
                priority: .low
            )

            if fatigueManager.shouldShow(alert: alert) {
                await sendNotification(alert)
                fatigueManager.recordShown(alert: alert)
            }
        }
    }

    // MARK: - Notifications

    /// Public method for EventScheduler to send notifications
    func sendNotificationPublic(_ alert: ProactiveAlert) async {
        await sendNotification(alert)
    }

    private func sendNotification(_ alert: ProactiveAlert) async {
        guard RuntimeEnvironment.supportsUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.categoryIdentifier = alert.category.rawValue

        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to send notification: \(error)")
        }
    }
}

// MARK: - Alert Types

struct ProactiveAlert {
    let id: String
    let title: String
    let body: String
    let category: Category
    let priority: Priority
    let timestamp: Date

    enum Category: String {
        case meeting = "meeting"
        case reminder = "reminder"
        case suggestion = "suggestion"
        case briefing = "briefing"
    }

    enum Priority: Int {
        case low = 0
        case medium = 1
        case high = 2
    }

    init(
        title: String,
        body: String,
        category: Category,
        priority: Priority = .medium
    ) {
        self.id = UUID().uuidString
        self.title = title
        self.body = body
        self.category = category
        self.priority = priority
        self.timestamp = Date()
    }
}
