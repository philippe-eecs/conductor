import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject var appState: AppState
    let projectId: Int64

    @State private var quickAddTitle: String = ""
    @State private var quickAddPriority: Int = 0
    @State private var showCompleted: Bool = false

    private var project: Project? {
        appState.projects.first(where: { $0.project.id == projectId })?.project
    }

    private var openTodos: [Todo] {
        appState.selectedProjectTodos.filter { !$0.completed }
    }

    private var completedTodos: [Todo] {
        appState.selectedProjectTodos.filter(\.completed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let project {
                projectHeader(project)
                Divider()
            }

            quickAddBar

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if openTodos.isEmpty && completedTodos.isEmpty {
                        emptyState
                    } else {
                        sectionTitle("Open Todos")
                            .padding(.top, 8)

                        ForEach(openTodos, id: \.id) { todo in
                            TodoRowView(
                                todo: todo,
                                projectColor: nil,
                                onToggle: { appState.toggleTodoCompletion(todo.id!) },
                                onSelect: { appState.selectTodo(todo.id) },
                                isSelected: appState.selectedTodoId == todo.id
                            )
                            Divider().padding(.leading, 36)
                        }
                    }

                    if !completedTodos.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCompleted.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                Text("Completed (\(completedTodos.count))")
                                    .font(.caption.weight(.medium))
                                Spacer()
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showCompleted {
                            ForEach(completedTodos, id: \.id) { todo in
                                TodoRowView(
                                    todo: todo,
                                    projectColor: nil,
                                    onToggle: { appState.toggleTodoCompletion(todo.id!) },
                                    onSelect: { appState.selectTodo(todo.id) },
                                    isSelected: appState.selectedTodoId == todo.id
                                )
                                Divider().padding(.leading, 36)
                            }
                        }
                    }

                    if !appState.selectedProjectDeliverables.isEmpty {
                        Divider().padding(.vertical, 8)

                        sectionTitle("Deliverables")

                        ForEach(appState.selectedProjectDeliverables, id: \.id) { deliverable in
                            deliverableRow(deliverable)
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            appState.loadProjectDetail(projectId)
        }
        .onChange(of: projectId) { _, newId in
            appState.loadProjectDetail(newId)
        }
    }

    private func projectHeader(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: project.color) ?? .blue)
                    .frame(width: 12, height: 12)

                Text(project.name)
                    .font(.headline)

                Spacer()
            }

            if let desc = project.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                Label("\(openTodos.count) open", systemImage: "circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Label("\(completedTodos.count) done", systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if !appState.selectedProjectDeliverables.isEmpty {
                    Label("\(appState.selectedProjectDeliverables.count)", systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var quickAddBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundColor(.secondary)

            TextField("Add a TODO", text: $quickAddTitle)
                .textFieldStyle(.plain)
                .onSubmit {
                    submitQuickAdd()
                }

            Picker("Priority", selection: $quickAddPriority) {
                Text("None").tag(0)
                Text("Low").tag(1)
                Text("Med").tag(2)
                Text("High").tag(3)
            }
            .pickerStyle(.menu)
            .frame(width: 72)

            Button("Add") {
                submitQuickAdd()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No TODOs yet")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Add one above or ask Conductor")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    private func submitQuickAdd() {
        let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        appState.quickAddTodo(title: title, priority: quickAddPriority)
        quickAddTitle = ""
        quickAddPriority = 0
        appState.loadProjectDetail(projectId)
    }

    private func deliverableRow(_ deliverable: Deliverable) -> some View {
        HStack(spacing: 8) {
            Image(systemName: deliverableIcon(deliverable.kind))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(deliverable.filePath ?? deliverable.url ?? deliverable.kind.rawValue)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if deliverable.verified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
