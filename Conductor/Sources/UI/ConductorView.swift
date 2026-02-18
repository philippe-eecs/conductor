import SwiftUI

struct ConductorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.showSetup {
                SetupView()
            } else if appState.showSettings {
                SettingsView()
            } else {
                HSplitView {
                    ProjectListView()
                        .frame(minWidth: 180, maxWidth: 220)

                    VStack(spacing: 0) {
                        ChatView()
                        InputBar()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
