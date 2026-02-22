import SwiftUI

struct ConductorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.showSetup {
                SetupView()
            } else {
                workspaceShell
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { keyboardShortcuts }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .frame(width: 420, height: 400)
        }
        .sheet(isPresented: $appState.showPermissionsPrompt) {
            PermissionsPromptView()
        }
    }

    private var workspaceShell: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                WorkspaceSidebarView()
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 300)

                WorkspacePaneView(
                    surface: appState.primarySurface,
                    role: .primary,
                    isDetached: false,
                    showsCloseButton: false
                )
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Conductor")
                .font(.headline)

            Text(appState.primarySurface.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())

            Spacer()

            if appState.mailConnectionStatus == .connected, appState.unreadEmailCount > 0 {
                Button {
                    appState.openSurface(.email, in: .primary)
                } label: {
                    Label("\(appState.unreadEmailCount) unread", systemImage: "envelope.badge")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Open Email")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("") { appState.openSurface(.dashboard) }
                .keyboardShortcut("1", modifiers: .command)

            Button("") { appState.openSurface(.calendar) }
                .keyboardShortcut("2", modifiers: .command)

            Button("") { appState.openSurface(.tasks) }
                .keyboardShortcut("3", modifiers: .command)

            Button("") { appState.openSurface(.chat) }
                .keyboardShortcut("4", modifiers: .command)

            Button("") { appState.openSurface(.projects) }
                .keyboardShortcut("5", modifiers: .command)

            Button("") { appState.openSurface(.email) }
                .keyboardShortcut("6", modifiers: .command)

            Button("") {
                appState.startNewConversation()
                appState.openSurface(.chat, in: .primary)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("") { appState.showSettings = true }
                .keyboardShortcut(",", modifiers: .command)

            Button("") { handleEscape() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func handleEscape() {
        if appState.showSettings {
            appState.showSettings = false
            return
        }

        if appState.selectedTodoId != nil {
            appState.selectTodo(nil)
            return
        }

        if appState.selectedProjectId != nil {
            appState.selectedProjectId = nil
        }
    }
}
