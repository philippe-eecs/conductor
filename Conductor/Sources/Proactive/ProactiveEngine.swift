import Foundation
import UserNotifications

/// Proactive engine that runs periodic checks and sends notifications
final class ProactiveEngine {
    static let shared = ProactiveEngine()

    private var quickCheckTimer: Timer?
    private var synthesisTimer: Timer?

    private let eventKitManager = EventKitManager.shared
    private let localRuleEngine = LocalRuleEngine.shared
    private let fatigueManager = FatigueManager.shared

    private var isRunning = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Request notification permissions
        requestNotificationPermission()

        // Start quick check timer (every 60 seconds)
        quickCheckTimer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            Task {
                await self?.runQuickCheck()
            }
        }

        // Start synthesis timer (every 30 minutes)
        synthesisTimer = Timer.scheduledTimer(
            withTimeInterval: 30 * 60,
            repeats: true
        ) { [weak self] _ in
            Task {
                await self?.runSynthesis()
            }
        }

        // Run initial check
        Task {
            await runQuickCheck()
        }

        print("ProactiveEngine started")
    }

    func stop() {
        quickCheckTimer?.invalidate()
        synthesisTimer?.invalidate()
        quickCheckTimer = nil
        synthesisTimer = nil
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

    // MARK: - Quick Check (Tier 1)

    private func runQuickCheck() async {
        // Get upcoming events
        let events = await eventKitManager.getTodayEvents()

        // Run local rules (no AI, no cost)
        let alerts = localRuleEngine.checkForAlerts(events: events)

        // Filter through fatigue manager
        for alert in alerts {
            if fatigueManager.shouldShow(alert: alert) {
                await sendNotification(alert)
                fatigueManager.recordShown(alert: alert)
            }
        }
    }

    // MARK: - Synthesis (Tier 2)

    private func runSynthesis() async {
        // This would use a cheap AI model to synthesize context
        // For MVP, we'll skip this and just use local rules
        print("Synthesis check (placeholder)")
    }

    // MARK: - Notifications

    private func sendNotification(_ alert: ProactiveAlert) async {
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
