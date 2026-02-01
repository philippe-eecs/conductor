import SwiftUI
import AppKit

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role indicator
                HStack(spacing: 4) {
                    Image(systemName: message.role == .user ? "person.fill" : "brain")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(message.role == .user ? "You" : "Conductor")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(message.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }

                // Message content
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    private var bubbleBackground: some View {
        Group {
            if message.role == .user {
                Color.accentColor.opacity(0.15)
            } else {
                Color(NSColor.controlBackgroundColor)
            }
        }
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
