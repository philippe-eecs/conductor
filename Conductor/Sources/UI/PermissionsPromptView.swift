import SwiftUI

struct PermissionsPromptView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions Needed")
                    .font(.title3.weight(.semibold))
                Text("Conductor works best with Calendar, Reminders, and Contacts access.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 10) {
                permissionRow(
                    title: "Calendar",
                    subtitle: "Show your schedule and weekly plan.",
                    granted: appState.hasCalendarAccess
                ) {
                    Task {
                        _ = await EventKitManager.shared.requestCalendarAccess()
                        appState.checkPermissions()
                    }
                }

                permissionRow(
                    title: "Reminders",
                    subtitle: "Track tasks and due dates.",
                    granted: appState.hasRemindersAccess
                ) {
                    Task {
                        _ = await EventKitManager.shared.requestRemindersAccess()
                        appState.checkPermissions()
                    }
                }

                permissionRow(
                    title: "Contacts",
                    subtitle: "Find people and schedule meetings faster.",
                    granted: ContactsManager.shared.contactsAuthorizationStatus() == .authorized
                ) {
                    Task {
                        _ = await ContactsManager.shared.requestContactsAccess()
                    }
                }
            }

            HStack {
                Button("Not Now") {
                    appState.showPermissionsPrompt = false
                }
                .buttonStyle(.bordered)

                Spacer()

                if appState.hasCalendarAccess
                    && appState.hasRemindersAccess
                    && ContactsManager.shared.contactsAuthorizationStatus() == .authorized {
                    Button("Done") {
                        appState.showPermissionsPrompt = false
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Grant All") {
                        Task {
                            if !appState.hasCalendarAccess {
                                _ = await EventKitManager.shared.requestCalendarAccess()
                            }
                            if !appState.hasRemindersAccess {
                                _ = await EventKitManager.shared.requestRemindersAccess()
                            }
                            if ContactsManager.shared.contactsAuthorizationStatus() != .authorized {
                                _ = await ContactsManager.shared.requestContactsAccess()
                            }
                            appState.checkPermissions()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : .secondary)
                .font(.title3)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if granted {
                Text("Granted")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.green)
            } else {
                Button("Grant", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
