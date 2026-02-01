import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var calendarStatus: EventKitManager.AuthorizationStatus = .notDetermined
    @State private var remindersStatus: EventKitManager.AuthorizationStatus = .notDetermined
    @State private var statusMessage: String?
    @State private var showStatusMessage: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Claude CLI Status
                    cliStatusSection

                    Divider()

                    // Cost Tracking
                    costTrackingSection

                    Divider()

                    // Calendar Access
                    calendarAccessSection

                    Divider()

                    // About Section
                    aboutSection
                }
                .padding()
            }

            // Status message overlay
            if showStatusMessage, let message = statusMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.callout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .shadow(radius: 4)
                        .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            refreshPermissionStatuses()
        }
    }

    private func refreshPermissionStatuses() {
        calendarStatus = EventKitManager.shared.calendarAuthorizationStatus()
        remindersStatus = EventKitManager.shared.remindersAuthorizationStatus()
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        withAnimation {
            showStatusMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                showStatusMessage = false
            }
        }
    }

    // MARK: - CLI Status Section

    private var cliStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Claude Code", systemImage: "terminal")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: appState.cliAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(appState.cliAvailable ? .green : .red)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.cliAvailable ? "Connected" : "Not Found")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let version = appState.cliVersion {
                        Text(version)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !appState.cliAvailable {
                        Text("Install Claude Code to use Conductor")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Refresh") {
                    Task {
                        await appState.checkCLIStatus()
                    }
                }
                .buttonStyle(.bordered)
            }

            if !appState.cliAvailable {
                Link("Install Claude Code", destination: URL(string: "https://claude.ai/code")!)
                    .font(.caption)
            }

            Text("Conductor uses your Claude Code Max subscription. No separate API key required.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Cost Tracking Section

    private var costTrackingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Usage & Cost", systemImage: "dollarsign.circle")
                .font(.headline)

            HStack(spacing: 24) {
                costCard("Today", amount: appState.dailyCost)
                costCard("This Week", amount: appState.weeklyCost)
                costCard("This Month", amount: appState.monthlyCost)
            }

            Text("Cost tracking is based on Claude CLI response data.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func costCard(_ label: String, amount: Double) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "$%.2f", amount))
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Calendar Access Section

    private var calendarAccessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Calendar & Reminders", systemImage: "calendar")
                .font(.headline)

            Text("Conductor can access your calendar and reminders to provide context-aware assistance.")
                .font(.callout)
                .foregroundColor(.secondary)

            // Calendar row
            permissionRow(
                label: "Calendar",
                status: calendarStatus,
                onRequest: {
                    Task {
                        let granted = await EventKitManager.shared.requestCalendarAccess()
                        await MainActor.run {
                            calendarStatus = EventKitManager.shared.calendarAuthorizationStatus()
                            if granted {
                                showStatus("Calendar access granted!")
                            } else if calendarStatus == .denied {
                                showStatus("Calendar access denied. Enable in System Settings.")
                            }
                        }
                    }
                },
                systemSettingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
            )

            // Reminders row
            permissionRow(
                label: "Reminders",
                status: remindersStatus,
                onRequest: {
                    Task {
                        let granted = await EventKitManager.shared.requestRemindersAccess()
                        await MainActor.run {
                            remindersStatus = EventKitManager.shared.remindersAuthorizationStatus()
                            if granted {
                                showStatus("Reminders access granted!")
                            } else if remindersStatus == .denied {
                                showStatus("Reminders access denied. Enable in System Settings.")
                            }
                        }
                    }
                },
                systemSettingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
            )
        }
    }

    private func permissionRow(
        label: String,
        status: EventKitManager.AuthorizationStatus,
        onRequest: @escaping () -> Void,
        systemSettingsURL: String
    ) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: statusIcon(status))
                .foregroundColor(statusColor(status))
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(statusText(status))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action button
            if status == .notDetermined {
                Button("Request Access") {
                    onRequest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if status == .denied || status == .restricted {
                Button("Open Settings") {
                    if let url = URL(string: systemSettingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func statusIcon(_ status: EventKitManager.AuthorizationStatus) -> String {
        switch status {
        case .fullAccess, .writeOnly:
            return "checkmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        case .denied, .restricted:
            return "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: EventKitManager.AuthorizationStatus) -> Color {
        switch status {
        case .fullAccess, .writeOnly:
            return .green
        case .notDetermined:
            return .orange
        case .denied, .restricted:
            return .red
        }
    }

    private func statusText(_ status: EventKitManager.AuthorizationStatus) -> String {
        switch status {
        case .fullAccess:
            return "Full Access"
        case .writeOnly:
            return "Write Only"
        case .notDetermined:
            return "Not Requested"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("About", systemImage: "info.circle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Conductor")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Your AI-powered personal assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Version 0.1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                keyboardShortcut("Cmd+Shift+C", description: "Toggle window")
                keyboardShortcut("Enter", description: "Send message")
                keyboardShortcut("Cmd+N", description: "New conversation")
            }
        }
    }

    private func keyboardShortcut(_ keys: String, description: String) -> some View {
        HStack {
            Text(keys)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
