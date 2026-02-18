import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var speechManager = SpeechManager.shared

    @State private var calendarStatus: EventKitManager.AuthorizationStatus = .notDetermined
    @State private var remindersStatus: EventKitManager.AuthorizationStatus = .notDetermined
    @State private var statusMessage: String?
    @State private var showStatusMessage: Bool = false

    // Planning preferences
    @State private var planningEnabled: Bool = true
    @State private var morningBriefHour: Int = 8
    @State private var focusSuggestionsEnabled: Bool = true
    @State private var includeOverdueReminders: Bool = true
    @State private var autoRollIncomplete: Bool = false
    @State private var weeklyReviewEnabled: Bool = true
    @State private var monthlyReviewEnabled: Bool = true

    // Daily Brief configuration
    @State private var morningBriefEnabled: Bool = true
    @State private var morningBriefNotificationType: NotificationType = .notification

    // Claude model preferences
    @State private var chatModel: String = "opus"
    @State private var planningModel: String = "opus"
    @State private var claudePermissionMode: String = "plan"

    // Security & Permission preferences
    @State private var calendarReadEnabled: Bool = true
    @State private var calendarWriteEnabled: Bool = false
    @State private var remindersReadEnabled: Bool = true
    @State private var remindersWriteEnabled: Bool = false
    @State private var emailEnabled: Bool = false
    @State private var commandAllowlistEnabled: Bool = true

    // Agent task preferences
    @State private var agentTasksEnabled: Bool = true
    @State private var emailSweepEnabled: Bool = false
    @State private var agentTaskModel: String = "sonnet"
    @State private var activeAgentTaskCount: Int = 0

    // Diagnostics
    @State private var lastCalendarFetchCount: Int?
    @State private var lastRemindersFetchCount: Int?
    @State private var lastContextSnapshotSummary: String?
    @State private var lastDiagnosticsRunAt: Date?

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

                    // Voice Output
                    voiceSection

                    Divider()

                    // Cost Tracking
                    costTrackingSection

                    Divider()

                    // Calendar Access
                    calendarAccessSection

                    Divider()

                    diagnosticsSection

                    Divider()

                    // Daily Planning
                    dailyPlanningSection

                    Divider()

                    // Security & Permissions
                    securitySection

                    Divider()

                    // Agent Tasks
                    agentTasksSection

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
        focusSuggestionsEnabled = (try? Database.shared.getPreference(key: "focus_suggestions_enabled")) != "false"
        includeOverdueReminders = (try? Database.shared.getPreference(key: "include_overdue_reminders")) != "false"
        autoRollIncomplete = (try? Database.shared.getPreference(key: "auto_roll_incomplete")) == "true"
        weeklyReviewEnabled = (try? Database.shared.getPreference(key: "weekly_review_enabled")) != "false"
        monthlyReviewEnabled = (try? Database.shared.getPreference(key: "monthly_review_enabled")) != "false"

        chatModel = (((try? Database.shared.getPreference(key: "claude_chat_model")) ?? nil) ?? "opus")
        planningModel = (((try? Database.shared.getPreference(key: "claude_planning_model")) ?? nil) ?? "opus")
        claudePermissionMode = (((try? Database.shared.getPreference(key: "claude_permission_mode")) ?? nil) ?? "plan")

        // Daily Brief configuration
        morningBriefEnabled = (try? Database.shared.getPreference(key: "morning_brief_enabled")) != "false"
        morningBriefNotificationType = NotificationType(rawValue: (try? Database.shared.getPreference(key: "morning_brief_notification_type")) ?? "notification") ?? .notification

        // Security preferences (default to safe values)
        calendarReadEnabled = (try? Database.shared.getPreference(key: "calendar_read_enabled")) != "false"
        calendarWriteEnabled = (try? Database.shared.getPreference(key: "calendar_write_enabled")) == "true"
        remindersReadEnabled = (try? Database.shared.getPreference(key: "reminders_read_enabled")) != "false"
        remindersWriteEnabled = (try? Database.shared.getPreference(key: "reminders_write_enabled")) == "true"
        emailEnabled = (try? Database.shared.getPreference(key: "email_integration_enabled")) == "true"
        commandAllowlistEnabled = (try? Database.shared.getPreference(key: "command_allowlist_enabled")) != "false"

        agentTasksEnabled = (try? Database.shared.getPreference(key: "agent_tasks_enabled")) != "false"
        emailSweepEnabled = (try? Database.shared.getPreference(key: "email_sweep_enabled")) == "true"
        agentTaskModel = (((try? Database.shared.getPreference(key: "agent_task_model")) ?? nil) ?? "sonnet")
        activeAgentTaskCount = (try? Database.shared.getActiveAgentTasks().count) ?? 0
    }

    private func savePlanningPreference(key: String, value: String) {
        try? Database.shared.setPreference(key: key, value: value)
    }

    private static func makeTimeDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func saveTimePreference(date: Date, hourKey: String, minuteKey: String) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        savePlanningPreference(key: hourKey, value: String(components.hour ?? 0))
        savePlanningPreference(key: minuteKey, value: String(components.minute ?? 0))
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

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Chat model")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: $chatModel) {
                        Text("Sonnet").tag("sonnet")
                        Text("Opus").tag("opus")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .onChange(of: chatModel) { _, newValue in
                        savePlanningPreference(key: "claude_chat_model", value: newValue)
                    }
                }

                HStack {
                    Text("Planning model")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: $planningModel) {
                        Text("Opus").tag("opus")
                        Text("Sonnet").tag("sonnet")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .onChange(of: planningModel) { _, newValue in
                        savePlanningPreference(key: "claude_planning_model", value: newValue)
                    }
                }

                Text("If Claude Code changes model names, update these to match your CLI.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Assistant Mode Section

    private var assistantModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Assistant Mode", systemImage: "wand.and.stars")
                .font(.headline)

            Toggle("Enable tool execution", isOn: Binding(
                get: { appState.toolsEnabled },
                set: { appState.setToolsEnabled($0) }
            ))

            if appState.toolsEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Tool permission mode")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $claudePermissionMode) {
                            Text("Plan").tag("plan")
                            Text("Default").tag("default")
                            Text("Don't ask").tag("dontAsk")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160)
                        .onChange(of: claudePermissionMode) { _, newValue in
                            savePlanningPreference(key: "claude_permission_mode", value: newValue)
                            showStatus("Tool permission mode set to \(newValue)")
                        }
                    }

                    Text("\"Plan\" is safest: Claude will propose actions instead of executing them. Use \"Default\" only if you can monitor approvals.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 6)

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("When enabled, Claude can execute commands (with approval prompts).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }

            Text("Context is fetched on-demand via MCP tools, gated by the permission toggles below.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Voice Output", systemImage: "speaker.wave.2")
                .font(.headline)

            Toggle("Read responses aloud", isOn: Binding(
                get: { speechManager.isEnabled },
                set: { speechManager.setEnabled($0) }
            ))

            if speechManager.isEnabled {
                HStack {
                    Text("Voice")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { speechManager.selectedVoice },
                        set: { speechManager.setVoice($0) }
                    )) {
                        Text("System Default").tag("")
                        ForEach(speechManager.availableVoices, id: \.id) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }

                if speechManager.isSpeaking {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Speaking...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Stop") {
                            speechManager.stop()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Text("When enabled, Conductor will read assistant responses using text-to-speech.")
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
                        guard RuntimeEnvironment.supportsTCCPrompts else {
                            showStatus("Permission prompts require running as a .app bundle. Use scripts/dev-run-app.sh.")
                            return
                        }
                        let granted = await EventKitManager.shared.requestCalendarAccess()
                        await MainActor.run {
                            calendarStatus = EventKitManager.shared.calendarAuthorizationStatus()
                            if granted {
                                try? Database.shared.setPreference(key: "calendar_read_enabled", value: "true")
                                showStatus("Calendar access granted!")
                            } else if calendarStatus == .denied {
                                showStatus("Calendar access denied. Enable in System Settings.")
                            }
                            appState.refreshConnectionStates()
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
                        guard RuntimeEnvironment.supportsTCCPrompts else {
                            showStatus("Permission prompts require running as a .app bundle. Use scripts/dev-run-app.sh.")
                            return
                        }
                        let granted = await EventKitManager.shared.requestRemindersAccess()
                        await MainActor.run {
                            remindersStatus = EventKitManager.shared.remindersAuthorizationStatus()
                            if granted {
                                try? Database.shared.setPreference(key: "reminders_read_enabled", value: "true")
                                showStatus("Reminders access granted!")
                            } else if remindersStatus == .denied {
                                showStatus("Reminders access denied. Enable in System Settings.")
                            }
                            appState.refreshConnectionStates()
                        }
                    }
                },
                systemSettingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
            )
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Diagnostics", systemImage: "stethoscope")
                .font(.headline)

            Text("Use these to verify Calendar/Reminders access and whether context is making it into the assistant prompt.")
                .font(.callout)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Calendar auth")
                        .font(.subheadline)
                    Spacer()
                    Text(statusText(calendarStatus))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Reminders auth")
                        .font(.subheadline)
                    Spacer()
                    Text(statusText(remindersStatus))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                HStack(spacing: 10) {
                    Button("Fetch Today’s Events") {
                        Task { await runCalendarFetchDiagnostics() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Fetch Reminders") {
                        Task { await runRemindersFetchDiagnostics() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Build Context Snapshot") {
                        Task { await runContextSnapshotDiagnostics() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let at = lastDiagnosticsRunAt {
                    Text("Last run: \(SharedDateFormatters.mediumDateTime.string(from: at))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let count = lastCalendarFetchCount {
                    Text("Calendar fetch: \(count) event\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let count = lastRemindersFetchCount {
                    Text("Reminders fetch: \(count) item\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let summary = lastContextSnapshotSummary {
                    Text("Context snapshot: \(summary)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Text("If permissions keep re-prompting after rebuilds, sign the app with a stable Apple Development identity (see build script).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func permissionRow(
        label: String,
        status: EventKitManager.AuthorizationStatus,
        onRequest: @escaping () -> Void,
        systemSettingsURL: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    if RuntimeEnvironment.supportsTCCPrompts {
                        Button("Request Access") {
                            onRequest()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Request Access") {}
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(true)
                    }
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

            if status == .notDetermined && !RuntimeEnvironment.supportsTCCPrompts {
                Text("Permission prompts require running as a .app bundle. Use scripts/dev-run-app.sh.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if status == .writeOnly {
                Text("Write-only access allows creating items but not reading your schedule/tasks. Grant full access for schedule/context features.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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

    private func diagnosticsStamp() {
        lastDiagnosticsRunAt = Date()
        refreshPermissionStatuses()
        appState.refreshPermissionStates()
    }

    @MainActor
    private func runCalendarFetchDiagnostics() async {
        diagnosticsStamp()
        let events = await EventKitManager.shared.getTodayEvents()
        lastCalendarFetchCount = events.count
        appState.logActivity(.context, "Diagnostics: fetched \(events.count) calendar event(s) for today")
        showStatus(events.isEmpty ? "Fetched 0 events" : "Fetched \(events.count) events")
    }

    @MainActor
    private func runRemindersFetchDiagnostics() async {
        diagnosticsStamp()
        let reminders = await EventKitManager.shared.getUpcomingReminders(limit: 10)
        lastRemindersFetchCount = reminders.count
        appState.logActivity(.context, "Diagnostics: fetched \(reminders.count) reminder(s)")
        showStatus(reminders.isEmpty ? "Fetched 0 reminders" : "Fetched \(reminders.count) reminders")
    }

    @MainActor
    private func runContextSnapshotDiagnostics() async {
        diagnosticsStamp()
        let context = await ContextBuilder.shared.buildContext()

        let summaryParts: [String] = [
            "events=\(context.todayEvents.count)",
            "reminders=\(context.upcomingReminders.count)",
            "notes=\(context.recentNotes.count)",
            "goals=\(context.planningContext?.todaysGoals.count ?? 0)",
            "email=\(context.emailContext?.importantEmails.count ?? 0)"
        ]
        let summary = summaryParts.joined(separator: ", ")
        lastContextSnapshotSummary = summary
        appState.logActivity(.context, "Diagnostics: built context snapshot (\(summary))")
        showStatus("Context snapshot built")
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
            return "Write Only (Limited)"
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
                    // Daily Brief
                    dailyBriefConfigRow

                    Divider()

                    // Reviews (collapsed section)
                    DisclosureGroup("Reviews") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Weekly review (Mondays)", isOn: $weeklyReviewEnabled)
                                .font(.subheadline)
                                .onChange(of: weeklyReviewEnabled) { _, newValue in
                                    savePlanningPreference(key: "weekly_review_enabled", value: newValue ? "true" : "false")
                                }

                            Toggle("Monthly review (1st of month)", isOn: $monthlyReviewEnabled)
                                .font(.subheadline)
                                .onChange(of: monthlyReviewEnabled) { _, newValue in
                                    savePlanningPreference(key: "monthly_review_enabled", value: newValue ? "true" : "false")
                                }
                        }
                        .padding(.top, 4)
                    }
                    .font(.subheadline)

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

            Text("Daily briefs help you start your day with intention.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var dailyBriefConfigRow: some View {
        VStack(spacing: 6) {
            HStack {
                Toggle("", isOn: $morningBriefEnabled)
                    .labelsHidden()
                    .onChange(of: morningBriefEnabled) { _, newValue in
                        savePlanningPreference(key: "morning_brief_enabled", value: newValue ? "true" : "false")
                    }

                Text("Daily Brief")
                    .font(.subheadline)
                    .foregroundColor(morningBriefEnabled ? .primary : .secondary)

                Spacer()

                if morningBriefEnabled {
                    DatePicker("", selection: Binding(
                        get: { Self.makeTimeDate(hour: morningBriefHour, minute: 0) },
                        set: { morningBriefHour = Calendar.current.component(.hour, from: $0) }
                    ), displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .frame(width: 90)
                        .onChange(of: morningBriefHour) { _, newValue in
                            savePlanningPreference(key: "morning_brief_hour", value: String(newValue))
                        }

                    // Notification type picker
                    Picker("", selection: $morningBriefNotificationType) {
                        ForEach(NotificationType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                    .onChange(of: morningBriefNotificationType) { _, newValue in
                        savePlanningPreference(key: "morning_brief_notification_type", value: newValue.rawValue)
                    }
                }
            }
        }
        .padding(8)
        .background(morningBriefEnabled ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .cornerRadius(6)
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
                            appState.refreshConnectionStates()
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
                        appState.refreshConnectionStates()
                    }
                Toggle("Write", isOn: writeEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: writeEnabled.wrappedValue) { _, newValue in
                        savePlanningPreference(key: writeKey, value: newValue ? "true" : "false")
                        logSecurityChange("\(title) write access", enabled: newValue)
                        appState.refreshConnectionStates()
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

    // MARK: - Agent Tasks Section

    private var agentTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agent Tasks", systemImage: "gearshape.2")
                .font(.headline)

            Toggle("Enable background agent tasks", isOn: $agentTasksEnabled)
                .onChange(of: agentTasksEnabled) { _, newValue in
                    savePlanningPreference(key: "agent_tasks_enabled", value: newValue ? "true" : "false")
                }

            if agentTasksEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Agent model")
                            .font(.subheadline)
                        Spacer()
                        Picker("", selection: $agentTaskModel) {
                            Text("Sonnet").tag("sonnet")
                            Text("Opus").tag("opus")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        .onChange(of: agentTaskModel) { _, newValue in
                            savePlanningPreference(key: "agent_task_model", value: newValue)
                        }
                    }

                    Toggle("Email triage sweep (every 30 min)", isOn: $emailSweepEnabled)
                        .font(.subheadline)
                        .onChange(of: emailSweepEnabled) { _, newValue in
                            savePlanningPreference(key: "email_sweep_enabled", value: newValue ? "true" : "false")
                        }
                        .disabled(!emailEnabled)

                    if !emailEnabled && emailSweepEnabled {
                        Text("Enable email integration in Security & Permissions first.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    HStack {
                        Text("Active agent tasks: \(activeAgentTaskCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(.leading, 4)
            }

            Text("Agent tasks run in the background using separate Claude sessions. They power reminders, follow-ups, and scheduled sweeps.")
                .font(.caption)
                .foregroundColor(.secondary)
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

// MARK: - Notification Type

enum NotificationType: String, CaseIterable {
    case notification = "notification"
    case voice = "voice"
    case both = "both"
    case none = "none"

    var displayName: String {
        switch self {
        case .notification: return "Banner"
        case .voice: return "Voice"
        case .both: return "Both"
        case .none: return "None"
        }
    }

    var icon: String {
        switch self {
        case .notification: return "bell"
        case .voice: return "speaker.wave.2"
        case .both: return "bell.and.waves.left.and.right"
        case .none: return "bell.slash"
        }
    }
}
