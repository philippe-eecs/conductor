import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var blinkIntervalMinutes: Int = 15
    @State private var cliVersion: String = "..."

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    appState.showSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Settings")
                    .font(.headline)
                Spacer()
                // Balance
                Color.clear.frame(width: 60)
            }
            .padding()

            Divider()

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
                    .onChange(of: blinkIntervalMinutes) { newValue in
                        try? appState.prefRepo.setInt("blink_interval_minutes", value: newValue)
                    }
                }

                Section("Permissions") {
                    HStack {
                        Text("Calendar")
                        Spacer()
                        Text(appState.hasCalendarAccess ? "Granted" : "Not Granted")
                            .foregroundColor(appState.hasCalendarAccess ? .green : .secondary)
                    }
                    HStack {
                        Text("Reminders")
                        Spacer()
                        Text(appState.hasRemindersAccess ? "Granted" : "Not Granted")
                            .foregroundColor(appState.hasRemindersAccess ? .green : .secondary)
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
            Task {
                cliVersion = await ClaudeService.shared.getCLIVersion() ?? "Unknown"
            }
        }
    }
}
