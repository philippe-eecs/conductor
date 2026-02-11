import SwiftUI

/// Inline approval cards for proposed actions from agent tasks or chat.
struct ActionApprovalView: View {
    let actions: [AssistantActionRequest]
    let onApprove: (AssistantActionRequest) -> Void
    let onReject: (AssistantActionRequest) -> Void
    let onApproveAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.orange)
                Text("Actions Pending Approval")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if actions.count > 1 {
                    Button("Approve All") {
                        onApproveAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.green)
                }
            }

            ForEach(actions) { action in
                ActionCard(action: action, onApprove: onApprove, onReject: onReject)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ActionCard: View {
    let action: AssistantActionRequest
    let onApprove: (AssistantActionRequest) -> Void
    let onReject: (AssistantActionRequest) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconForAction(action.type))
                .foregroundColor(colorForAction(action.type))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.callout)
                    .lineLimit(2)

                Text(action.type.rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let payload = action.payload, !payload.isEmpty {
                    let details = payload.map { "\($0.key): \($0.value)" }.prefix(3).joined(separator: ", ")
                    Text(details)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: { onReject(action) }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)

                Button(action: { onApprove(action) }) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.green)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func iconForAction(_ type: AssistantActionRequest.ActionType) -> String {
        switch type {
        case .createTodoTask, .updateTodoTask, .deleteTodoTask: return "checklist"
        case .createCalendarEvent, .updateCalendarEvent, .deleteCalendarEvent: return "calendar.badge.plus"
        case .createReminder, .completeReminder: return "bell.badge"
        case .createGoal, .completeGoal: return "target"
        case .sendEmail: return "envelope"
        case .webTask: return "globe"
        }
    }

    private func colorForAction(_ type: AssistantActionRequest.ActionType) -> Color {
        switch type {
        case .createTodoTask, .updateTodoTask, .deleteTodoTask: return .blue
        case .createCalendarEvent, .updateCalendarEvent, .deleteCalendarEvent: return .orange
        case .createReminder, .completeReminder: return .purple
        case .createGoal, .completeGoal: return .green
        case .sendEmail: return .red
        case .webTask: return .indigo
        }
    }
}
