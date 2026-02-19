import Foundation

// MARK: - Chat Actions

enum ChatAction {
    case confirmReceipt(receiptId: String)
    case undoReceipt(receiptId: String, entityType: String, entityId: Int64)
    case completeTodo(todoId: Int64)
    case viewTodo(todoId: Int64)
    case viewProject(projectId: Int64)
    case viewTodosForProject(projectId: Int64)
    case dismissCard(cardId: String)
}

// MARK: - Chat UI Elements

enum ChatUIElement: Identifiable {
    case operationReceipt(OperationReceiptData)
    case todaySchedule(TodayScheduleData)
    case projectSnapshot(ProjectSnapshotData)
    case todoList(TodoListCardData)

    var id: String {
        switch self {
        case .operationReceipt(let d): return "receipt-\(d.id)"
        case .todaySchedule(let d): return "schedule-\(d.id)"
        case .projectSnapshot(let d): return "project-\(d.id)"
        case .todoList(let d): return "todolist-\(d.id)"
        }
    }
}

// MARK: - Operation Receipt

enum OperationType: String {
    case created, updated, completed, deleted, dispatched
}

enum ReceiptStatus {
    case pending, confirmed, undone
}

struct OperationReceiptData: Identifiable {
    let id: String
    let entityType: String  // "todo", "project", "calendar_event", "agent"
    let entityName: String
    let entityId: Int64?
    let operation: OperationType
    var status: ReceiptStatus = .pending
    let timestamp: Date

    // Detail fields for richer display
    let priority: Int?
    let dueDate: Date?
    let projectName: String?

    init(entityType: String, entityName: String, entityId: Int64?, operation: OperationType,
         priority: Int? = nil, dueDate: Date? = nil, projectName: String? = nil) {
        self.id = UUID().uuidString
        self.entityType = entityType
        self.entityName = entityName
        self.entityId = entityId
        self.operation = operation
        self.priority = priority
        self.dueDate = dueDate
        self.projectName = projectName
        self.timestamp = Date()
    }
}

// MARK: - Today Schedule

struct TodayScheduleData: Identifiable {
    let id = UUID().uuidString
    let date: Date
    let events: [ScheduleEventData]
    let todosDueToday: [TodoLineData]
}

struct ScheduleEventData: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?

    var timeRange: String {
        if isAllDay { return "All day" }
        let start = SharedDateFormatters.shortTime.string(from: startDate)
        let end = SharedDateFormatters.shortTime.string(from: endDate)
        return "\(start) - \(end)"
    }

    var duration: String {
        let interval = endDate.timeIntervalSince(startDate)
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        else if hours > 0 { return "\(hours)h" }
        else { return "\(minutes)m" }
    }
}

// MARK: - Project Snapshot

struct ProjectSnapshotData: Identifiable {
    let id: String
    let name: String
    let color: String
    let description: String?
    let openTodoCount: Int
    let completedTodoCount: Int
    let deliverableCount: Int
    let topTodos: [TodoLineData]
}

// MARK: - Todo List Card

struct TodoListCardData: Identifiable {
    let id = UUID().uuidString
    let title: String
    let todos: [TodoLineData]
}

struct TodoLineData: Identifiable {
    let id: Int64
    let title: String
    let priority: Int
    let dueDate: Date?
    let completed: Bool
    let projectColor: String?
}

// MARK: - Message Metadata

struct MessageMetadata {
    var model: String?
    var toolCallNames: [String] = []
    var uiElements: [ChatUIElement] = []
}
