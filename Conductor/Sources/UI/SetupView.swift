import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Welcome to Conductor")
                .font(.title)

            Text("Conductor needs Claude Code CLI to work.\nInstall it from claude.ai/download")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: appState.isCliAvailable ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(appState.isCliAvailable ? .green : .red)
                    Text("Claude CLI")
                    Spacer()
                    if !appState.isCliAvailable {
                        Text("Not found")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Image(systemName: appState.hasCalendarAccess ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(appState.hasCalendarAccess ? .green : .secondary)
                    Text("Calendar Access")
                    Spacer()
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
                    Image(systemName: appState.hasRemindersAccess ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(appState.hasRemindersAccess ? .green : .secondary)
                    Text("Reminders Access")
                    Spacer()
                    if !appState.hasRemindersAccess {
                        Button("Grant") {
                            Task {
                                _ = await EventKitManager.shared.requestRemindersAccess()
                                appState.checkPermissions()
                            }
                        }
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            Button("Retry") {
                appState.checkPermissions()
            }

            if appState.isCliAvailable {
                Button("Continue") {
                    appState.showSetup = false
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
