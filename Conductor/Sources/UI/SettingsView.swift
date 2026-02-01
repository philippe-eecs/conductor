import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var calendarStatus: EventKitManager.AuthorizationStatus = .notDetermined
    @State private var remindersStatus: EventKitManager.AuthorizationStatus = .notDetermined
    @State private var statusMessage: String?
    @State private var showStatusMessage: Bool = false

    // Planning preferences
    @State private var planningEnabled: Bool = true
    @State private var morningBriefHour: Int = 8
    @State private var eveningBriefHour: Int = 18
    @State private var focusSuggestionsEnabled: Bool = true
    @State private var includeOverdueReminders: Bool = true
    @State private var autoRollIncomplete: Bool = false

    // Security & Permission preferences
    @State private var calendarReadEnabled: Bool = true
    @State private var calendarWriteEnabled: Bool = false
    @State private var remindersReadEnabled: Bool = true
    @State private var remindersWriteEnabled: Bool = false
    @State private var emailEnabled: Bool = false
    @State private var commandAllowlistEnabled: Bool = true

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

                    // Assistant Mode
                    assistantModeSection

                    Divider()

                    // Cost Tracking
                    costTrackingSection

                    Divider()

                    // Calendar Access
                    calendarAccessSection

                    Divider()

                    // Daily Planning
                    dailyPlanningSection

                    Divider()

                    // Security & Permissions
                    securitySection

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
            loadPlanningPreferences()
        }
    }

    private func refreshPermissionStatuses() {
        calendarStatus = EventKitManager.shared.calendarAuthorizationStatus()
        remindersStatus = EventKitManager.shared.remindersAuthorizationStatus()
    }

    private func loadPlanningPreferences() {
        planningEnabled = (try? Database.shared.getPreference(key: "planning_enabled")) != "false"
        morningBriefHour = Int((try? Database.shared.getPreference(key: "morning_brief_hour")) ?? "8") ?? 8
        eveningBriefHour = Int((try? Database.shared.getPreference(key: "evening_brief_hour")) ?? "18") ?? 18
        focusSuggestionsEnabled = (try? Database.shared.getPreference(key: "focus_suggestions_enabled")) != "false"
        includeOverdueReminders = (try? Database.shared.getPreference(key: "include_overdue_reminders")) != "false"
        autoRollIncomplete = (try? Database.shared.getPreference(key: "auto_roll_incomplete")) == "true"

        // Security preferences (default to safe values)
        calendarReadEnabled = (try? Database.shared.getPreference(key: "calendar_read_enabled")) != "false"
        calendarWriteEnabled = (try? Database.shared.getPreference(key: "calendar_write_enabled")) == "true"
        remindersReadEnabled = (try? Database.shared.getPreference(key: "reminders_read_enabled")) != "false"
        remindersWriteEnabled = (try? Database.shared.getPreference(key: "reminders_write_enabled")) == "true"
        emailEnabled = (try? Database.shared.getPreference(key: "email_integration_enabled")) == "true"
        commandAllowlistEnabled = (try? Database.shared.getPreference(key: "command_allowlist_enabled")) != "false"
    }

    private func savePlanningPreference(key: String, value: String) {
        try? Database.shared.setPreference(key: key, value: value)
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

    // MARK: - Assistant Mode Section

    private var assistantModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Assistant Mode", systemImage: "wand.and.stars")
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                // Safe mode (default)
                modeOption(
                    title: "Safe Mode",
                    description: "Q&A only. Cannot execute commands or modify files.",
                    icon: "shield.fill",
                    iconColor: .green,
                    isSelected: !appState.toolsEnabled
                ) {
                    appState.setToolsEnabled(false)
                }

                // Tool mode
                modeOption(
                    title: "Tool Mode",
                    description: "Can execute commands and actions with your approval.",
                    icon: "hammer.fill",
                    iconColor: .orange,
                    isSelected: appState.toolsEnabled
                ) {
                    appState.setToolsEnabled(true)
                }
            }

            if appState.toolsEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Claude will ask for permission before running commands or making changes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func modeOption(
        title: String,
        description: String,
        icon: String,
        iconColor: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title2)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                }
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    // MARK: - Daily Planning Section

    private var dailyPlanningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Daily Planning", systemImage: "calendar.badge.clock")
                .font(.headline)

            // Master toggle
            Toggle("Enable daily planning", isOn: $planningEnabled)
                .onChange(of: planningEnabled) { _, newValue in
                    savePlanningPreference(key: "planning_enabled", value: newValue ? "true" : "false")
                }

            if planningEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    // Morning Brief Time
                    HStack {
                        Text("Morning Brief")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $morningBriefHour) {
                            ForEach(5..<12, id: \.self) { hour in
                                Text("\(hour):00 AM").tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .onChange(of: morningBriefHour) { _, newValue in
                            savePlanningPreference(key: "morning_brief_hour", value: String(newValue))
                        }
                    }

                    // Evening Shutdown Time
                    HStack {
                        Text("Evening Shutdown")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $eveningBriefHour) {
                            ForEach(16..<22, id: \.self) { hour in
                                Text("\(hour > 12 ? hour - 12 : hour):00 \(hour >= 12 ? "PM" : "AM")").tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .onChange(of: eveningBriefHour) { _, newValue in
                            savePlanningPreference(key: "evening_brief_hour", value: String(newValue))
                        }
                    }

                    Divider()

                    // Additional toggles
                    Toggle("Show focus block suggestions", isOn: $focusSuggestionsEnabled)
                        .font(.subheadline)
                        .onChange(of: focusSuggestionsEnabled) { _, newValue in
                            savePlanningPreference(key: "focus_suggestions_enabled", value: newValue ? "true" : "false")
                        }

                    Toggle("Include overdue reminders in briefs", isOn: $includeOverdueReminders)
                        .font(.subheadline)
                        .onChange(of: includeOverdueReminders) { _, newValue in
                            savePlanningPreference(key: "include_overdue_reminders", value: newValue ? "true" : "false")
                        }

                    Toggle("Auto-roll incomplete goals", isOn: $autoRollIncomplete)
                        .font(.subheadline)
                        .onChange(of: autoRollIncomplete) { _, newValue in
                            savePlanningPreference(key: "auto_roll_incomplete", value: newValue ? "true" : "false")
                        }
                }
                .padding(.leading, 4)
            }

            Text("Daily briefs help you start and end your day with intention.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Security & Permissions", systemImage: "lock.shield")
                .font(.headline)

            Text("Control what data Conductor can access and what actions it can perform.")
                .font(.callout)
                .foregroundColor(.secondary)

            // Data Access Permissions
            VStack(alignment: .leading, spacing: 10) {
                Text("Data Access")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                // Calendar permissions
                permissionToggleRow(
                    title: "Calendar",
                    icon: "calendar",
                    readEnabled: $calendarReadEnabled,
                    writeEnabled: $calendarWriteEnabled,
                    readKey: "calendar_read_enabled",
                    writeKey: "calendar_write_enabled"
                )

                // Reminders permissions
                permissionToggleRow(
                    title: "Reminders",
                    icon: "checklist",
                    readEnabled: $remindersReadEnabled,
                    writeEnabled: $remindersWriteEnabled,
                    readKey: "reminders_read_enabled",
                    writeKey: "reminders_write_enabled"
                )

                // Email toggle
                HStack {
                    Image(systemName: "envelope")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("Email")
                        .font(.subheadline)
                    Spacer()
                    Toggle("", isOn: $emailEnabled)
                        .labelsHidden()
                        .onChange(of: emailEnabled) { _, newValue in
                            savePlanningPreference(key: "email_integration_enabled", value: newValue ? "true" : "false")
                            logSecurityChange("Email integration", enabled: newValue)
                        }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }

            // Command Execution
            VStack(alignment: .leading, spacing: 10) {
                Text("Command Execution")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                // Command allowlist toggle
                HStack {
                    Image(systemName: "terminal")
                        .foregroundColor(.orange)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Command Allowlist")
                            .font(.subheadline)
                        Text("Only allow safe commands (git, ls, cat)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $commandAllowlistEnabled)
                        .labelsHidden()
                        .onChange(of: commandAllowlistEnabled) { _, newValue in
                            savePlanningPreference(key: "command_allowlist_enabled", value: newValue ? "true" : "false")
                            logSecurityChange("Command allowlist", enabled: newValue)
                        }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                if appState.toolsEnabled && !commandAllowlistEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Warning: Tool mode is enabled without command restrictions. Claude can execute any command.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }
            }

            // Allowed commands info
            if commandAllowlistEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allowed Commands")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text("git (status, diff, log), ls, cat, head, tail, echo, pwd")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                }
            }
        }
    }

    private func permissionToggleRow(
        title: String,
        icon: String,
        readEnabled: Binding<Bool>,
        writeEnabled: Binding<Bool>,
        readKey: String,
        writeKey: String
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 12) {
                Toggle("Read", isOn: readEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: readEnabled.wrappedValue) { _, newValue in
                        savePlanningPreference(key: readKey, value: newValue ? "true" : "false")
                        logSecurityChange("\(title) read access", enabled: newValue)
                    }
                Toggle("Write", isOn: writeEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: writeEnabled.wrappedValue) { _, newValue in
                        savePlanningPreference(key: writeKey, value: newValue ? "true" : "false")
                        logSecurityChange("\(title) write access", enabled: newValue)
                    }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func logSecurityChange(_ setting: String, enabled: Bool) {
        appState.logActivity(.system, "\(setting) \(enabled ? "enabled" : "disabled")")
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
