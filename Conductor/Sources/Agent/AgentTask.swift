import Foundation

// MARK: - Agent Task

struct AgentTask: Identifiable {
    let id: String
    var name: String
    var prompt: String
    var triggerType: TriggerType
    var triggerConfig: TriggerConfig
    var contextNeeds: [AgentContextNeed]
    var allowedActions: [AssistantActionRequest.ActionType]
    var status: Status
    var createdBy: CreatedBy
    var createdAt: Date
    var lastRun: Date?
    var nextRun: Date?
    var runCount: Int
    var maxRuns: Int?

    enum TriggerType: String, Codable, CaseIterable {
        case time
        case recurring
        case event
        case checkin
        case manual
    }

    enum Status: String, Codable, CaseIterable {
        case active
        case paused
        case completed
        case expired
    }

    enum CreatedBy: String, Codable {
        case chat
        case system
        case agent
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        prompt: String,
        triggerType: TriggerType,
        triggerConfig: TriggerConfig = TriggerConfig(),
        contextNeeds: [AgentContextNeed] = [],
        allowedActions: [AssistantActionRequest.ActionType] = [],
        status: Status = .active,
        createdBy: CreatedBy = .chat,
        createdAt: Date = Date(),
        lastRun: Date? = nil,
        nextRun: Date? = nil,
        runCount: Int = 0,
        maxRuns: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.triggerType = triggerType
        self.triggerConfig = triggerConfig
        self.contextNeeds = contextNeeds
        self.allowedActions = allowedActions
        self.status = status
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.lastRun = lastRun
        self.nextRun = nextRun
        self.runCount = runCount
        self.maxRuns = maxRuns
    }

    var isOneShot: Bool {
        triggerType == .time || triggerType == .manual
    }

    var isDue: Bool {
        guard status == .active else { return false }
        guard let nextRun else { return false }
        return nextRun <= Date()
    }
}

// MARK: - Agent Context Need

enum AgentContextNeed: String, Codable, CaseIterable {
    case calendar
    case reminders
    case goals
    case email
    case notes
    case tasks
}

// MARK: - Trigger Config

struct TriggerConfig: Codable {
    var fireAt: Date?
    var cronHour: Int?
    var cronMinute: Int?
    var intervalMinutes: Int?
    var checkinPhase: String?
    var eventType: String?

    init(
        fireAt: Date? = nil,
        cronHour: Int? = nil,
        cronMinute: Int? = nil,
        intervalMinutes: Int? = nil,
        checkinPhase: String? = nil,
        eventType: String? = nil
    ) {
        self.fireAt = fireAt
        self.cronHour = cronHour
        self.cronMinute = cronMinute
        self.intervalMinutes = intervalMinutes
        self.checkinPhase = checkinPhase
        self.eventType = eventType
    }

    var json: String {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    static func fromJSON(_ json: String) -> TriggerConfig {
        guard let data = json.data(using: .utf8),
              let config = try? JSONDecoder().decode(TriggerConfig.self, from: data) else {
            return TriggerConfig()
        }
        return config
    }
}

// MARK: - Agent Task Result

struct AgentTaskResult: Identifiable {
    let id: String
    let taskId: String
    let timestamp: Date
    let output: String
    let actionsProposed: [AssistantActionRequest]
    let actionsExecuted: [ExecutedAction]
    let costUsd: Double?
    let status: ResultStatus
    let durationMs: Int?

    enum ResultStatus: String, Codable {
        case success
        case failed
        case pendingApproval = "pending_approval"
    }

    init(
        id: String = UUID().uuidString,
        taskId: String,
        timestamp: Date = Date(),
        output: String,
        actionsProposed: [AssistantActionRequest] = [],
        actionsExecuted: [ExecutedAction] = [],
        costUsd: Double? = nil,
        status: ResultStatus = .success,
        durationMs: Int? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.timestamp = timestamp
        self.output = output
        self.actionsProposed = actionsProposed
        self.actionsExecuted = actionsExecuted
        self.costUsd = costUsd
        self.status = status
        self.durationMs = durationMs
    }
}

// MARK: - Executed Action

struct ExecutedAction: Codable {
    let actionId: String
    let type: AssistantActionRequest.ActionType
    let title: String
    let approved: Bool
    let executedAt: Date

    init(
        actionId: String,
        type: AssistantActionRequest.ActionType,
        title: String,
        approved: Bool,
        executedAt: Date = Date()
    ) {
        self.actionId = actionId
        self.type = type
        self.title = title
        self.approved = approved
        self.executedAt = executedAt
    }
}
