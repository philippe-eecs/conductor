import SwiftUI

@main
struct ConductorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            ConductorView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "brain")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
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

    private let claudeService = ClaudeService.shared

    init() {
        // Check if setup completed (lightweight preference read is OK on main thread)
        hasCompletedSetup = (try? Database.shared.getPreference(key: "setup_completed")) == "true"

        // Load tools preference (default: disabled for safety)
        toolsEnabled = (try? Database.shared.getPreference(key: "tools_enabled")) == "true"

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
    }

    func setToolsEnabled(_ enabled: Bool) {
        toolsEnabled = enabled
        Task.detached(priority: .utility) {
            try? Database.shared.setPreference(key: "tools_enabled", value: enabled ? "true" : "false")
        }
    }

    func checkCLIStatus() async {
        // These are nonisolated on the actor, so they don't need await for actor isolation
        let available = await claudeService.checkCLIAvailable()
        let version = await claudeService.getCLIVersion()

        // Already on MainActor, no need for MainActor.run
        self.cliAvailable = available
        self.cliVersion = version
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

        // Already on MainActor, no need for MainActor.run
        messages.append(userMessage)
        isLoading = true

        // Save user message in background
        let sessionId = currentSessionId
        Task.detached(priority: .utility) {
            try? Database.shared.saveMessage(userMessage, forSession: sessionId)
        }

        do {
            // Build context off the main actor (EventKit calls are synchronous under the hood).
            let context = await Task.detached(priority: .userInitiated) {
                await ContextBuilder.shared.buildContext()
            }.value
            let response = try await claudeService.sendMessage(content, context: context, history: messages, toolsEnabled: toolsEnabled)

            let assistantMessage = ChatMessage(role: .assistant, content: response.result)

            // Already on MainActor, no need for MainActor.run
            messages.append(assistantMessage)
            isLoading = false

            // Update session ID if we got one (sync with ClaudeService's session)
            if let newSessionId = response.sessionId {
                currentSessionId = newSessionId
            }

            // Persist session metadata and cost off-main, then refresh UI models.
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

            // Save assistant message in background
            let finalSessionId = currentSessionId
            Task.detached(priority: .utility) {
                try? Database.shared.saveMessage(assistantMessage, forSession: finalSessionId)
            }

        } catch {
            let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")

            // Already on MainActor, no need for MainActor.run
            messages.append(errorMessage)
            isLoading = false
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
    }

    func startNewConversation() {
        messages = []
        Task {
            await claudeService.startNewConversation()
        }
        currentSessionId = nil
    }

    func resumeSession(_ session: Session) {
        currentSessionId = session.id
        Task {
            await claudeService.resumeSession(session.id)
        }
        loadConversationHistory()
    }

    func deleteSession(_ session: Session) {
        let sessionId = session.id
        Task.detached(priority: .utility) {
            try? Database.shared.deleteSession(id: sessionId)
        }
        loadSessions()

        // If we deleted the current session, start fresh
        if currentSessionId == session.id {
            startNewConversation()
        }
    }
}
