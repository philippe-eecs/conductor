import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var blinkIntervalMinutes: Int = 15
    @State private var cliVersion: String = "..."
    @State private var autoOpenMailOnLaunch: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Claude CLI") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(appState.isCliAvailable ? "Available" : "Not Found")
                            .foregroundColor(appState.isCliAvailable ? .green : .red)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(cliVersion)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Blink Engine") {
                    Picker("Interval", selection: $blinkIntervalMinutes) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("60 min").tag(60)
                    }
                    .onChange(of: blinkIntervalMinutes) { _, newValue in
                        try? appState.prefRepo.setInt("blink_interval_minutes", value: newValue)
                    }
                }

                Section("Email") {
                    HStack {
                        Text("Mail")
                        Spacer()
                        Text(mailStatusText)
                            .foregroundColor(mailStatusColor)
                    }

                    if appState.mailConnectionStatus == .connected {
                        HStack {
                            Text("Unread")
                            Spacer()
                            Text("\(appState.unreadEmailCount)")
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("Auto-open Mail on launch", isOn: $autoOpenMailOnLaunch)
                        .onChange(of: autoOpenMailOnLaunch) { _, newValue in
                            try? appState.prefRepo.setInt("mail_auto_open_on_launch", value: newValue ? 1 : 0)
                        }

                    HStack {
                        Button("Connect Mail") {
                            Task {
                                _ = await MailService.shared.connectToMailApp()
                                await appState.refreshMailStatus()
                            }
                        }

                        Button("Refresh Status") {
                            Task { await appState.refreshMailStatus() }
                        }
                    }
                }

                Section("Permissions") {
                    HStack {
                        Text("Calendar")
                        Spacer()
                        Text(appState.hasCalendarAccess ? "Granted" : "Not Granted")
                            .foregroundColor(appState.hasCalendarAccess ? .green : .secondary)
                        if !appState.hasCalendarAccess {
                            Button("Grant") {
                                Task {
                                    _ = await EventKitManager.shared.requestCalendarAccess()
                                    appState.checkPermissions()
                                }
                            }
                        }
                    }
                    HStack {
                        Text("Reminders")
                        Spacer()
                        Text(appState.hasRemindersAccess ? "Granted" : "Not Granted")
                            .foregroundColor(appState.hasRemindersAccess ? .green : .secondary)
                        if !appState.hasRemindersAccess {
                            Button("Grant") {
                                Task {
                                    _ = await EventKitManager.shared.requestRemindersAccess()
                                    appState.checkPermissions()
                                }
                            }
                        }
                    }
                    HStack {
                        Text("Contacts")
                        Spacer()
                        Text(contactsStatusText)
                            .foregroundColor(contactsStatusColor)
                        if ContactsManager.shared.contactsAuthorizationStatus() != .authorized {
                            Button("Grant") {
                                Task {
                                    _ = await ContactsManager.shared.requestContactsAccess()
                                }
                            }
                        }
                    }
                    Button("Open Permission Window") {
                        appState.showPermissionsPrompt = true
                    }
                }

                Section("About") {
                    HStack {
                        Text("Conductor")
                        Spacer()
                        Text("v2.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            blinkIntervalMinutes = (try? appState.prefRepo.getInt("blink_interval_minutes", default: 15)) ?? 15
            autoOpenMailOnLaunch = ((try? appState.prefRepo.getInt("mail_auto_open_on_launch", default: 0)) ?? 0) == 1
            Task {
                cliVersion = await ClaudeService.shared.getCLIVersion() ?? "Unknown"
                await appState.refreshMailStatus()
            }
        }
    }

    private var mailStatusText: String {
        switch appState.mailConnectionStatus {
        case .connected:
            return "Connected"
        case .noAccess:
            return "No Access"
        case .notRunning:
            return "Not Running"
        }
    }

    private var mailStatusColor: Color {
        switch appState.mailConnectionStatus {
        case .connected:
            return .green
        case .noAccess:
            return .orange
        case .notRunning:
            return .secondary
        }
    }

    private var contactsStatusText: String {
        switch ContactsManager.shared.contactsAuthorizationStatus() {
        case .authorized:
            return "Granted"
        case .notDetermined:
            return "Not Granted"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }

    private var contactsStatusColor: Color {
        switch ContactsManager.shared.contactsAuthorizationStatus() {
        case .authorized:
            return .green
        case .notDetermined:
            return .secondary
        case .denied, .restricted:
            return .orange
        }
    }
}
