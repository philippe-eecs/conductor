import SwiftUI
import Combine

extension Notification.Name {
    static let mcpOperationReceipt = Notification.Name("mcpOperationReceipt")
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Chat
    @Published var messages: [Message] = []
    @Published var currentInput: String = ""
    @Published var isLoading: Bool = false
    @Published var currentSessionId: String?
    @Published var messageMetadata: [Int64: MessageMetadata] = [:]

    // Projects
    @Published var projects: [ProjectRepository.ProjectSummary] = []
    @Published var selectedProjectId: Int64?
    @Published var selectedProjectTodos: [Todo] = []
    @Published var selectedProjectDeliverables: [Deliverable] = []
    @Published var selectedTodoId: Int64?
    @Published var selectedTodo: Todo?
    @Published var selectedTodoDeliverables: [Deliverable] = []

    // Today data
    @Published var todayEvents: [EventKitManager.CalendarEvent] = []
    @Published var todayTodos: [Todo] = []
    @Published var openTodos: [Todo] = []

    // Workspace routing
    @Published var primarySurface: WorkspaceSurface = .dashboard
    @Published var secondarySurface: WorkspaceSurface?
    @Published var detachedSurfaces: Set<WorkspaceSurface> = []

    // Setup
    @Published var hasCalendarAccess: Bool = false
    @Published var hasRemindersAccess: Bool = false
    @Published var isCliAvailable: Bool = false
    @Published var showSetup: Bool = false
    @Published var mailConnectionStatus: MailService.ConnectionStatus = .notRunning
    @Published var unreadEmailCount: Int = 0

    // Settings
    @Published var showSettings: Bool = false
    @Published var showPermissionsPrompt: Bool = false

    // Repositories
    let projectRepo: ProjectRepository
    let messageRepo: MessageRepository
    let blinkRepo: BlinkRepository
    let prefRepo: PreferenceRepository

    // Pending receipts accumulated during a Claude call
    private var pendingReceipts: [OperationReceiptData] = []
    private var receiptObserver: AnyCancellable?
    private var openPromptObserver: AnyCancellable?

    private enum PrefKey {
        static let workspacePrimary = "workspace.primarySurface"
        static let workspaceSecondary = "workspace.secondarySurface"
        static let workspaceDetached = "workspace.detachedSurfaces"
    }

    private init() {
        let db = AppDatabase.shared
        self.projectRepo = ProjectRepository(db: db)
        self.messageRepo = MessageRepository(db: db)
        self.blinkRepo = BlinkRepository(db: db)
        self.prefRepo = PreferenceRepository(db: db)

        receiptObserver = NotificationCenter.default.publisher(for: .mcpOperationReceipt)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let receipt = notification.object as? OperationReceiptData {
                    self?.pendingReceipts.append(receipt)
                }
            }

        openPromptObserver = NotificationCenter.default.publisher(for: .openConductorWithPrompt)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let prompt = notification.object as? String,
                      !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                self.openSurface(.chat, in: .primary)
                self.currentInput = prompt
            }
    }

    func loadInitialData() {
        loadWorkspaceLayout()
        primarySurface = .dashboard
        detachedSurfaces.remove(.dashboard)
        secondarySurface = nil
        loadProjects()
        loadRecentMessages()
        loadOpenTodos()
        checkPermissions()
        promptForPermissionsIfNeeded()
        Task {
            await loadTodayData()
            await refreshMailStatus()
        }
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
        refreshPermissionFlags()
        if hasCalendarAccess && hasRemindersAccess {
            showPermissionsPrompt = false
        }
        Task {
            isCliAvailable = await ClaudeService.shared.checkCLIAvailable()
            showSetup = !isCliAvailable
            await refreshMailStatus()
        }
    }

    func promptForPermissionsIfNeeded() {
        refreshPermissionFlags()
        showPermissionsPrompt = !hasCalendarAccess || !hasRemindersAccess
    }

    private func refreshPermissionFlags() {
        hasCalendarAccess = EventKitManager.shared.calendarAuthorizationStatus() == .fullAccess
        hasRemindersAccess = EventKitManager.shared.remindersAuthorizationStatus() == .fullAccess
    }

    func loadTodayData() async {
        todayEvents = await EventKitManager.shared.getTodayEvents()
        loadOpenTodos()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        todayTodos = openTodos.filter { todo in
            guard let due = todo.dueDate else { return false }
            return due >= today && due < tomorrow
        }
    }

    func refreshMailStatus() async {
        mailConnectionStatus = MailService.shared.connectionStatus()
        unreadEmailCount = await MailService.shared.getUnreadCount()
    }

    func loadOpenTodos() {
        do {
            openTodos = try projectRepo.allOpenTodos()
        } catch {
            openTodos = []
        }
    }

    // MARK: - Workspace Layout

    func loadWorkspaceLayout() {
        if let raw = try? prefRepo.get(PrefKey.workspacePrimary),
           let surface = WorkspaceSurface(rawValue: raw) {
            primarySurface = surface
        }

        if let raw = try? prefRepo.get(PrefKey.workspaceSecondary),
           !raw.isEmpty,
           let surface = WorkspaceSurface(rawValue: raw),
           surface != primarySurface {
            secondarySurface = surface
        } else {
            secondarySurface = nil
        }

        if let raw = try? prefRepo.get(PrefKey.workspaceDetached),
           !raw.isEmpty {
            detachedSurfaces = Set(
                raw
                    .split(separator: ",")
                    .compactMap { WorkspaceSurface(rawValue: String($0)) }
            )
        } else {
            detachedSurfaces = []
        }

        detachedSurfaces.remove(primarySurface)
        if let secondary = secondarySurface, detachedSurfaces.contains(secondary) {
            secondarySurface = nil
        }

        ensureValidWorkspace()
    }

    func openSurface(_ surface: WorkspaceSurface, in target: WorkspaceDockTarget = .primary) {
        if detachedSurfaces.remove(surface) != nil {
            MainWindowController.shared.closeDetachedSurfaceWindow(for: surface)
        }

        switch target {
        case .primary:
            if secondarySurface == surface {
                secondarySurface = nil
            }
            primarySurface = surface
        case .secondary:
            if primarySurface != surface {
                detachSurface(surface)
            }
            return
        }

        persistWorkspaceLayout()
    }

    func toggleSecondaryPane(default surface: WorkspaceSurface = .calendar) {
        let target = primarySurface == surface ? .tasks : surface
        if detachedSurfaces.contains(target) {
            redockSurface(target, to: .primary)
        } else {
            detachSurface(target)
        }
    }

    func clearSecondaryPane() {
        if let surface = secondarySurface {
            secondarySurface = nil
            MainWindowController.shared.closeDetachedSurfaceWindow(for: surface)
        }
        persistWorkspaceLayout()
    }

    func detachSurface(_ surface: WorkspaceSurface) {
        if detachedSurfaces.contains(surface) {
            MainWindowController.shared.showDetachedSurfaceWindow(for: surface, appState: self)
            return
        }

        if primarySurface == surface {
            if let secondary = secondarySurface, secondary != surface {
                primarySurface = secondary
                secondarySurface = nil
            } else {
                primarySurface = fallbackPrimarySurface(excluding: [surface])
            }
        }
        if secondarySurface == surface {
            secondarySurface = nil
        }

        detachedSurfaces.insert(surface)
        ensureValidWorkspace()
        persistWorkspaceLayout()
        MainWindowController.shared.showDetachedSurfaceWindow(for: surface, appState: self)
    }

    func redockSurface(_ surface: WorkspaceSurface, to target: WorkspaceDockTarget) {
        if detachedSurfaces.remove(surface) != nil {
            MainWindowController.shared.closeDetachedSurfaceWindow(for: surface)
        }
        openSurface(surface, in: target)
    }

    func handleDetachedWindowClosed(_ surface: WorkspaceSurface) {
        detachedSurfaces.remove(surface)
        ensureValidWorkspace()
        persistWorkspaceLayout()
    }

    func isSurfaceDetached(_ surface: WorkspaceSurface) -> Bool {
        detachedSurfaces.contains(surface)
    }

    private func ensureValidWorkspace() {
        if detachedSurfaces.contains(primarySurface) {
            detachedSurfaces.remove(primarySurface)
        }
        if let secondary = secondarySurface {
            if secondary == primarySurface || detachedSurfaces.contains(secondary) {
                secondarySurface = nil
            }
        }
    }

    private func fallbackPrimarySurface(excluding excluded: Set<WorkspaceSurface>) -> WorkspaceSurface {
        for surface in WorkspaceSurface.navigationOrder where !excluded.contains(surface) && !detachedSurfaces.contains(surface) {
            return surface
        }
        return .dashboard
    }

    private func persistWorkspaceLayout() {
        try? prefRepo.set(PrefKey.workspacePrimary, value: primarySurface.rawValue)
        try? prefRepo.set(PrefKey.workspaceSecondary, value: secondarySurface?.rawValue ?? "")
        let detached = detachedSurfaces.map(\.rawValue).sorted().joined(separator: ",")
        try? prefRepo.set(PrefKey.workspaceDetached, value: detached)
    }

    func startNewConversation() {
        messages = []
        currentSessionId = nil
        currentInput = ""
        messageMetadata = [:]
        Task { await ClaudeService.shared.startNewConversation() }
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }

        isLoading = true
        currentInput = ""
        pendingReceipts = []

        // Save user message
        let userMsg = try? messageRepo.saveMessage(role: "user", content: trimmed, sessionId: currentSessionId)
        if let userMsg { messages.append(userMsg) }

        Task {
            do {
                // Pre-fetch context for new conversations
                var context: ChatContext?
                if currentSessionId == nil {
                    let events = await EventKitManager.shared.getTodayEvents()
                    let summaries = (try? projectRepo.projectSummaries()) ?? []
                    let todos = (try? projectRepo.allOpenTodos()) ?? []
                    context = ChatContext(todayEvents: events, projects: summaries, openTodos: todos)
                }

                let response = try await ClaudeService.shared.sendMessage(
                    trimmed,
                    history: [],
                    toolsEnabled: true,
                    context: context
                )

                // Save session ID
                if let sessionId = response.sessionId {
                    currentSessionId = sessionId
                }

                // Save assistant message with model info
                let assistantMsg = try? messageRepo.saveMessage(
                    role: "assistant",
                    content: response.result,
                    sessionId: currentSessionId,
                    costUsd: response.totalCostUsd,
                    model: response.model
                )
                if let assistantMsg {
                    messages.append(assistantMsg)

                    // Attach metadata
                    var meta = MessageMetadata()
                    meta.model = response.model
                    meta.toolCallNames = response.toolCallNames ?? []

                    // Attach any pending receipts as UI elements
                    for receipt in pendingReceipts {
                        meta.uiElements.append(.operationReceipt(receipt))
                    }
                    pendingReceipts = []

                    if let msgId = assistantMsg.id {
                        messageMetadata[msgId] = meta
                    }
                }

                // Reload projects in case Claude created/modified them
                loadProjects()
                await loadTodayData()
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

    // MARK: - Project Detail

    func loadProjectDetail(_ projectId: Int64) {
        do {
            selectedProjectTodos = try projectRepo.todosForProject(projectId)
            selectedProjectDeliverables = try projectRepo.deliverablesForProject(projectId)
        } catch {
            selectedProjectTodos = []
            selectedProjectDeliverables = []
        }
    }

    // MARK: - Task Detail

    func selectTodo(_ todoId: Int64?) {
        selectedTodoId = todoId

        guard let todoId else {
            selectedTodo = nil
            selectedTodoDeliverables = []
            return
        }

        loadTodoDetail(todoId)
    }

    func loadTodoDetail(_ todoId: Int64) {
        do {
            guard let todo = try projectRepo.todo(id: todoId) else {
                selectTodo(nil)
                return
            }

            selectedTodo = todo
            selectedTodoDeliverables = try projectRepo.deliverablesForTodo(todoId)
            selectedProjectId = todo.projectId
            if let projectId = todo.projectId {
                loadProjectDetail(projectId)
            } else {
                selectedProjectTodos = []
                selectedProjectDeliverables = []
            }
        } catch {
            selectedTodo = nil
            selectedTodoDeliverables = []
        }
    }

    func quickAddTodo(title: String, priority: Int = 0, dueDate: Date? = nil) {
        let projectId = selectedProjectId
        do {
            try projectRepo.createTodo(title: title, priority: priority, dueDate: dueDate, projectId: projectId)
            loadProjects()
            loadOpenTodos()
            if let pid = projectId {
                loadProjectDetail(pid)
            }
            Task { await loadTodayData() }
        } catch {
            Log.database.error("Failed to create todo: \(error.localizedDescription, privacy: .public)")
        }
    }

    func toggleTodoCompletion(_ todoId: Int64) {
        do {
            guard var todo = try projectRepo.todo(id: todoId) else { return }
            todo.completed.toggle()
            todo.completedAt = todo.completed ? Date() : nil
            try projectRepo.updateTodo(todo)
            loadProjects()
            loadOpenTodos()
            if let pid = selectedProjectId {
                loadProjectDetail(pid)
            }
            if selectedTodoId == todoId {
                loadTodoDetail(todoId)
            }
            Task { await loadTodayData() }
        } catch {
            Log.database.error("Failed to toggle todo: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Chat Actions

    func handleChatAction(_ action: ChatAction) {
        switch action {
        case .confirmReceipt(let receiptId):
            updateReceiptStatus(receiptId: receiptId, newStatus: .confirmed)

        case .undoReceipt(let receiptId, let entityType, let entityId):
            do {
                switch entityType {
                case "todo":
                    try projectRepo.deleteTodo(id: entityId)
                    if selectedTodoId == entityId {
                        selectTodo(nil)
                    }
                case "project": try projectRepo.deleteProject(id: entityId)
                default: break
                }
                updateReceiptStatus(receiptId: receiptId, newStatus: .undone)
                loadProjects()
                loadOpenTodos()
                Task { await loadTodayData() }
            } catch {
                Log.database.error("Failed to undo \(entityType): \(error.localizedDescription, privacy: .public)")
            }

        case .completeTodo(let todoId):
            toggleTodoCompletion(todoId)

        case .viewProject(let projectId):
            selectedProjectId = projectId
            loadProjectDetail(projectId)
            openSurface(.projects)

        case .viewTodosForProject(let projectId):
            selectedProjectId = projectId
            loadProjectDetail(projectId)
            openSurface(.projects)

        case .viewTodo(let todoId):
            selectTodo(todoId)
            openSurface(.tasks)

        case .dismissCard(let cardId):
            for (msgId, var meta) in messageMetadata {
                meta.uiElements.removeAll { $0.id == cardId }
                messageMetadata[msgId] = meta
            }
        }
    }

    private func updateReceiptStatus(receiptId: String, newStatus: ReceiptStatus) {
        for (msgId, var meta) in messageMetadata {
            for i in meta.uiElements.indices {
                if case .operationReceipt(var receipt) = meta.uiElements[i],
                   receipt.id == receiptId {
                    receipt.status = newStatus
                    meta.uiElements[i] = .operationReceipt(receipt)
                }
            }
            messageMetadata[msgId] = meta
        }
    }
}
