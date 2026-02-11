import Foundation
import UserNotifications
import AppKit

/// Manages actionable notifications with response tracking
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    // Notification categories
    static let checkinCategory = "CHECKIN_CATEGORY"
    static let meetingCategory = "MEETING_CATEGORY"
    static let briefingCategory = "BRIEFING_CATEGORY"

    // Action identifiers
    static let respondAction = "RESPOND_ACTION"
    static let snoozeAction = "SNOOZE_ACTION"
    static let dismissAction = "DISMISS_ACTION"

    private override init() {
        super.init()
        guard RuntimeEnvironment.supportsUserNotifications else {
            NSLog("NotificationManager disabled (not running inside a .app bundle).")
            return
        }
        setupNotificationCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Setup

    private func setupNotificationCategories() {
        // Respond action - opens Conductor with prompt
        let respondAction = UNNotificationAction(
            identifier: Self.respondAction,
            title: "Respond",
            options: [.foreground]
        )

        // Snooze action - reschedules notification
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeAction,
            title: "Snooze 15m",
            options: []
        )

        // Dismiss action - dismisses silently
        let dismissAction = UNNotificationAction(
            identifier: Self.dismissAction,
            title: "Dismiss",
            options: [.destructive]
        )

        // Check-in category
        let checkinCategory = UNNotificationCategory(
            identifier: Self.checkinCategory,
            actions: [respondAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Meeting category
        let meetingCategory = UNNotificationCategory(
            identifier: Self.meetingCategory,
            actions: [respondAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        // Briefing category
        let briefingCategory = UNNotificationCategory(
            identifier: Self.briefingCategory,
            actions: [respondAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            checkinCategory,
            meetingCategory,
            briefingCategory
        ])
    }

    // MARK: - Send Notifications

    /// Sends an actionable notification with Respond/Snooze/Dismiss buttons
    func sendActionableNotification(_ alert: ProactiveAlert) async {
        guard RuntimeEnvironment.supportsUserNotifications else {
            await MainActor.run {
                AppState.shared.logActivity(.scheduler, "Notifications unavailable; skipped: \(alert.title)")
            }
            return
        }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default

        // Set category based on alert type
        switch alert.category {
        case .meeting:
            content.categoryIdentifier = Self.meetingCategory
        case .briefing:
            content.categoryIdentifier = Self.briefingCategory
        case .suggestion, .reminder:
            content.categoryIdentifier = Self.checkinCategory
        }

        // Store alert info for response handling
        content.userInfo = [
            "alert_id": alert.id,
            "alert_title": alert.title,
            "alert_body": alert.body,
            "alert_category": alert.category.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            await MainActor.run {
                AppState.shared.logActivity(.scheduler, "Notification sent: \(alert.title)")
            }
        } catch {
            print("Failed to send notification: \(error)")
        }
    }

    /// Schedules a snoozed notification
    func snoozeNotification(_ alert: ProactiveAlert, minutes: Int = 15) async {
        guard RuntimeEnvironment.supportsUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body + " (snoozed)"
        content.sound = .default
        content.categoryIdentifier = Self.checkinCategory
        content.userInfo = [
            "alert_id": alert.id,
            "alert_title": alert.title,
            "alert_body": alert.body,
            "alert_category": alert.category.rawValue
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "\(alert.id)_snoozed",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule snoozed notification: \(error)")
        }
    }

    // MARK: - Meeting Prep Notifications

    /// Schedules a pre-meeting notification
    func scheduleMeetingPrep(for event: EventKitManager.CalendarEvent, minutesBefore: Int = 15) async {
        guard RuntimeEnvironment.supportsUserNotifications else { return }
        let alertTime = event.startDate.addingTimeInterval(-Double(minutesBefore * 60))

        // Don't schedule if already past
        guard alertTime > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Meeting in \(minutesBefore) minutes"
        content.body = "\(event.title). Need anything prepped?"
        content.sound = .default
        content.categoryIdentifier = Self.meetingCategory
        content.userInfo = [
            "event_id": event.id,
            "event_title": event.title
        ]

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: alertTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(
            identifier: "meeting_prep_\(event.id)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule meeting prep: \(error)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case Self.respondAction, UNNotificationDefaultActionIdentifier:
            // Open Conductor and focus chat
            DispatchQueue.main.async {
                MainWindowController.shared.showWindow(appState: AppState.shared)

                // If there's a prompt body, we could pre-fill the chat
                if let body = userInfo["alert_body"] as? String {
                    // Post notification to open with context
                    NotificationCenter.default.post(
                        name: .openConductorWithPrompt,
                        object: nil,
                        userInfo: ["prompt": body]
                    )
                }

                AppState.shared.logActivity(.scheduler, "User responded to notification")
            }

        case Self.snoozeAction:
            // Reschedule for 15 minutes later
            if let _ = userInfo["alert_id"] as? String,
               let title = userInfo["alert_title"] as? String,
               let body = userInfo["alert_body"] as? String,
               let categoryRaw = userInfo["alert_category"] as? String,
               let category = ProactiveAlert.Category(rawValue: categoryRaw) {

                let snoozedAlert = ProactiveAlert(title: title, body: body, category: category)
                Task {
                    await snoozeNotification(snoozedAlert, minutes: 15)
                    await MainActor.run {
                        AppState.shared.logActivity(.scheduler, "Notification snoozed: \(title)")
                    }
                }
            }

        case Self.dismissAction:
            // Just log dismissal
            DispatchQueue.main.async {
                if let title = userInfo["alert_title"] as? String {
                    AppState.shared.logActivity(.scheduler, "Notification dismissed: \(title)")
                }
            }

        default:
            break
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openConductorWithPrompt = Notification.Name("openConductorWithPrompt")
}
