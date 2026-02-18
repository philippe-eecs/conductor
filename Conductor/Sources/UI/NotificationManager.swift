import Foundation
import UserNotifications
import AppKit

final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    static let blinkCategory = "BLINK_CATEGORY"
    static let respondAction = "RESPOND_ACTION"
    static let dismissAction = "DISMISS_ACTION"

    private override init() {
        super.init()
        guard RuntimeEnvironment.supportsUserNotifications else {
            NSLog("NotificationManager disabled (not running inside a .app bundle).")
            return
        }
        setupCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    private func setupCategories() {
        let respondAction = UNNotificationAction(
            identifier: Self.respondAction,
            title: "Open",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: Self.dismissAction,
            title: "Dismiss",
            options: [.destructive]
        )

        let blinkCategory = UNNotificationCategory(
            identifier: Self.blinkCategory,
            actions: [respondAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([blinkCategory])
    }

    func sendNotification(title: String, body: String) async {
        guard RuntimeEnvironment.supportsUserNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.blinkCategory

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            Log.notify.info("Notification sent: \(title, privacy: .public)")
        } catch {
            Log.notify.error("Failed to send notification: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case Self.respondAction, UNNotificationDefaultActionIdentifier:
            DispatchQueue.main.async {
                MainWindowController.shared.showWindow(appState: AppState.shared)
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
        completionHandler([.banner, .sound])
    }
}

extension Notification.Name {
    static let mcpToolCalled = Notification.Name("mcpToolCalled")
    static let mcpServerFailed = Notification.Name("mcpServerFailed")
    static let openConductorWithPrompt = Notification.Name("openConductorWithPrompt")
}
