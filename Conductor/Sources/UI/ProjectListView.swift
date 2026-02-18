import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Projects")
                    .font(.headline)
                Spacer()
                Button {
                    // New conversation
                    appState.startNewConversation()
                } label: {
                    Image(systemName: "plus.message")
                }
                .buttonStyle(.plain)
                .help("New Conversation")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Inbox
            Button {
                appState.selectedProjectId = nil
            } label: {
                HStack {
                    Image(systemName: "tray")
                        .foregroundColor(.secondary)
                    Text("Inbox")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(appState.selectedProjectId == nil ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            // Project list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(appState.projects, id: \.project.id) { summary in
                        Button {
                            appState.selectedProjectId = summary.project.id
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: summary.project.color) ?? .blue)
                                    .frame(width: 8, height: 8)

                                Text(summary.project.name)
                                    .lineLimit(1)

                                Spacer()

                                if summary.openTodoCount > 0 {
                                    Text("\(summary.openTodoCount)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(appState.selectedProjectId == summary.project.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }

            Spacer()

            Divider()

            // Settings button
            Button {
                appState.showSettings = true
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Color hex helper

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
