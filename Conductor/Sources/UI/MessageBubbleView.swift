import SwiftUI
import AppKit

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var isHovering = false
    @State private var showCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role indicator with context badge
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

                    // Context badge for assistant messages
                    if message.role == .assistant, let context = message.contextUsed {
                        contextBadge(context)
                    }
                }

                // Message content
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)

                    // Action buttons (shown on hover for assistant messages)
                    if message.role == .assistant && isHovering {
                        messageActions
                    }
                }
                .padding(10)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Context Badge

    private func contextBadge(_ context: MessageContext) -> some View {
        HStack(spacing: 4) {
            if context.eventsCount > 0 {
                contextPill(icon: "calendar", count: context.eventsCount)
            }
            if context.remindersCount > 0 {
                contextPill(icon: "checklist", count: context.remindersCount)
            }
            if context.goalsCount > 0 {
                contextPill(icon: "target", count: context.goalsCount)
            }
            if context.emailCount > 0 {
                contextPill(icon: "envelope", count: context.emailCount)
            }
        }
    }

    private func contextPill(icon: String, count: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(count)")
                .font(.caption2)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(4)
    }

    // MARK: - Message Actions

    private var messageActions: some View {
        HStack(spacing: 12) {
            // Copy button
            Button(action: copyMessage) {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                    Text(showCopied ? "Copied!" : "Copy")
                        .font(.caption)
                }
                .foregroundColor(showCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Cost badge if available
            if let cost = message.cost {
                Text(String(format: "$%.4f", cost))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 4)
        .transition(.opacity)
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopied = false
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

// MARK: - Message Context

struct MessageContext: Codable, Equatable {
    var eventsCount: Int = 0
    var remindersCount: Int = 0
    var goalsCount: Int = 0
    var emailCount: Int = 0

    var isEmpty: Bool {
        eventsCount == 0 && remindersCount == 0 && goalsCount == 0 && emailCount == 0
    }

    var summary: String {
        var parts: [String] = []
        if eventsCount > 0 { parts.append("\(eventsCount) events") }
        if remindersCount > 0 { parts.append("\(remindersCount) reminders") }
        if goalsCount > 0 { parts.append("\(goalsCount) goals") }
        if emailCount > 0 { parts.append("\(emailCount) emails") }
        return parts.isEmpty ? "No context" : parts.joined(separator: ", ")
    }

    static func from(_ context: ContextData) -> MessageContext {
        MessageContext(
            eventsCount: context.todayEvents.count,
            remindersCount: context.upcomingReminders.count,
            goalsCount: context.planningContext?.todaysGoals.count ?? 0,
            emailCount: context.emailContext?.unreadCount ?? 0
        )
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    var contextUsed: MessageContext?
    var cost: Double?

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        contextUsed: MessageContext? = nil,
        cost: Double? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextUsed = contextUsed
        self.cost = cost
    }

    var formattedTime: String {
        SharedDateFormatters.shortTime.string(from: timestamp)
    }
}
