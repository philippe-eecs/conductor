import SwiftUI

struct WorkspacePaneView: View {
    @EnvironmentObject var appState: AppState

    let surface: WorkspaceSurface
    let role: WorkspaceDockTarget?
    let isDetached: Bool
    let showsCloseButton: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            WorkspaceSurfaceContentView(surface: surface)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(surface.title, systemImage: surface.icon)
                .font(.subheadline.weight(.semibold))

            Spacer()

            if isDetached {
                Button("Dock Left") {
                    appState.redockSurface(surface, to: .primary)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button("Dock Right") {
                    appState.redockSurface(surface, to: .secondary)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            } else {
                Menu {
                    if role != .primary {
                        Button("Move to Left Pane") {
                            appState.openSurface(surface, in: .primary)
                        }
                    }
                    if role != .secondary {
                        Button("Move to Right Pane") {
                            appState.openSurface(surface, in: .secondary)
                        }
                    }
                    Divider()
                    Button("Open in Separate Window") {
                        appState.detachSurface(surface)
                    }
                    if showsCloseButton {
                        Divider()
                        Button("Close Right Pane") {
                            appState.clearSecondaryPane()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Pane Actions")

                Button {
                    appState.detachSurface(surface)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Open in Separate Window")

                if showsCloseButton {
                    Button {
                        appState.clearSecondaryPane()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Close Right Pane")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct WorkspaceSurfaceContentView: View {
    let surface: WorkspaceSurface

    var body: some View {
        Group {
            switch surface {
            case .dashboard:
                DashboardView()
            case .calendar:
                CalendarWorkspaceView()
            case .tasks:
                TasksWorkspaceView()
            case .chat:
                VStack(spacing: 0) {
                    ChatView()
                    InputBar()
                }
                .background(Color(nsColor: .textBackgroundColor))
            case .projects:
                ProjectsWorkspaceView()
            }
        }
    }
}

struct DetachedSurfaceWindowView: View {
    let surface: WorkspaceSurface

    var body: some View {
        WorkspacePaneView(
            surface: surface,
            role: nil,
            isDetached: true,
            showsCloseButton: false
        )
    }
}
