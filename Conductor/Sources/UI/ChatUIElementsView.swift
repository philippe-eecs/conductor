import SwiftUI

struct ChatUIElementsView: View {
    let elements: [ChatUIElement]
    let onAction: (ChatAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(elements) { element in
                switch element {
                case .operationReceipt(let data):
                    OperationReceiptCard(data: data, onAction: onAction)
                case .todaySchedule(let data):
                    TodayScheduleCard(data: data)
                case .weekBlocks(let data):
                    WeekBlocksCard(data: data)
                case .projectSnapshot(let data):
                    ProjectSnapshotCard(data: data, onAction: onAction)
                case .todoList(let data):
                    TodoListCard(data: data, onAction: onAction)
                }
            }
        }
    }
}

// MARK: - Operation Receipt Card

struct OperationReceiptCard: View {
    let data: OperationReceiptData
    let onAction: (ChatAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(data.entityName)
                    .font(.callout.weight(.medium))

                HStack(spacing: 6) {
                    Text("\(data.entityType.capitalized) \(data.operation.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let projectName = data.projectName {
                        Text(projectName)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(3)
                    }

                    if let priority = data.priority, priority > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text("P\(priority)")
                                .font(.caption2)
                        }
                        .foregroundColor(priority >= 3 ? .red : priority >= 2 ? .orange : .secondary)
                    }

                    if let due = data.dueDate {
                        Text(SharedDateFormatters.shortMonthDay.string(from: due))
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(dueDateColor(due).opacity(0.12))
                            .foregroundColor(dueDateColor(due))
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()

            if data.status == .pending, let entityId = data.entityId {
                HStack(spacing: 6) {
                    Button {
                        onAction(.confirmReceipt(receiptId: data.id))
                    } label: {
                        Text("OK")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAction(.undoReceipt(receiptId: data.id, entityType: data.entityType, entityId: entityId))
                    } label: {
                        Text("Undo")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            } else if data.status == .confirmed {
                Text("Confirmed")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if data.status == .undone {
                Text("Undone")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }

    private var statusIcon: String {
        switch data.status {
        case .pending: return data.operation == .created ? "plus.circle.fill" : "pencil.circle.fill"
        case .confirmed: return "checkmark.circle.fill"
        case .undone: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch data.status {
        case .pending: return .orange
        case .confirmed: return .green
        case .undone: return .red
        }
    }

    private func dueDateColor(_ date: Date) -> Color {
        let today = Calendar.current.startOfDay(for: Date())
        if date < today { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return .secondary
    }
}

// MARK: - Today Schedule Card

struct TodayScheduleCard: View {
    let data: TodayScheduleData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.accentColor)
                Text(SharedDateFormatters.shortDayDate.string(from: data.date))
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(data.events.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let allDay = data.events.filter(\.isAllDay)
            let timed = data.events.filter { !$0.isAllDay }

            if !allDay.isEmpty {
                ForEach(allDay) { event in
                    HStack(spacing: 6) {
                        Text("All day")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)
                        Text(event.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }

            ForEach(timed) { event in
                HStack(spacing: 6) {
                    Text(SharedDateFormatters.shortTime.string(from: event.startDate))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 14)
                    Text(event.title)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(event.duration)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !data.todosDueToday.isEmpty {
                Divider()
                Text("Due Today")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                ForEach(data.todosDueToday) { todo in
                    HStack(spacing: 6) {
                        Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundColor(todo.completed ? .green : .secondary)
                        Text(todo.title)
                            .font(.caption)
                            .strikethrough(todo.completed)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Week Blocks Card

struct WeekBlocksCard: View {
    let data: WeekBlocksCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.accentColor)
                Text(data.title)
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(totalBlocks) blocks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(data.dayColumns) { day in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(SharedDateFormatters.shortDayDate.string(from: day.date))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(day.blocks.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if day.blocks.isEmpty {
                        Text("No events")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)
                    } else {
                        ForEach(day.blocks) { block in
                            HStack(spacing: 6) {
                                Text(block.timeRange)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 92, alignment: .leading)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.accentColor)
                                    .frame(width: 2, height: 14)
                                Text(block.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(block.calendarTitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }

    private var totalBlocks: Int {
        data.dayColumns.reduce(0) { $0 + $1.blocks.count }
    }
}

// MARK: - Project Snapshot Card

struct ProjectSnapshotCard: View {
    let data: ProjectSnapshotData
    let onAction: (ChatAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: data.color) ?? .blue)
                    .frame(width: 10, height: 10)
                Text(data.name)
                    .font(.callout.weight(.medium))
                Spacer()
                Button {
                    if let id = Int64(data.id) {
                        onAction(.viewProject(projectId: id))
                    }
                } label: {
                    Text("View")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            if let desc = data.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Label("\(data.openTodoCount) open", systemImage: "circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Label("\(data.completedTodoCount) done", systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if data.deliverableCount > 0 {
                    Label("\(data.deliverableCount) deliverables", systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !data.topTodos.isEmpty {
                Divider()
                ForEach(data.topTodos) { todo in
                    HStack(spacing: 6) {
                        Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundColor(todo.completed ? .green : .secondary)
                        Button {
                            onAction(.viewTodo(todoId: todo.id))
                        } label: {
                            Text(todo.title)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if todo.priority >= 2 {
                            priorityIcon(todo.priority)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }

    private func priorityIcon(_ priority: Int) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundColor(priority >= 3 ? .red : .orange)
    }
}

// MARK: - Todo List Card

struct TodoListCard: View {
    let data: TodoListCardData
    let onAction: (ChatAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !data.title.isEmpty {
                Text(data.title)
                    .font(.callout.weight(.medium))
            }

            if data.todos.isEmpty {
                Text("No open TODOs for this view.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(data.todos) { todo in
                    HStack(spacing: 6) {
                        Button {
                            onAction(.completeTodo(todoId: todo.id))
                        } label: {
                            Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                                .font(.callout)
                                .foregroundColor(todo.completed ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onAction(.viewTodo(todoId: todo.id))
                        } label: {
                            Text(todo.title)
                                .font(.callout)
                                .strikethrough(todo.completed)
                                .foregroundColor(todo.completed ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if todo.priority >= 2 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(todo.priority >= 3 ? .red : .orange)
                        }

                        if let due = todo.dueDate {
                            Text(SharedDateFormatters.shortMonthDay.string(from: due))
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(dueDateColor(due).opacity(0.15))
                                .foregroundColor(dueDateColor(due))
                                .cornerRadius(3)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }

    private func dueDateColor(_ date: Date) -> Color {
        let today = Calendar.current.startOfDay(for: Date())
        if date < today { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return .secondary
    }
}
