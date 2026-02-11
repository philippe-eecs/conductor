import SwiftUI
import AppKit

struct SetupView: View {
    let onComplete: () -> Void

    @State private var currentStep: SetupStep = .welcome
    @State private var cliAvailable: Bool = false
    @State private var cliVersion: String?
    @State private var calendarStatus: EventKitManager.AuthorizationStatus = .notDetermined
    @State private var remindersStatus: EventKitManager.AuthorizationStatus = .notDetermined
    @State private var isCheckingCLI: Bool = false
    @State private var didAutoRequestCalendar: Bool = false
    @State private var didAutoRequestReminders: Bool = false
    @State private var showRunAsAppHelp: Bool = false

    enum SetupStep: Int, CaseIterable {
        case welcome
        case claudeCLI
        case calendarAccess
        case remindersAccess
        case complete

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .claudeCLI: return "Claude CLI"
            case .calendarAccess: return "Calendar"
            case .remindersAccess: return "Reminders"
            case .complete: return "Complete"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
                .padding(.top, 20)
                .padding(.bottom, 10)

            Divider()

            // Step content
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            navigationButtons
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            refreshStatuses()
        }
        .task(id: currentStep) {
            await autoRequestPermissionsIfNeeded()
        }
        .sheet(isPresented: $showRunAsAppHelp) {
            runAsAppHelpSheet
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(SetupStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeStep
        case .claudeCLI:
            claudeCLIStep
        case .calendarAccess:
            calendarStep
        case .remindersAccess:
            remindersStep
        case .complete:
            completeStep
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Welcome to Conductor")
                .font(.title)
                .fontWeight(.semibold)

            Text("Your AI-powered personal assistant that helps you manage your day, schedule, and tasks.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "calendar", text: "Access your calendar and schedule")
                featureRow(icon: "checklist", text: "Manage reminders and tasks")
                featureRow(icon: "brain", text: "Powered by Claude Code")
            }
            .padding(.top, 16)
        }
        .padding()
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.callout)
        }
    }

    // MARK: - Claude CLI Step

    private var claudeCLIStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(cliAvailable ? .green : .orange)

            Text("Claude Code CLI")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Conductor requires Claude Code to be installed. It uses your Claude Code Max subscription.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Status indicator
            HStack(spacing: 12) {
                if isCheckingCLI {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: cliAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(cliAvailable ? .green : .red)
                        .font(.title2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(cliAvailable ? "Claude CLI Found" : "Claude CLI Not Found")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let version = cliVersion {
                        Text(version)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            if !cliAvailable {
                VStack(spacing: 12) {
                    Link("Install Claude Code", destination: URL(string: "https://claude.ai/code")!)
                        .buttonStyle(.borderedProminent)

                    Button("Check Again") {
                        checkCLIStatus()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
    }

    // MARK: - Calendar Step

    private var calendarStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundColor((calendarStatus == .fullAccess || calendarStatus == .writeOnly) ? .green : .accentColor)

            Text("Calendar Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Allow Conductor to access your calendar so it can help you manage your schedule and provide context-aware assistance.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            permissionStatusView(
                label: "Calendar",
                status: calendarStatus,
                onRequest: { Task { _ = await requestCalendarAccess() } },
                systemSettingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
            )
        }
        .padding()
    }

    // MARK: - Reminders Step

    private var remindersStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundColor((remindersStatus == .fullAccess || remindersStatus == .writeOnly) ? .green : .accentColor)

            Text("Reminders Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Allow Conductor to access your reminders so it can help you create and manage tasks.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            permissionStatusView(
                label: "Reminders",
                status: remindersStatus,
                onRequest: { Task { _ = await requestRemindersAccess() } },
                systemSettingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
            )
        }
        .padding()
    }

    // MARK: - Complete Step

    private var completeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.semibold)

            Text("Conductor is ready to help you manage your day.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Summary
            VStack(alignment: .leading, spacing: 12) {
                summaryRow(
                    icon: "terminal",
                    label: "Claude CLI",
                    status: cliAvailable ? "Connected" : "Not available",
                    isEnabled: cliAvailable
                )
                summaryRow(
                    icon: "calendar",
                    label: "Calendar",
                    status: statusText(calendarStatus),
                    isEnabled: calendarStatus == .fullAccess
                )
                summaryRow(
                    icon: "checklist",
                    label: "Reminders",
                    status: statusText(remindersStatus),
                    isEnabled: remindersStatus == .fullAccess
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
    }

    private func summaryRow(icon: String, label: String, status: String, isEnabled: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(label)
                .font(.callout)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(isEnabled ? .green : .orange)
                    .font(.caption)
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Permission Status View

    private func permissionStatusView(
        label: String,
        status: EventKitManager.AuthorizationStatus,
        onRequest: @escaping () -> Void,
        systemSettingsURL: String
    ) -> some View {
        VStack(spacing: 16) {
            // Status indicator
            HStack(spacing: 12) {
                Image(systemName: statusIcon(status))
                    .foregroundColor(statusColor(status))
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(label) Access")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(statusText(status))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Action buttons
            if status == .notDetermined {
                if RuntimeEnvironment.supportsTCCPrompts {
                    Button("Grant \(label) Access") {
                        onRequest()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    VStack(spacing: 8) {
                        Text("Permissions require running Conductor as a .app bundle (not swift run).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 10) {
                            Button("Grant \(label) Access") {}
                                .buttonStyle(.borderedProminent)
                                .disabled(true)

                            Button("How to run as .app") {
                                showRunAsAppHelp = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else if status == .denied || status == .restricted {
                VStack(spacing: 8) {
                    Text("Permission was denied. You can enable it in System Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Open System Settings") {
                        if let url = URL(string: systemSettingsURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if status == .writeOnly {
                Text("Write-only access allows creating items but not reading your schedule/tasks. For schedule/context features, grant full access.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep != .welcome {
                Button("Back") {
                    withAnimation {
                        goToPreviousStep()
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep == .complete {
                Button("Start Using Conductor") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
            } else if currentStep == .calendarAccess || currentStep == .remindersAccess {
                HStack(spacing: 12) {
                    Button("Skip") {
                        withAnimation {
                            goToNextStep()
                        }
                    }
                    .buttonStyle(.bordered)

                    if (currentStep == .calendarAccess && (calendarStatus == .fullAccess || calendarStatus == .writeOnly)) ||
                       (currentStep == .remindersAccess && (remindersStatus == .fullAccess || remindersStatus == .writeOnly)) {
                        Button("Continue") {
                            withAnimation {
                                goToNextStep()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if currentStep == .claudeCLI {
                Button(cliAvailable ? "Continue" : "Continue Anyway") {
                    withAnimation {
                        goToNextStep()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") {
                    withAnimation {
                        goToNextStep()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

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
            return "Write Only (Limited)"
        case .notDetermined:
            return "Not Requested"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }

    private func goToNextStep() {
        if let nextIndex = SetupStep.allCases.firstIndex(of: currentStep).map({ $0 + 1 }),
           nextIndex < SetupStep.allCases.count {
            currentStep = SetupStep.allCases[nextIndex]
            refreshStatuses()
        }
    }

    private func goToPreviousStep() {
        if let prevIndex = SetupStep.allCases.firstIndex(of: currentStep).map({ $0 - 1 }),
           prevIndex >= 0 {
            currentStep = SetupStep.allCases[prevIndex]
        }
    }

    private func refreshStatuses() {
        calendarStatus = EventKitManager.shared.calendarAuthorizationStatus()
        remindersStatus = EventKitManager.shared.remindersAuthorizationStatus()

        if currentStep == .claudeCLI {
            checkCLIStatus()
        }
    }

    private func checkCLIStatus() {
        isCheckingCLI = true
        Task {
            let available = await ClaudeService.shared.checkCLIAvailable()
            let version = await ClaudeService.shared.getCLIVersion()

            await MainActor.run {
                cliAvailable = available
                cliVersion = version
                isCheckingCLI = false
            }
        }
    }

    @MainActor
    private func requestCalendarAccess() async -> Bool {
        let granted = await EventKitManager.shared.requestCalendarAccess()
        calendarStatus = EventKitManager.shared.calendarAuthorizationStatus()
        if granted {
            try? Database.shared.setPreference(key: "calendar_read_enabled", value: "true")
        }
        return granted
    }

    @MainActor
    private func requestRemindersAccess() async -> Bool {
        let granted = await EventKitManager.shared.requestRemindersAccess()
        remindersStatus = EventKitManager.shared.remindersAuthorizationStatus()
        if granted {
            try? Database.shared.setPreference(key: "reminders_read_enabled", value: "true")
        }
        return granted
    }

    @MainActor
    private func autoRequestPermissionsIfNeeded() async {
        guard RuntimeEnvironment.supportsTCCPrompts else { return }

        switch currentStep {
        case .calendarAccess:
            guard calendarStatus == .notDetermined, !didAutoRequestCalendar else { return }
            didAutoRequestCalendar = true
            _ = await requestCalendarAccess()
        case .remindersAccess:
            guard remindersStatus == .notDetermined, !didAutoRequestReminders else { return }
            didAutoRequestReminders = true
            _ = await requestRemindersAccess()
        default:
            break
        }
    }

    private var runAsAppHelpSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Testing Permissions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("macOS Calendar/Reminders permission prompts require Conductor to run as a real .app bundle. Launching with swift run can't show these prompts and may crash system frameworks.")
                .font(.body)
                .foregroundColor(.secondary)

            Text("Run:")
                .font(.headline)

            Text("scripts/dev-run-app.sh")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

            Spacer()

            HStack {
                Spacer()
                Button("Close") { showRunAsAppHelp = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
