import SwiftUI
import AppKit

struct TaskDetailView: View {
    @EnvironmentObject var appState: AppState
    let todoId: Int64

    private var todo: Todo? {
        appState.selectedTodo?.id == todoId ? appState.selectedTodo : nil
    }

    private var projectName: String {
        guard let projectId = todo?.projectId else { return "Inbox" }
        return appState.projects.first(where: { $0.project.id == projectId })?.project.name ?? "Project \(projectId)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let todo {
                header(todo)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        metadataSection(todo)
                        attachmentsSection
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            } else {
                emptyState
            }
        }
        .onAppear {
            appState.loadTodoDetail(todoId)
        }
        .onChange(of: todoId) { _, newId in
            appState.loadTodoDetail(newId)
        }
    }

    private func header(_ todo: Todo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if let id = todo.id {
                        appState.toggleTodoCompletion(id)
                    }
                } label: {
                    Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(todo.completed ? .green : .secondary)
                }
                .buttonStyle(.plain)

                Text(todo.title)
                    .font(.headline)
                    .strikethrough(todo.completed)
                    .foregroundColor(todo.completed ? .secondary : .primary)

                Spacer()
            }

            HStack(spacing: 8) {
                Text(projectName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.14))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())

                Text(todo.completed ? "Completed" : "Open")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((todo.completed ? Color.green : Color.secondary).opacity(0.14))
                    .foregroundColor(todo.completed ? .green : .secondary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func metadataSection(_ todo: Todo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Details")

            detailRow("Priority", priorityText(todo.priority))
            detailRow("Due", dueDateText(todo.dueDate))
            detailRow("Created", SharedDateFormatters.mediumDateTime.string(from: todo.createdAt))
            detailRow("Updated", SharedDateFormatters.mediumDateTime.string(from: todo.updatedAt))
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Attached Deliverables")

            if appState.selectedTodoDeliverables.isEmpty {
                Text("No attachments yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(appState.selectedTodoDeliverables, id: \.id) { deliverable in
                    attachmentRow(deliverable)
                }
            }
        }
    }

    private func attachmentRow(_ deliverable: Deliverable) -> some View {
        HStack(spacing: 8) {
            Image(systemName: deliverableIcon(deliverable.kind))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(attachmentName(deliverable))
                    .font(.caption)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(deliverable.kind.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())

                    if deliverable.verified {
                        Text("Verified")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer()

            if canOpen(deliverable) {
                Button("Open") {
                    openDeliverable(deliverable)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No task selected")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Select a task to inspect its details.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.caption)
            Spacer()
        }
    }

    private func priorityText(_ priority: Int) -> String {
        switch priority {
        case 3: return "High"
        case 2: return "Medium"
        case 1: return "Low"
        default: return "None"
        }
    }

    private func dueDateText(_ date: Date?) -> String {
        guard let date else { return "Not set" }
        return SharedDateFormatters.mediumDateTime.string(from: date)
    }

    private func attachmentName(_ deliverable: Deliverable) -> String {
        deliverable.filePath ?? deliverable.url ?? "Attachment"
    }

    private func canOpen(_ deliverable: Deliverable) -> Bool {
        deliverable.url != nil || deliverable.filePath != nil
    }

    private func openDeliverable(_ deliverable: Deliverable) {
        if let urlString = deliverable.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return
        }

        guard let filePath = deliverable.filePath else { return }
        let expandedPath = (filePath as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath))
    }

    private func deliverableIcon(_ kind: DeliverableKind) -> String {
        switch kind {
        case .pdf: return "doc.richtext"
        case .pr: return "arrow.triangle.pull"
        case .markdown: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc"
        }
    }
}
