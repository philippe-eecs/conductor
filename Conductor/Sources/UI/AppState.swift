import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Chat
    @Published var messages: [Message] = []
    @Published var currentInput: String = ""
    @Published var isLoading: Bool = false
    @Published var currentSessionId: String?

    // Projects
    @Published var projects: [ProjectRepository.ProjectSummary] = []
    @Published var selectedProjectId: Int64?

    // Setup
    @Published var hasCalendarAccess: Bool = false
    @Published var hasRemindersAccess: Bool = false
    @Published var isCliAvailable: Bool = false
    @Published var showSetup: Bool = false

    // Settings
    @Published var showSettings: Bool = false

    // Repositories
    let projectRepo: ProjectRepository
    let messageRepo: MessageRepository
    let blinkRepo: BlinkRepository
    let prefRepo: PreferenceRepository

    private init() {
        let db = AppDatabase.shared
        self.projectRepo = ProjectRepository(db: db)
        self.messageRepo = MessageRepository(db: db)
        self.blinkRepo = BlinkRepository(db: db)
        self.prefRepo = PreferenceRepository(db: db)
    }

    func loadInitialData() {
        loadProjects()
        loadRecentMessages()
        checkPermissions()
    }

    func loadProjects() {
        do {
            projects = try projectRepo.projectSummaries()
        } catch {
            Log.database.error("Failed to load projects: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadRecentMessages() {
        do {
            messages = try messageRepo.recentMessages(limit: 100)
        } catch {
            Log.database.error("Failed to load messages: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkPermissions() {
        hasCalendarAccess = EventKitManager.shared.calendarAuthorizationStatus() == .fullAccess
        hasRemindersAccess = EventKitManager.shared.remindersAuthorizationStatus() == .fullAccess
        Task {
            isCliAvailable = await ClaudeService.shared.checkCLIAvailable()
            showSetup = !isCliAvailable
        }
    }

    func startNewConversation() {
        messages = []
        currentSessionId = nil
        currentInput = ""
        Task { await ClaudeService.shared.startNewConversation() }
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }

        isLoading = true
        currentInput = ""

        // Save user message
        let userMsg = try? messageRepo.saveMessage(role: "user", content: trimmed, sessionId: currentSessionId)
        if let userMsg { messages.append(userMsg) }

        Task {
            do {
                let response = try await ClaudeService.shared.sendMessage(
                    trimmed,
                    history: [],
                    toolsEnabled: true
                )

                // Save session ID
                if let sessionId = response.sessionId {
                    currentSessionId = sessionId
                }

                // Save assistant message
                let assistantMsg = try? messageRepo.saveMessage(
                    role: "assistant",
                    content: response.result,
                    sessionId: currentSessionId,
                    costUsd: response.totalCostUsd
                )
                if let assistantMsg { messages.append(assistantMsg) }

                // Reload projects in case Claude created/modified them
                loadProjects()
            } catch {
                let errorMsg = try? messageRepo.saveMessage(
                    role: "system",
                    content: "Error: \(error.localizedDescription)",
                    sessionId: currentSessionId
                )
                if let errorMsg { messages.append(errorMsg) }
            }

            isLoading = false
        }
    }
}
