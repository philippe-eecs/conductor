import SwiftUI

// MARK: - Permissions, Connections & Setup

extension AppState {

    func refreshPermissionStates() {
        let calendarStatus = EventKitManager.shared.calendarAuthorizationStatus()
        calendarAccessGranted = calendarStatus == .fullAccess
        calendarWriteOnlyAccess = calendarStatus == .writeOnly

        let remindersStatus = EventKitManager.shared.remindersAuthorizationStatus()
        remindersAccessGranted = remindersStatus == .fullAccess
        remindersWriteOnlyAccess = remindersStatus == .writeOnly
    }

    func refreshConnectionStates() {
        refreshPermissionStates()
        calendarReadEnabled = (try? Database.shared.getPreference(key: "calendar_read_enabled")) != "false"
        remindersReadEnabled = (try? Database.shared.getPreference(key: "reminders_read_enabled")) != "false"
        emailIntegrationEnabled = (try? Database.shared.getPreference(key: "email_integration_enabled")) == "true"
        mailAppRunning = MailService.shared.isMailRunning()
    }

    var isCalendarConnected: Bool {
        calendarAccessGranted && calendarReadEnabled
    }

    var isRemindersConnected: Bool {
        remindersAccessGranted && remindersReadEnabled
    }

    var isEmailConfigured: Bool {
        emailIntegrationEnabled
    }

    var hasMissingInitialConnections: Bool {
        !isCalendarConnected || !isRemindersConnected || !isEmailConfigured
    }

    func shouldShowConnectionPrompt() -> Bool {
        guard hasCompletedSetup else { return false }
        guard hasMissingInitialConnections else { return false }
        let today = DailyPlanningService.todayDateString
        let dismissed = (try? Database.shared.getPreference(key: connectionPromptDismissedDateKey)) ?? nil
        return dismissed != today
    }

    func dismissConnectionPromptForToday() {
        try? Database.shared.setPreference(key: connectionPromptDismissedDateKey, value: DailyPlanningService.todayDateString)
    }

    func completeSetup() {
        hasCompletedSetup = true
        Task.detached(priority: .utility) {
            try? Database.shared.setPreference(key: "setup_completed", value: "true")
        }
        refreshConnectionStates()
        logActivity(.system, "Setup completed")
    }

    func setToolsEnabled(_ enabled: Bool) {
        toolsEnabled = enabled
        Task.detached(priority: .utility) {
            try? Database.shared.setPreference(key: "tools_enabled", value: enabled ? "true" : "false")
        }
        logActivity(.system, enabled ? "Insecure mode enabled" : "Insecure mode disabled")
    }

    func checkCLIStatus() async {
        let available = await claudeService.checkCLIAvailable()
        let version = await claudeService.getCLIVersion()

        self.cliAvailable = available
        self.cliVersion = version

        if !available {
            logActivity(.error, "Claude CLI not found")
        }
    }

    func checkPlanningNotifications() {
        let today = DailyPlanningService.todayDateString
        if let brief = try? Database.shared.getDailyBrief(for: today, type: .morning),
           brief.readAt == nil && !brief.dismissed {
            showPlanningNotificationBadge = true
        } else {
            showPlanningNotificationBadge = false
        }
    }
}
