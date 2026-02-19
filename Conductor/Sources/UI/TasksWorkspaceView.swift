import SwiftUI

private enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case week = "This Week"
    case noDate = "No Date"

    var id: String { rawValue }
}

struct TasksWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @State private var filter: TaskFilter = .all

    private var visibleTodos: [Todo] {
        let today = Calendar.current.startOfDay(for: Date())
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today

        return appState.openTodos.filter { todo in
            switch filter {
            case .all:
                return true
            case .today:
                guard let due = todo.dueDate else { return false }
                return Calendar.current.isDateInToday(due)
            case .week:
                guard let due = todo.dueDate else { return false }
                return due >= today && due < weekEnd
            case .noDate:
                return todo.dueDate == nil
            }
        }
    }

    var body: some View {
        HSplitView {
            taskList
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

            if let todoId = appState.selectedTodoId {
                TaskDetailView(todoId: todoId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyDetail
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Open Tasks")
                    .font(.headline)
                Spacer()
                Text("\(visibleTodos.count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Picker("Filter", selection: $filter) {
                ForEach(TaskFilter.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if visibleTodos.isEmpty {
                        Text("No tasks in this filter.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(12)
                    } else {
                        ForEach(visibleTodos, id: \.id) { todo in
                            TodoRowView(
                                todo: todo,
                                projectColor: projectColor(for: todo.projectId),
                                onToggle: { appState.toggleTodoCompletion(todo.id!) },
                                onSelect: { appState.selectTodo(todo.id) },
                                isSelected: appState.selectedTodoId == todo.id
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Select a task")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Choose a task from the list to see details and attachments.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func projectColor(for projectId: Int64?) -> String? {
        guard let projectId else { return nil }
        return appState.projects.first(where: { $0.project.id == projectId })?.project.color
    }
}
