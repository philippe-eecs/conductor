import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchQuery: String = ""

    private var totalOpenTodos: Int {
        appState.projects.reduce(0) { $0 + $1.openTodoCount }
    }

    private var orderedProjects: [ProjectRepository.ProjectSummary] {
        appState.projects.sorted {
            if $0.openTodoCount == $1.openTodoCount {
                return $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending
            }
            return $0.openTodoCount > $1.openTodoCount
        }
    }

    private var filteredProjects: [ProjectRepository.ProjectSummary] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return orderedProjects }

        return orderedProjects.filter { summary in
            summary.project.name.localizedCaseInsensitiveContains(trimmed)
                || (summary.project.description?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            Divider()

            workspaceSection

            Divider()
                .padding(.top, 8)

            projectsSectionHeader
            searchField

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if filteredProjects.isEmpty {
                        Text(searchQuery.isEmpty ? "No projects yet" : "No matching projects")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                    } else {
                        ForEach(filteredProjects, id: \.project.id) { summary in
                            projectRow(summary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }

            Spacer(minLength: 0)

            Divider()

            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebarHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Workspace")
                    .font(.headline)
                Text("\(appState.projects.count) projects")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                appState.startNewConversation()
            } label: {
                Image(systemName: "plus.bubble")
            }
            .buttonStyle(.plain)
            .help("New Conversation")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sidebarRow(
                title: "Chat",
                subtitle: "Main conversation",
                icon: "bubble.left.and.bubble.right",
                badge: nil,
                isSelected: appState.selectedProjectId == nil,
                action: { appState.selectedProjectId = nil }
            )

            sidebarRow(
                title: "Today",
                subtitle: "Calendar and due todos",
                icon: appState.showTodayPanel ? "calendar.circle.fill" : "calendar.circle",
                badge: appState.todayEvents.count,
                isSelected: appState.showTodayPanel,
                action: { appState.showTodayPanel.toggle() }
            )
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var projectsSectionHeader: some View {
        HStack {
            Text("Projects")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
            Text("\(totalOpenTodos) open todos")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)

            TextField("Filter projects", text: $searchQuery)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func projectRow(_ summary: ProjectRepository.ProjectSummary) -> some View {
        Button {
            appState.selectedProjectId = summary.project.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: summary.project.color) ?? .blue)
                        .frame(width: 8, height: 8)

                    Text(summary.project.name)
                        .lineLimit(1)

                    Spacer()

                    if summary.openTodoCount > 0 {
                        Text("\(summary.openTodoCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if summary.totalDeliverables > 0 {
                        Label("\(summary.totalDeliverables)", systemImage: "doc")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let description = summary.project.description, !description.isEmpty {
                        Text(description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(appState.selectedProjectId == summary.project.id ? Color.accentColor.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func sidebarRow(
        title: String,
        subtitle: String,
        icon: String,
        badge: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Button {
            appState.showSettings = true
        } label: {
            HStack {
                Image(systemName: "gearshape")
                Text("Settings")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
