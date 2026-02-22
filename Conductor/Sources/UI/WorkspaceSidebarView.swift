import SwiftUI

struct WorkspaceSidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchQuery: String = ""

    private var filteredProjects: [ProjectRepository.ProjectSummary] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return appState.projects }
        return appState.projects.filter { summary in
            summary.project.name.localizedCaseInsensitiveContains(trimmed)
            || (summary.project.description?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            navigationSection
            Divider().padding(.top, 8)
            projectsHeader
            searchField
            projectList
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Conductor")
                    .font(.headline)
                Text("Workspace")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                appState.startNewConversation()
                appState.openSurface(.chat, in: .primary)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .help("New Conversation")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(WorkspaceSurface.navigationOrder) { surface in
                navigationRow(surface)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func navigationRow(_ surface: WorkspaceSurface) -> some View {
        let isPrimary = appState.primarySurface == surface
        let isDetached = appState.isSurfaceDetached(surface)

        return Button {
            appState.openSurface(surface, in: .primary)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: surface.icon)
                    .foregroundColor(isPrimary ? .accentColor : .secondary)
                Text(surface.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if isDetached {
                    Text("Window")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.mint.opacity(0.14))
                        .foregroundColor(.mint)
                        .clipShape(Capsule())
                } else if isPrimary {
                    Text("Current")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isPrimary ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open Here") {
                appState.openSurface(surface, in: .primary)
            }
            Divider()
            if isDetached {
                Button("Dock to Main Window") {
                    appState.redockSurface(surface, to: .primary)
                }
            } else {
                Button("Open in Separate Window") {
                    appState.detachSurface(surface)
                }
            }
        }
    }

    private var projectsHeader: some View {
        HStack {
            Text("Projects")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
            Text("\(appState.projects.count)")
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var projectList: some View {
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
                        Button {
                            appState.selectedProjectId = summary.project.id
                            if let projectId = summary.project.id {
                                appState.loadProjectDetail(projectId)
                            }
                            appState.openSurface(.projects, in: .primary)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: summary.project.color) ?? .blue)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.project.name)
                                        .lineLimit(1)
                                    if let description = summary.project.description, !description.isEmpty {
                                        Text(description)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if summary.openTodoCount > 0 {
                                    Text("\(summary.openTodoCount)")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.14))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(appState.selectedProjectId == summary.project.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
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
