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

    // Tool mode: when enabled, Claude can execute commands (with approval prompts)
    @Published var toolsEnabled: Bool = false

    // Planning state
    @Published var planningEnabled: Bool = true
    @Published var showPlanningNotificationBadge: Bool = false

    // Activity log for transparency
    @Published var recentActivity: [ActivityLogEntry] = []

    // Agent task approval
    @Published var pendingApprovalCount: Int = 0
    @Published var pendingActions: [AssistantActionRequest] = []

    private let claudeService = ClaudeService.shared
    private let planningService = DailyPlanningService.shared

    init() {
        // Check if setup completed (lightweight preference read is OK on main thread)
        hasCompletedSetup = (try? Database.shared.getPreference(key: "setup_completed")) == "true"

        // Load tools preference (default: disabled for safety)
        toolsEnabled = (try? Database.shared.getPreference(key: "tools_enabled")) == "true"

        // Load planning preference (default: enabled)
        planningEnabled = (try? Database.shared.getPreference(key: "planning_enabled")) != "false"

        // Check current permission states
        refreshPermissionStates()

        // Start in-process MCP server for context tools
        MCPServer.shared.start()

        // Start agent task scheduler
        AgentTaskScheduler.shared.start()

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
        let (loadedMessages, loadedSessions, costs) = await Task.detached(priority: .userInitiated) {
            let messages = (try? Database.shared.loadRecentMessages(limit: 50, forSession: nil)) ?? []
            let sessions = (try? Database.shared.getRecentSessions(limit: 20)) ?? []
            let daily = (try? Database.shared.getDailyCost()) ?? 0
            let weekly = (try? Database.shared.getWeeklyCost()) ?? 0
            let monthly = (try? Database.shared.getMonthlyCost()) ?? 0
            return (messages, sessions, (daily, weekly, monthly))
        }.value

        // Update UI on main actor (we're already on MainActor due to class annotation)
        self.messages = loadedMessages
        self.sessions = loadedSessions
        self.dailyCost = costs.0
        self.weeklyCost = costs.1
        self.monthlyCost = costs.2

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

    func checkPlanningNotifications() {
        let today = DailyPlanningService.todayDateString
        if let brief = try? Database.shared.getDailyBrief(for: today, type: .morning),
           brief.readAt == nil && !brief.dismissed {
            showPlanningNotificationBadge = true
        } else {
            showPlanningNotificationBadge = false
        }
    }

    func refreshPermissionStates() {
        let calendarStatus = EventKitManager.shared.calendarAuthorizationStatus()
        calendarAccessGranted = calendarStatus == .fullAccess || calendarStatus == .writeOnly

        let remindersStatus = EventKitManager.shared.remindersAuthorizationStatus()
        remindersAccessGranted = remindersStatus == .fullAccess || remindersStatus == .writeOnly
    }

    func completeSetup() {
        hasCompletedSetup = true
        Task.detached(priority: .utility) {
            try? Database.shared.setPreference(key: "setup_completed", value: "true")
        }
        refreshPermissionStates()
        logActivity(.system, "Setup completed")
    }

    func setToolsEnabled(_ enabled: Bool) {
        toolsEnabled = enabled
        Task.detached(priority: .utility) {
            try? Database.shared.setPreference(key: "tools_enabled", value: enabled ? "true" : "false")
        }
        logActivity(.system, enabled ? "Insecure mode enabled" : "Insecure mode disabled")
    }

    func checkCLIStatus() async {
        let available = await claudeService.checkCLIAvailable()
        let version = await claudeService.getCLIVersion()

        self.cliAvailable = available
        self.cliVersion = version

        if !available {
            logActivity(.error, "Claude CLI not found")
        }
    }

    func loadConversationHistory() {
        Task {
            let sessionId = self.currentSessionId
            let loadedMessages = await Task.detached(priority: .userInitiated) {
                (try? Database.shared.loadRecentMessages(limit: 50, forSession: sessionId)) ?? []
            }.value
            self.messages = loadedMessages
        }
    }

    func loadSessions() {
        Task {
            let loadedSessions = await Task.detached(priority: .userInitiated) {
                (try? Database.shared.getRecentSessions(limit: 20)) ?? []
            }.value
            self.sessions = loadedSessions
        }
    }

    func loadCostData() {
        Task {
            let costs = await Task.detached(priority: .userInitiated) {
                let daily = (try? Database.shared.getDailyCost()) ?? 0
                let weekly = (try? Database.shared.getWeeklyCost()) ?? 0
                let monthly = (try? Database.shared.getMonthlyCost()) ?? 0
                return (daily, weekly, monthly)
            }.value
            self.dailyCost = costs.0
            self.weeklyCost = costs.1
            self.monthlyCost = costs.2
        }
    }

    /// Sends a message to Claude. Context is fetched on-demand via MCP tools.
    func sendMessage(_ content: String) async {
        let userMessage = ChatMessage(role: .user, content: content)
        messages.append(userMessage)
        isLoading = true

        // Save user message in background
        let sessionId = currentSessionId
        Task.detached(priority: .utility) {
            try? Database.shared.saveMessage(userMessage, forSession: sessionId)
        }

        // Ensure MCP server is running
        if !MCPServer.shared.isRunning {
            MCPServer.shared.start()
        }

        do {
            let chatModel = await Task.detached(priority: .utility) {
                (((try? Database.shared.getPreference(key: "claude_chat_model")) ?? nil) ?? "opus")
            }.value

            let permissionMode = await Task.detached(priority: .utility) {
                (((try? Database.shared.getPreference(key: "claude_permission_mode")) ?? nil) ?? "plan")
            }.value

            let response = try await claudeService.sendMessage(
                content,
                history: messages,
                toolsEnabled: toolsEnabled,
                modelOverride: chatModel,
                permissionModeOverride: permissionMode
            )

            // Parse actions from response
            let parseResult = ActionParser.extractActions(from: response.result)
            let displayText = parseResult.cleanText.isEmpty ? response.result : parseResult.cleanText

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: displayText,
                cost: response.totalCostUsd,
                model: response.model,
                toolCalls: response.toolCalls
            )

            messages.append(assistantMessage)

            // Handle parsed actions
            if !parseResult.actions.isEmpty {
                for action in parseResult.actions {
                    let isSafe = ActionExecutor.safeActionTypes.contains(action.type)
                        && !action.requiresUserApproval
                    if isSafe {
                        Task {
                            let _ = await ActionExecutor.shared.execute(action)
                        }
                    } else {
                        pendingActions.append(action)
                        pendingApprovalCount += 1
                    }
                }
            }

            isLoading = false

            // Speak response if voice is enabled
            SpeechManager.shared.speak(displayText)

            // Update session ID if we got one
            if let newSessionId = response.sessionId {
                currentSessionId = newSessionId
            }

            // Log tool calls to activity
            if let toolCalls = response.toolCalls {
                for tool in toolCalls {
                    var toolMeta: [String: String] = ["Tool": tool.displayName]
                    if let input = tool.input { toolMeta["Input"] = String(input.prefix(200)) }
                    logActivity(.context, "Tool called: \(tool.displayName)", metadata: toolMeta)
                }
            }

            // Persist session metadata and cost
            let sessionToPersist = currentSessionId
            let title = extractTitle(from: content)
            let costToLog = response.totalCostUsd
            await Task.detached(priority: .utility) {
                if let sid = sessionToPersist {
                    try? Database.shared.saveSession(id: sid, title: title)
                    try? Database.shared.associateOrphanedMessages(withSession: sid)
                }
                if let cost = costToLog {
                    try? Database.shared.logCost(amount: cost, sessionId: sessionToPersist)
                }
            }.value

            loadCostData()
            loadSessions()

            // Log the interaction
            var logMetadata: [String: String] = [:]
            if let cost = costToLog {
                logMetadata["Cost"] = String(format: "$%.4f", cost)
            }
            if let model = response.model {
                logMetadata["Model"] = model
            }
            logActivity(.ai, "Response generated", metadata: logMetadata)

            // Save assistant message in background
            let finalSessionId = currentSessionId
            Task.detached(priority: .utility) {
                try? Database.shared.saveMessage(assistantMessage, forSession: finalSessionId)
            }

        } catch {
            let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
            messages.append(errorMessage)
            isLoading = false
            logActivity(.error, "Request failed: \(error.localizedDescription)")
        }
    }

    private func extractTitle(from message: String) -> String {
        let truncated = String(message.prefix(50))
        if let periodIndex = truncated.firstIndex(of: ".") {
            return String(truncated[..<periodIndex])
        }
        if let newlineIndex = truncated.firstIndex(of: "\n") {
            return String(truncated[..<newlineIndex])
        }
        return truncated
    }

    func clearHistory() {
        messages = []
        Task {
            await claudeService.startNewConversation()
        }
        let sessionId = currentSessionId
        currentSessionId = nil
        Task.detached(priority: .utility) {
            try? Database.shared.clearMessages(forSession: sessionId)
        }
        logActivity(.system, "History cleared")
    }

    func startNewConversation() {
        messages = []
        Task {
            await claudeService.startNewConversation()
        }
        currentSessionId = nil
        logActivity(.system, "New conversation started")
    }

    func resumeSession(_ session: Session) {
        currentSessionId = session.id
        Task {
            await claudeService.resumeSession(session.id)
        }
        loadConversationHistory()
        logActivity(.system, "Resumed session: \(session.title)")
    }

    func deleteSession(_ session: Session) {
        let sessionId = session.id
        Task.detached(priority: .utility) {
            try? Database.shared.deleteSession(id: sessionId)
        }
        loadSessions()

        if currentSessionId == session.id {
            startNewConversation()
        }
    }

    // MARK: - Action Approval

    func approveAction(_ action: AssistantActionRequest) {
        pendingActions.removeAll { $0.id == action.id }
        pendingApprovalCount = max(0, pendingApprovalCount - 1)
        Task {
            let success = await ActionExecutor.shared.execute(action)
            logActivity(.system, success ? "Action approved: \(action.title)" : "Action failed: \(action.title)")
        }
        Task.detached(priority: .utility) {
            try? Database.shared.recordBehaviorEvent(type: .actionApproved, entityId: action.id)
        }
    }

    func rejectAction(_ action: AssistantActionRequest) {
        pendingActions.removeAll { $0.id == action.id }
        pendingApprovalCount = max(0, pendingApprovalCount - 1)
        logActivity(.system, "Action rejected: \(action.title)")
        Task.detached(priority: .utility) {
            try? Database.shared.recordBehaviorEvent(type: .actionRejected, entityId: action.id)
        }
    }

    func approveAllActions() {
        let actions = pendingActions
        pendingActions.removeAll()
        pendingApprovalCount = 0
        for action in actions {
            Task {
                let success = await ActionExecutor.shared.execute(action)
                logActivity(.system, success ? "Action approved: \(action.title)" : "Action failed: \(action.title)")
            }
        }
    }

    // MARK: - Activity Logging

    func logActivity(_ type: ActivityLogEntry.ActivityType, _ message: String, metadata: [String: String]? = nil) {
        let entry = ActivityLogEntry(type: type, message: message, metadata: metadata)
        recentActivity.insert(entry, at: 0)

        // Keep only last 100 entries for better audit trail
        if recentActivity.count > 100 {
            recentActivity = Array(recentActivity.prefix(100))
        }
    }

    /// Log a security-related event with detailed metadata
    func logSecurityEvent(_ action: String, allowed: Bool, details: [String: String] = [:]) {
        var metadata = details
        metadata["Allowed"] = allowed ? "Yes" : "No"
        metadata["Time"] = SharedDateFormatters.iso8601.string(from: Date())

        let message = allowed ? "Allowed: \(action)" : "Blocked: \(action)"
        logActivity(.security, message, metadata: metadata)
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
        case error

        var icon: String {
            switch self {
            case .system: return "gear"
            case .context: return "doc.text"
            case .ai: return "brain"
            case .scheduler: return "clock"
            case .security: return "lock.shield"
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
