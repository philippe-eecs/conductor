import SwiftUI

@main
struct ConductorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// Notification names for cross-component communication
extension Notification.Name {
    static let showPlanningView = Notification.Name("showPlanningView")
    static let mcpToolCalled = Notification.Name("mcpToolCalled")
    static let showDayReview = Notification.Name("showDayReview")
    static let mcpServerFailed = Notification.Name("mcpServerFailed")
    static let showThemeInTasks = Notification.Name("showThemeInTasks")
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var cliAvailable: Bool = false
    @Published var cliVersion: String?
    @Published var currentSessionId: String?
    @Published var sessions: [Session] = []

    // Cost tracking
    @Published var dailyCost: Double = 0
    @Published var weeklyCost: Double = 0
    @Published var monthlyCost: Double = 0

    // Setup tracking
    @Published var hasCompletedSetup: Bool = false
    @Published var calendarAccessGranted: Bool = false
    @Published var remindersAccessGranted: Bool = false
    @Published var calendarWriteOnlyAccess: Bool = false
    @Published var remindersWriteOnlyAccess: Bool = false
    @Published var calendarReadEnabled: Bool = true
    @Published var remindersReadEnabled: Bool = true
    @Published var emailIntegrationEnabled: Bool = false
    @Published var mailAppRunning: Bool = false
    @Published var chatCardsV1Enabled: Bool = true

    // Tool mode: when enabled, Claude can execute commands (with approval prompts)
    @Published var toolsEnabled: Bool = false

    // Planning state
    @Published var planningEnabled: Bool = true
    @Published var showPlanningNotificationBadge: Bool = false

    // Activity log for transparency
    @Published var recentActivity: [ActivityLogEntry] = []
    @Published var recentOperationEvents: [OperationEvent] = []

    // Agent task approval
    @Published var pendingApprovalCount: Int = 0
    @Published var pendingActions: [AssistantActionRequest] = []

    // Block proposal popover
    @Published var showProposalPopoverDraftId: String?

    let connectionPromptDismissedDateKey = "connection_prompt_last_dismissed_date"

    let claudeService = ClaudeService.shared
    let conversationCore = ConversationCore.shared
    private let planningService = DailyPlanningService.shared

    init() {
        // Check if setup completed (lightweight preference read is OK on main thread)
        hasCompletedSetup = (try? Database.shared.getPreference(key: "setup_completed")) == "true"

        // Load tools preference (default: disabled for safety)
        toolsEnabled = (try? Database.shared.getPreference(key: "tools_enabled")) == "true"

        // Load planning preference (default: enabled)
        planningEnabled = (try? Database.shared.getPreference(key: "planning_enabled")) != "false"

        // Feature flag: enabled by default in dev
        if let cardsPref = try? Database.shared.getPreference(key: "chat_cards_v1_enabled") {
            chatCardsV1Enabled = cardsPref != "false"
        } else {
            chatCardsV1Enabled = true
            try? Database.shared.setPreference(key: "chat_cards_v1_enabled", value: "true")
        }

        // Check current permission states
        refreshConnectionStates()

        // Start in-process MCP server for context tools (with retry)
        MCPServer.shared.startWithRetry()

        // Observe MCP server fatal failure
        NotificationCenter.default.addObserver(
            forName: .mcpServerFailed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logActivity(.error, "MCP server failed to start. Context tools unavailable.")
        }

        // Start jobs engine (compatibility wrapper over legacy scheduler/runtime)
        JobService.shared.start()

        // Observe MCP tool call notifications for activity logging
        NotificationCenter.default.addObserver(
            forName: .mcpToolCalled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let toolName = info["toolName"] as? String else { return }
            let args = info["arguments"] as? String ?? ""
            Task { @MainActor in
                self.logActivity(.context, "MCP tool called: \(toolName)", metadata: ["Tool": toolName, "Args": String(args.prefix(200))])
            }
        }

        // Load data asynchronously to avoid blocking main thread
        Task {
            await loadInitialData()
        }
    }

    private func loadInitialData() async {
        // Run DB operations on background thread
        let (loadedMessages, loadedSessions, costs, operationEvents) = await Task.detached(priority: .userInitiated) {
            let messages = (try? Database.shared.loadRecentMessages(limit: 50, forSession: nil)) ?? []
            let sessions = (try? Database.shared.getRecentSessions(limit: 20)) ?? []
            let daily = (try? Database.shared.getDailyCost()) ?? 0
            let weekly = (try? Database.shared.getWeeklyCost()) ?? 0
            let monthly = (try? Database.shared.getMonthlyCost()) ?? 0
            let operationEvents = (try? Database.shared.getRecentOperationEvents(limit: 50)) ?? []
            return (messages, sessions, (daily, weekly, monthly), operationEvents)
        }.value

        // Update UI on main actor (we're already on MainActor due to class annotation)
        self.messages = loadedMessages
        self.sessions = loadedSessions
        self.dailyCost = costs.0
        self.weeklyCost = costs.1
        self.monthlyCost = costs.2
        self.recentOperationEvents = operationEvents

        // Check CLI availability
        await checkCLIStatus()

        // Load planning data
        await planningService.loadTodaysData()

        // Check if there's an unread brief
        checkPlanningNotifications()

        // Log startup activity
        logActivity(.system, "Conductor started")
        if calendarAccessGranted {
            logActivity(.context, "Calendar access active")
        }
        if remindersAccessGranted {
            logActivity(.context, "Reminders access active")
        }
    }
}

// MARK: - Activity Log Entry

struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: ActivityType
    let message: String
    let metadata: [String: String]?

    enum ActivityType {
        case system
        case context
        case ai
        case scheduler
        case security
        case operation
        case error

        var icon: String {
            switch self {
            case .system: return "gear"
            case .context: return "doc.text"
            case .ai: return "brain"
            case .scheduler: return "clock"
            case .security: return "lock.shield"
            case .operation: return "checkmark.seal"
            case .error: return "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .system: return .secondary
            case .context: return .blue
            case .ai: return .purple
            case .scheduler: return .orange
            case .security: return .indigo
            case .operation: return .green
            case .error: return .red
            }
        }
    }

    init(type: ActivityType, message: String, metadata: [String: String]? = nil) {
        self.timestamp = Date()
        self.type = type
        self.message = message
        self.metadata = metadata
    }

    var formattedTime: String {
        SharedDateFormatters.time24HourWithSeconds.string(from: timestamp)
    }
}
