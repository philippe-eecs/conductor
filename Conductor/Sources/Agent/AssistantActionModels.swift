import Foundation

/// A lightweight, forward-compatible schema for "assistant proposes actions" workflows.
/// Not wired into the UI yet; intended as scaffolding for future builds (action approval + execution).
struct AssistantActionEnvelope: Codable, Equatable {
    var actions: [AssistantActionRequest] = []
    var notes: String?
}

struct AssistantActionRequest: Codable, Equatable, Identifiable {
    var id: String
    var type: ActionType
    var title: String
    var requiresUserApproval: Bool
    var humanSteps: [HumanStep]?
    var payload: [String: String]?

    init(
        id: String = UUID().uuidString,
        type: ActionType,
        title: String,
        requiresUserApproval: Bool = true,
        humanSteps: [HumanStep]? = nil,
        payload: [String: String]? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.requiresUserApproval = requiresUserApproval
        self.humanSteps = humanSteps
        self.payload = payload
    }

    enum ActionType: String, Codable, CaseIterable {
        case createTodoTask
        case updateTodoTask
        case deleteTodoTask

        case createCalendarEvent
        case updateCalendarEvent
        case deleteCalendarEvent

        case createReminder
        case completeReminder

        case createGoal
        case completeGoal

        case sendEmail
        case webTask
    }
}

/// Represents explicit human-in-the-loop steps (e.g. login, captcha, 2FA) for future web agent flows.
struct HumanStep: Codable, Equatable, Identifiable {
    var id: String
    var kind: Kind
    var instructions: String

    init(id: String = UUID().uuidString, kind: Kind, instructions: String) {
        self.id = id
        self.kind = kind
        self.instructions = instructions
    }

    enum Kind: String, Codable, CaseIterable {
        case login
        case captcha
        case twoFactor
        case consent
        case manualCheck
    }
}

