import SwiftUI

struct ProjectsWorkspaceView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let projectId = appState.selectedProjectId {
                ProjectDetailView(projectId: projectId)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                projectOverview
            }
        }
    }

    private var projectOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Projects")
                    .font(.title3.weight(.semibold))
                    .padding(.bottom, 2)

                if appState.projects.isEmpty {
                    Text("No projects yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appState.projects, id: \.project.id) { summary in
                        Button {
                            appState.selectedProjectId = summary.project.id
                            if let id = summary.project.id {
                                appState.loadProjectDetail(id)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: summary.project.color) ?? .blue)
                                        .frame(width: 9, height: 9)
                                    Text(summary.project.name)
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("\(summary.openTodoCount) open")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if let description = summary.project.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                HStack(spacing: 8) {
                                    Label("\(summary.openTodoCount)", systemImage: "checklist")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Label("\(summary.totalDeliverables)", systemImage: "doc")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
