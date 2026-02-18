import Foundation

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
    var uiElements: [ChatUIElement]
    var interactionState: ChatInteractionState?

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
        richContent: RichContent? = nil,
        uiElements: [ChatUIElement] = [],
        interactionState: ChatInteractionState? = nil
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
        self.uiElements = uiElements
        self.interactionState = interactionState
    }

    var formattedTime: String {
        SharedDateFormatters.shortTime.string(from: timestamp)
    }
}
