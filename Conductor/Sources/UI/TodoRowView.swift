import SwiftUI

struct TodoRowView: View {
    let todo: Todo
    let projectColor: String?
    let onToggle: () -> Void
    let onSelect: (() -> Void)?
    let isSelected: Bool

    init(
        todo: Todo,
        projectColor: String?,
        onToggle: @escaping () -> Void,
        onSelect: (() -> Void)? = nil,
        isSelected: Bool = false
    ) {
        self.todo = todo
        self.projectColor = projectColor
        self.onToggle = onToggle
        self.onSelect = onSelect
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundColor(todo.completed ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(todo.title)
                    .lineLimit(1)
                    .strikethrough(todo.completed)
                    .foregroundColor(todo.completed ? .secondary : .primary)
            }

            Spacer()

            if let color = projectColor {
                Circle()
                    .fill(Color(hex: color) ?? .blue)
                    .frame(width: 6, height: 6)
            }

            if todo.priority >= 1 {
                priorityIndicator
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
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            onSelect?()
        }
    }

    @ViewBuilder
    private var priorityIndicator: some View {
        switch todo.priority {
        case 3:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.red)
        case 2:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.orange)
        case 1:
            Image(systemName: "arrow.down")
                .font(.system(size: 8))
                .foregroundColor(.blue)
        default:
            EmptyView()
        }
    }

    private func dueDateColor(_ date: Date) -> Color {
        let today = Calendar.current.startOfDay(for: Date())
        if date < today { return .red }
        if Calendar.current.isDateInToday(date) { return .orange }
        return .secondary
    }
}
