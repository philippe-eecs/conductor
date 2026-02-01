import SwiftUI

@main
struct ConductorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        // Main window shown when clicking menu bar icon
        MenuBarExtra {
            ConductorView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "brain")
                if appState.showPlanningNotificationBadge {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .menuBarExtraStyle(.window)

        // Right-click menu
        MenuBarExtra {
            menuContent
        } label: {
            EmptyView() // Hidden, shares the brain icon
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        // Status section
        Section {
            statusMenuItem
        }

        Divider()

        // Quick actions
        Section {
            Button("Open Conductor") {
                AppDelegate.toggleConductorWindow()
            }
            .keyboardShortcut("o")

            Button("Daily Planning...") {
                NotificationCenter.default.post(name: .showPlanningView, object: nil)
            }
            .keyboardShortcut("p")

            Button("New Conversation") {
                appState.startNewConversation()
            }
            .keyboardShortcut("n")
        }

        Divider()

        // Settings & Quit
        Section {
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit Conductor") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var statusMenuItem: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(appState.cliAvailable ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(appState.cliAvailable ? "Claude CLI Ready" : "Claude CLI Not Found")
                    .font(.caption)
            }

            if appState.calendarAccessGranted || appState.remindersAccessGranted {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text(permissionsSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var permissionsSummary: String {
        var parts: [String] = []
        if appState.calendarAccessGranted { parts.append("Calendar") }
        if appState.remindersAccessGranted { parts.append("Reminders") }
        return parts.joined(separator: ", ")
    }
}

// Notification names for cross-component communication
extension Notification.Name {
    static let showPlanningView = Notification.Name("showPlanningView")
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
        calendarAccessGranted = EventKitManager.shared.calendarAuthorizationStatus() == .fullAccess
        remindersAccessGranted = EventKitManager.shared.remindersAuthorizationStatus() == .fullAccess
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
        logActivity(.system, enabled ? "Tools enabled" : "Tools disabled")
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

    func sendMessage(_ content: String) async {
        let userMessage = ChatMessage(role: .user, content: content)

        messages.append(userMessage)
        isLoading = true

        // Save user message in background
        let sessionId = currentSessionId
        Task.detached(priority: .utility) {
            try? Database.shared.saveMessage(userMessage, forSession: sessionId)
        }

        do {
            // Build context off the main actor
            let context = await Task.detached(priority: .userInitiated) {
                await ContextBuilder.shared.buildContext()
            }.value

            // Create message context for display
            let messageContext = MessageContext.from(context)

            // Log context usage
            logContextUsage(context)

            let chatModel = await Task.detached(priority: .utility) {
                (((try? Database.shared.getPreference(key: "claude_chat_model")) ?? nil) ?? "sonnet")
            }.value

            let response = try await claudeService.sendMessage(
                content,
                context: context,
                history: messages,
                toolsEnabled: toolsEnabled,
                modelOverride: chatModel
            )

            // Create assistant message with context metadata
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response.result,
                contextUsed: messageContext,
                cost: response.totalCostUsd
            )

            messages.append(assistantMessage)
            isLoading = false

            // Update session ID if we got one
            if let newSessionId = response.sessionId {
                currentSessionId = newSessionId
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

            // Log the interaction with detailed metadata
            var logMetadata: [String: String] = [:]
            logMetadata["Context"] = messageContext.summary
            if let cost = costToLog {
                logMetadata["Cost"] = String(format: "$%.4f", cost)
                logActivity(.ai, "Response generated", metadata: logMetadata)
            }

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

    private func logContextUsage(_ context: ContextData) {
        var parts: [String] = []
        if !context.todayEvents.isEmpty {
            parts.append("\(context.todayEvents.count) events")
        }
        if !context.upcomingReminders.isEmpty {
            parts.append("\(context.upcomingReminders.count) reminders")
        }
        if let planning = context.planningContext {
            if !planning.todaysGoals.isEmpty {
                parts.append("\(planning.todaysGoals.count) goals")
            }
        }
        if let email = context.emailContext, email.unreadCount > 0 {
            parts.append("\(email.unreadCount) emails")
        }

        if !parts.isEmpty {
            logActivity(.context, "Using: " + parts.joined(separator: ", "))
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
