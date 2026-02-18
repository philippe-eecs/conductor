import Foundation
import SwiftUI

struct Session: Identifiable {
    let id: String
    let createdAt: Date
    let lastUsed: Date
    let title: String

    var formattedLastUsed: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }
}

struct DailyBrief: Identifiable {
    let id: String
    let date: String  // YYYY-MM-DD
    let briefType: BriefType
    let content: String
    let generatedAt: Date
    var readAt: Date?
    var dismissed: Bool

    enum BriefType: String, Codable {
        case morning
        case evening
        case weekly
        case monthly
    }

    init(
        id: String = UUID().uuidString,
        date: String,
        briefType: BriefType,
        content: String,
        generatedAt: Date = Date(),
        readAt: Date? = nil,
        dismissed: Bool = false
    ) {
        self.id = id
        self.date = date
        self.briefType = briefType
        self.content = content
        self.generatedAt = generatedAt
        self.readAt = readAt
        self.dismissed = dismissed
    }
}

struct DailyGoal: Identifiable {
    let id: String
    let date: String  // YYYY-MM-DD
    var goalText: String
    var priority: Int
    var completedAt: Date?
    var rolledTo: String?

    var isCompleted: Bool { completedAt != nil }
    var isRolled: Bool { rolledTo != nil }

    init(
        id: String = UUID().uuidString,
        date: String,
        goalText: String,
        priority: Int = 0,
        completedAt: Date? = nil,
        rolledTo: String? = nil
    ) {
        self.id = id
        self.date = date
        self.goalText = goalText
        self.priority = priority
        self.completedAt = completedAt
        self.rolledTo = rolledTo
    }
}

struct ProductivityStats: Identifiable {
    let id: String
    let date: String  // YYYY-MM-DD
    let goalsCompleted: Int
    let goalsTotal: Int
    let meetingsCount: Int
    let meetingsHours: Double
    let focusHours: Double
    let overdueCount: Int
    let generatedAt: Date

    var completionRate: Double {
        guard goalsTotal > 0 else { return 0 }
        return Double(goalsCompleted) / Double(goalsTotal)
    }

    init(
        id: String = UUID().uuidString,
        date: String,
        goalsCompleted: Int,
        goalsTotal: Int,
        meetingsCount: Int,
        meetingsHours: Double,
        focusHours: Double,
        overdueCount: Int,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.goalsCompleted = goalsCompleted
        self.goalsTotal = goalsTotal
        self.meetingsCount = meetingsCount
        self.meetingsHours = meetingsHours
        self.focusHours = focusHours
        self.overdueCount = overdueCount
        self.generatedAt = generatedAt
    }
}

struct ContextFilter: Codable, Equatable {
    var calendarKeywords: [String]
    var includeCalendar: Bool
    var includeReminders: Bool
    var includeEmails: Bool
    var includeTasks: Bool

    init(
        calendarKeywords: [String] = [],
        includeCalendar: Bool = true,
        includeReminders: Bool = true,
        includeEmails: Bool = false,
        includeTasks: Bool = true
    ) {
        self.calendarKeywords = calendarKeywords
        self.includeCalendar = includeCalendar
        self.includeReminders = includeReminders
        self.includeEmails = includeEmails
        self.includeTasks = includeTasks
    }
}

struct TaskList: Identifiable {
    let id: String
    var name: String
    var color: String
    var icon: String
    var sortOrder: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        color: String = "blue",
        icon: String = "list.bullet",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
    }

    var swiftUIColor: Color {
        switch color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        default: return .blue
        }
    }
}

struct TodoTask: Identifiable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: Date?
    var listId: String?
    var priority: Priority
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var blockedByTaskId: String?
    var blockedOffsetDays: Int?

    enum Priority: Int, CaseIterable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3

        var label: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }

        var icon: String? {
            switch self {
            case .none: return nil
            case .low: return "arrow.down"
            case .medium: return "minus"
            case .high: return "exclamationmark"
            }
        }

        var color: Color {
            switch self {
            case .none: return .secondary
            case .low: return .blue
            case .medium: return .orange
            case .high: return .red
            }
        }
    }

    var isBlocked: Bool {
        blockedByTaskId != nil
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        listId: String? = nil,
        priority: Priority = .none,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        blockedByTaskId: String? = nil,
        blockedOffsetDays: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.listId = listId
        self.priority = priority
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.blockedByTaskId = blockedByTaskId
        self.blockedOffsetDays = blockedOffsetDays
    }

    var isOverdue: Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Date()
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    var isDueTomorrow: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInTomorrow(dueDate)
    }

    var isDueThisWeek: Bool {
        guard let dueDate else { return false }
        let calendar = Calendar.current
        let now = Date()
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) else { return false }
        return dueDate >= now && dueDate < weekEnd
    }

    var dueDateLabel: String? {
        guard let dueDate else { return nil }

        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        } else if isOverdue {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: dueDate, relativeTo: Date())
        } else {
            return SharedDateFormatters.shortMonthDay.string(from: dueDate)
        }
    }
}

// MARK: - Themes

struct Theme: Identifiable {
    let id: String
    var name: String
    var color: String
    var themeDescription: String?
    var objective: String?
    var isArchived: Bool
    var sortOrder: Int
    let createdAt: Date
    var defaultStartTime: String?
    var defaultDurationMinutes: Int
    var contextFilter: ContextFilter?
    var autoRemindLeftover: Bool
    var leftoverRemindTime: String?
    var isLooseBucket: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        color: String = "blue",
        themeDescription: String? = nil,
        objective: String? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        defaultStartTime: String? = nil,
        defaultDurationMinutes: Int = 60,
        contextFilter: ContextFilter? = nil,
        autoRemindLeftover: Bool = false,
        leftoverRemindTime: String? = nil,
        isLooseBucket: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.themeDescription = themeDescription
        self.objective = objective
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.defaultStartTime = defaultStartTime
        self.defaultDurationMinutes = defaultDurationMinutes
        self.contextFilter = contextFilter
        self.autoRemindLeftover = autoRemindLeftover
        self.leftoverRemindTime = leftoverRemindTime
        self.isLooseBucket = isLooseBucket
    }

    var swiftUIColor: Color {
        switch color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        case "indigo": return .indigo
        case "teal": return .teal
        default: return .blue
        }
    }
}

enum ThemeItemType: String, Codable {
    case task
    case note
    case goal
}

struct ThemeItem: Identifiable {
    let id: String
    let themeId: String
    let itemType: ThemeItemType
    let itemId: String
    let createdAt: Date
}

struct ThemeBlock: Identifiable, Codable {
    enum Status: String, Codable, CaseIterable {
        case draft
        case planned
        case published
    }

    let id: String
    var themeId: String
    var startTime: Date
    var endTime: Date
    var isRecurring: Bool
    var recurrenceRule: String?
    var status: Status
    var calendarEventId: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        themeId: String,
        startTime: Date,
        endTime: Date,
        isRecurring: Bool = false,
        recurrenceRule: String? = nil,
        status: Status = .draft,
        calendarEventId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.themeId = themeId
        self.startTime = startTime
        self.endTime = endTime
        self.isRecurring = isRecurring
        self.recurrenceRule = recurrenceRule
        self.status = status
        self.calendarEventId = calendarEventId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Processed Emails

struct ProcessedEmail: Identifiable {
    let id: String
    let messageId: String
    let sender: String
    let subject: String
    let bodyPreview: String
    let receivedAt: Date
    let isRead: Bool
    let severity: EmailSeverity
    let aiSummary: String?
    let actionItem: String?
    let processedAt: Date
    var dismissed: Bool

    init(
        id: String = UUID().uuidString,
        messageId: String,
        sender: String,
        subject: String,
        bodyPreview: String = "",
        receivedAt: Date = Date(),
        isRead: Bool = true,
        severity: EmailSeverity = .normal,
        aiSummary: String? = nil,
        actionItem: String? = nil,
        processedAt: Date = Date(),
        dismissed: Bool = false
    ) {
        self.id = id
        self.messageId = messageId
        self.sender = sender
        self.subject = subject
        self.bodyPreview = bodyPreview
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.severity = severity
        self.aiSummary = aiSummary
        self.actionItem = actionItem
        self.processedAt = processedAt
        self.dismissed = dismissed
    }

    var formattedReceivedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: receivedAt, relativeTo: Date())
    }
}

enum EmailSeverity: String, Codable, CaseIterable {
    case critical
    case important
    case normal
    case low
}

enum EmailFilter: String, CaseIterable {
    case all = "All"
    case actionNeeded = "Action Needed"
    case important = "Important"
    case dismissed = "Dismissed"
}

// MARK: - Operation Events

enum OperationKind: String, Codable, CaseIterable {
    case created
    case updated
    case deleted
    case assigned
    case linked
    case published
    case failed
}

enum OperationStatus: String, Codable, CaseIterable {
    case success
    case failed
    case partialSuccess = "partial_success"
}

struct OperationEvent: Identifiable, Codable {
    let id: String
    let correlationId: String
    let operation: OperationKind
    let entityType: String
    let entityId: String?
    let source: String
    let status: OperationStatus
    let message: String
    let payload: [String: String]
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        correlationId: String = UUID().uuidString,
        operation: OperationKind,
        entityType: String,
        entityId: String? = nil,
        source: String,
        status: OperationStatus,
        message: String,
        payload: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.correlationId = correlationId
        self.operation = operation
        self.entityType = entityType
        self.entityId = entityId
        self.source = source
        self.status = status
        self.message = message
        self.payload = payload
        self.createdAt = createdAt
    }

    var formattedTime: String {
        SharedDateFormatters.shortTime.string(from: createdAt)
    }

    var statusIcon: String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .partialSuccess: return "exclamationmark.triangle.fill"
        }
    }

    var statusColorName: String {
        switch status {
        case .success: return "green"
        case .failed: return "red"
        case .partialSuccess: return "orange"
        }
    }
}

struct OperationReceipt {
    let operationId: String
    let correlationId: String
    let entityType: String
    let entityId: String?
    let status: OperationStatus
    let message: String
    let timestamp: Date

    init(operationId: String, correlationId: String, entityType: String, entityId: String?, status: OperationStatus, message: String, timestamp: Date = Date()) {
        self.operationId = operationId
        self.correlationId = correlationId
        self.entityType = entityType
        self.entityId = entityId
        self.status = status
        self.message = message
        self.timestamp = timestamp
    }

    init(from event: OperationEvent) {
        self.operationId = event.id
        self.correlationId = event.correlationId
        self.entityType = event.entityType
        self.entityId = event.entityId
        self.status = event.status
        self.message = event.message
        self.timestamp = event.createdAt
    }

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "operation_id": operationId,
            "correlation_id": correlationId,
            "entity_type": entityType,
            "status": status.rawValue,
            "message": message,
            "timestamp": SharedDateFormatters.iso8601DateTime.string(from: timestamp),
        ]
        if let entityId {
            dict["entity_id"] = entityId
        }
        return dict
    }
}

// MARK: - Behavior Events

enum BehaviorEventType: String, Codable, CaseIterable {
    case taskCompleted = "task_completed"
    case goalCompleted = "goal_completed"
    case goalRolled = "goal_rolled"
    case actionApproved = "action_approved"
    case actionRejected = "action_rejected"
    case taskDeferred = "task_deferred"
    case emailDismissed = "email_dismissed"
    case emailActioned = "email_actioned"
    case checkinCompleted = "checkin_completed"
    case agentTaskCreated = "agent_task_created"
}

struct BehaviorEvent: Identifiable {
    let id: String
    let eventType: BehaviorEventType
    let entityId: String?
    let metadata: [String: String]
    let hourOfDay: Int
    let dayOfWeek: Int
    let createdAt: Date
}

// MARK: - Context Library

struct ContextLibraryItem: Identifiable, Codable {
    let id: String
    var title: String
    var content: String
    var type: ItemType
    var createdAt: Date
    var autoInclude: Bool

    enum ItemType: String, Codable, CaseIterable {
        case note
        case link
        case document
        case calendarSnapshot
        case custom

        var icon: String {
            switch self {
            case .note: return "note.text"
            case .link: return "link"
            case .document: return "doc"
            case .calendarSnapshot: return "calendar"
            case .custom: return "square.and.pencil"
            }
        }

        var displayName: String {
            switch self {
            case .note: return "Note"
            case .link: return "Link"
            case .document: return "Document"
            case .calendarSnapshot: return "Calendar Snapshot"
            case .custom: return "Custom"
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        content: String,
        type: ItemType = .note,
        createdAt: Date = Date(),
        autoInclude: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.type = type
        self.createdAt = createdAt
        self.autoInclude = autoInclude
    }
}

