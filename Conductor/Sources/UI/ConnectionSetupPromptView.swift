import SwiftUI
import AppKit

struct ConnectionSetupPromptView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onOpenSettings: () -> Void

    @State private var isWorkingCalendar = false
    @State private var isWorkingReminders = false
    @State private var isWorkingEmail = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Apps")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Conductor works best when Calendar, Reminders, and Email are connected.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            connectionRow(
                title: "Calendar",
                icon: "calendar",
                connected: appState.isCalendarConnected,
                detail: appState.isCalendarConnected ? "Connected" : "Need full access + read enabled",
                isWorking: isWorkingCalendar,
                actionTitle: appState.isCalendarConnected ? "Connected" : "Connect",
                action: requestCalendar
            )

            connectionRow(
                title: "Reminders",
                icon: "checklist",
                connected: appState.isRemindersConnected,
                detail: appState.isRemindersConnected ? "Connected" : "Need full access + read enabled",
                isWorking: isWorkingReminders,
                actionTitle: appState.isRemindersConnected ? "Connected" : "Connect",
                action: requestReminders
            )

            connectionRow(
                title: "Email",
                icon: "envelope",
                connected: appState.isEmailConfigured,
                detail: appState.isEmailConfigured
                    ? (appState.mailAppRunning ? "Enabled" : "Enabled (open Mail.app to sync now)")
                    : "Enable integration and grant Mail automation",
                isWorking: isWorkingEmail,
                actionTitle: appState.isEmailConfigured ? "Configured" : "Enable",
                action: requestEmail
            )

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }

            Divider()

            HStack {
                Button("Not Now") {
                    appState.dismissConnectionPromptForToday()
                    dismiss()
                }
                Spacer()
                Button("Open Settings") {
                    dismiss()
                    onOpenSettings()
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    appState.dismissConnectionPromptForToday()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 500)
        .onAppear {
            appState.refreshConnectionStates()
        }
    }

    @ViewBuilder
    private func connectionRow(
        title: String,
        icon: String,
        connected: Bool,
        detail: String,
        isWorking: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(connected ? .green : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()

            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 70)
            } else {
                if connected {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
                } else {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func requestCalendar() {
        Task { @MainActor in
            guard RuntimeEnvironment.supportsTCCPrompts else {
                statusMessage = "Run as a .app bundle to show Calendar permission prompts."
                return
            }

            isWorkingCalendar = true
            defer { isWorkingCalendar = false }

            let granted = await EventKitManager.shared.requestCalendarAccess()
            if granted {
                try? Database.shared.setPreference(key: "calendar_read_enabled", value: "true")
                statusMessage = "Calendar connected."
            } else {
                statusMessage = "Calendar not granted. You can enable it in System Settings > Privacy & Security > Calendars."
            }
            appState.refreshConnectionStates()
        }
    }

    private func requestReminders() {
        Task { @MainActor in
            guard RuntimeEnvironment.supportsTCCPrompts else {
                statusMessage = "Run as a .app bundle to show Reminders permission prompts."
                return
            }

            isWorkingReminders = true
            defer { isWorkingReminders = false }

            let granted = await EventKitManager.shared.requestRemindersAccess()
            if granted {
                try? Database.shared.setPreference(key: "reminders_read_enabled", value: "true")
                statusMessage = "Reminders connected."
            } else {
                statusMessage = "Reminders not granted. You can enable it in System Settings > Privacy & Security > Reminders."
            }
            appState.refreshConnectionStates()
        }
    }

    private func requestEmail() {
        Task { @MainActor in
            isWorkingEmail = true
            defer { isWorkingEmail = false }

            try? Database.shared.setPreference(key: "email_integration_enabled", value: "true")
            if !MailService.shared.isMailRunning() {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: "/System/Applications/Mail.app"),
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, _ in }
            }
            _ = await MailService.shared.getUnreadCount()
            appState.refreshConnectionStates()
            statusMessage = "Email integration enabled."
        }
    }
}
