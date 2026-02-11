import SwiftUI
import AppKit

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var isHovering = false
    @State private var showCopied = false
    @State private var isContextExpanded = false
    @State private var isToolCallsExpanded = false

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

                    // Model badge for assistant messages
                    if message.role == .assistant, let model = message.model {
                        modelBadge(model)
                    }

                    // Tool calls badge for assistant messages
                    if message.role == .assistant, let tools = message.toolCalls, !tools.isEmpty {
                        Button(action: { isToolCallsExpanded.toggle() }) {
                            toolCallsBadge(tools)
                        }
                        .buttonStyle(.plain)
                    }

                    // Context badge for assistant messages (clickable to expand)
                    if message.role == .assistant, let context = message.contextUsed, !context.isEmpty {
                        Button(action: { isContextExpanded.toggle() }) {
                            contextBadge(context)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Message content
                VStack(alignment: .leading, spacing: 6) {
                    // Rich content (visual cards) - shown before text
                    if message.role == .assistant, let richContent = message.richContent {
                        switch richContent {
                        case .dayOverview(let data):
                            DayOverviewCard(data: data)
                        case .weekOverview:
                            // Week overview card would go here
                            EmptyView()
                        }
                    }

                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)

                    // Expandable tool calls for assistant messages
                    if message.role == .assistant, let tools = message.toolCalls, !tools.isEmpty, isToolCallsExpanded {
                        toolCallsDetailView(tools)
                    }

                    // Expandable context details for assistant messages
                    if message.role == .assistant, let context = message.contextUsed, !context.isEmpty, isContextExpanded {
                        contextDetailsView(context)
                    }

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

    // MARK: - Model Badge

    private func modelBadge(_ model: String) -> some View {
        let displayName = model.contains("opus") ? "Opus" : model.contains("sonnet") ? "Sonnet" : model.contains("haiku") ? "Haiku" : model
        return Text(displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.purple)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(4)
    }

    // MARK: - Tool Calls Badge & Detail

    private func toolCallsBadge(_ tools: [ClaudeService.ToolCallInfo]) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.caption2)
            Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                .font(.caption2)
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(4)
    }

    private func toolCallsDetailView(_ tools: [ClaudeService.ToolCallInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Tools called")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { isToolCallsExpanded = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)

                    if let input = tool.input, !input.isEmpty {
                        Text(input)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.top, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Context Details View

    private func contextDetailsView(_ context: MessageContext) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Context sent with this message")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { isContextExpanded = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Events section
            if !context.events.isEmpty {
                contextSection(title: "Calendar Events", icon: "calendar") {
                    ForEach(context.events) { event in
                        HStack(spacing: 6) {
                            Text(event.time)
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .frame(width: 50, alignment: .leading)
                            Text(event.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(event.duration)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Reminders section
            if !context.reminders.isEmpty {
                contextSection(title: "Reminders", icon: "checklist") {
                    ForEach(context.reminders) { reminder in
                        HStack(spacing: 6) {
                            Image(systemName: priorityIcon(reminder.priority))
                                .font(.caption2)
                                .foregroundColor(priorityColor(reminder.priority))
                            Text(reminder.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            if let due = reminder.dueDate {
                                Text(due)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Goals section
            if !context.goals.isEmpty {
                contextSection(title: "Today's Goals", icon: "target") {
                    ForEach(context.goals) { goal in
                        HStack(spacing: 6) {
                            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundColor(goal.isCompleted ? .green : .secondary)
                            Text(goal.text)
                                .font(.caption)
                                .strikethrough(goal.isCompleted)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }

            // Emails section
            if !context.emails.isEmpty {
                contextSection(title: "Recent Emails", icon: "envelope") {
                    ForEach(context.emails) { email in
                        HStack(spacing: 6) {
                            Image(systemName: email.isRead ? "envelope.open" : "envelope.fill")
                                .font(.caption2)
                                .foregroundColor(email.isRead ? .secondary : .blue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(email.sender)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                Text(email.subject)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func contextSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                content()
            }
            .padding(.leading, 16)
        }
    }

    private func priorityIcon(_ priority: Int) -> String {
        switch priority {
        case 1: return "exclamationmark.3"
        case 2...4: return "exclamationmark.2"
        case 5...9: return "exclamationmark"
        default: return "minus"
        }
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 1: return .red
        case 2...4: return .orange
        case 5...9: return .yellow
        default: return .secondary
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

    // Full context data for transparency view
    var events: [EventDetail] = []
    var reminders: [ReminderDetail] = []
    var goals: [GoalDetail] = []
    var emails: [EmailDetail] = []

    struct EventDetail: Codable, Equatable, Identifiable {
        var id: String { "\(time)-\(title)" }
        let time: String
        let title: String
        let duration: String
        let location: String?
    }

    struct ReminderDetail: Codable, Equatable, Identifiable {
        var id: String { title }
        let title: String
        let dueDate: String?
        let priority: Int
    }

    struct GoalDetail: Codable, Equatable, Identifiable {
        var id: String { text }
        let text: String
        let priority: Int
        let isCompleted: Bool
    }

    struct EmailDetail: Codable, Equatable, Identifiable {
        var id: String { "\(sender)-\(subject)" }
        let sender: String
        let subject: String
        let isRead: Bool
    }

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
        var messageContext = MessageContext(
            eventsCount: context.todayEvents.count,
            remindersCount: context.upcomingReminders.count,
            goalsCount: context.planningContext?.todaysGoals.count ?? 0,
            emailCount: context.emailContext?.unreadCount ?? 0
        )

        // Store full event details
        messageContext.events = context.todayEvents.map { event in
            EventDetail(
                time: event.time,
                title: event.title,
                duration: event.duration,
                location: event.location
            )
        }

        // Store full reminder details
        messageContext.reminders = context.upcomingReminders.map { reminder in
            ReminderDetail(
                title: reminder.title,
                dueDate: reminder.dueDate,
                priority: reminder.priority
            )
        }

        // Store full goal details
        if let planningContext = context.planningContext {
            messageContext.goals = planningContext.todaysGoals.map { goal in
                GoalDetail(
                    text: goal.text,
                    priority: goal.priority,
                    isCompleted: goal.isCompleted
                )
            }
        }

        // Store email details
        if let emailContext = context.emailContext {
            messageContext.emails = emailContext.importantEmails.map { email in
                EmailDetail(
                    sender: email.sender,
                    subject: email.subject,
                    isRead: email.isRead
                )
            }
        }

        return messageContext
    }
}

// MARK: - Rich Content

enum RichContent: Codable, Equatable {
    case dayOverview(DayOverviewData)
    case weekOverview(WeekOverviewData)
}

struct WeekOverviewData: Codable, Equatable {
    let startDate: Date
    let days: [DaySummary]

    struct DaySummary: Codable, Equatable, Identifiable {
        var id: String { dateString }
        let dateString: String
        let dayName: String
        let eventCount: Int
        let taskCount: Int
        let hasHighPriority: Bool
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
    var model: String?
    var toolCalls: [ClaudeService.ToolCallInfo]?
    var richContent: RichContent?

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
        cost: Double? = nil,
        model: String? = nil,
        toolCalls: [ClaudeService.ToolCallInfo]? = nil,
        richContent: RichContent? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextUsed = contextUsed
        self.cost = cost
        self.model = model
        self.toolCalls = toolCalls
        self.richContent = richContent
    }

    var formattedTime: String {
        SharedDateFormatters.shortTime.string(from: timestamp)
    }
}
