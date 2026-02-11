import SwiftUI
import AppKit

enum ConductorTab: String, CaseIterable {
    case chat = "Chat"
    case focus = "Focus"
    case schedule = "Schedule"
    case activity = "Activity"

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .focus: return "target"
        case .schedule: return "calendar"
        case .activity: return "chart.bar"
        }
    }
}

struct ConductorView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var speechManager = SpeechManager.shared
    @State private var inputText: String = ""
    @State private var showSettings: Bool = false
    @State private var showSessions: Bool = false
    @State private var showPlanning: Bool = false
    @State private var showBriefing: Bool = false
    @State private var selectedTab: ConductorTab = .chat
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Group {
            if !appState.hasCompletedSetup {
                SetupView(onComplete: {
                    appState.completeSetup()
                })
            } else {
                mainContentView
            }
        }
    }

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Tab Bar
            tabBarView

            Divider()

            // Tab Content
            if appState.cliAvailable {
                tabContentView
            } else {
                cliNotFoundView
            }

            Divider()

            // Input (only visible for chat tab)
            if appState.cliAvailable && selectedTab == .chat {
                inputView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showSessions) {
            SessionsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showPlanning) {
            DailyPlanningView()
        }
        .sheet(isPresented: $showBriefing) {
            MorningBriefingView()
        }
        .onAppear {
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .prepareEmailResponse)) { notification in
            if let text = notification.userInfo?["text"] as? String {
                selectedTab = .chat
                inputText = text
                isInputFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPlanningView)) { _ in
            showPlanning = true
        }
    }

    // MARK: - Tab Bar

    private var tabBarView: some View {
        HStack(spacing: 0) {
            ForEach(ConductorTab.allCases, id: \.self) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    badgeCount: badgeCount(for: tab)
                ) {
                    selectedTab = tab
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func badgeCount(for tab: ConductorTab) -> Int {
        switch tab {
        case .chat:
            return 0
        case .focus:
            return (try? Database.shared.getTodayTasks(includeCompleted: false).count) ?? 0
        case .schedule:
            return 0
        case .activity:
            // Show pending approvals + errors
            let approvals = appState.pendingApprovalCount
            let errors = appState.recentActivity.filter { $0.type == .error }.count
            return approvals + errors
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContentView: some View {
        switch selectedTab {
        case .chat:
            messagesView
        case .focus:
            TodoListView()
        case .schedule:
            ScheduleTabView()
        case .activity:
            ActivityTabView(showPendingApprovals: true)
                .environmentObject(appState)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .foregroundColor(.accentColor)
            Text("Conductor")
                .font(.headline)

            if appState.currentSessionId != nil {
                Text("Session")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
            }

            Spacer()

            // Stop speech button (shown when speaking)
            if speechManager.isSpeaking {
                Button(action: { speechManager.stop() }) {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.red)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stop speaking")
            }

            // Voice toggle
            Button(action: { speechManager.setEnabled(!speechManager.isEnabled) }) {
                Image(systemName: speechManager.isEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .foregroundColor(speechManager.isEnabled ? .accentColor : .secondary)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(speechManager.isEnabled ? "Disable voice" : "Enable voice")

            // Morning briefing
            Button(action: { showBriefing = true }) {
                Image(systemName: "sun.max")
                    .foregroundColor(.orange)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Morning Briefing")

            // Settings
            Button(action: { showSettings = true }) {
                Image(systemName: "gear")
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Overflow menu
            Menu {
                Button(action: { appState.startNewConversation() }) {
                    Label("New Conversation", systemImage: "plus.circle")
                }

                Button(action: { showPlanning = true }) {
                    Label("Daily Planning", systemImage: "calendar.badge.clock")
                }

                Button(action: { showSessions = true }) {
                    Label("Sessions", systemImage: "clock.arrow.circlepath")
                }

                Divider()

                Button(action: { appState.clearHistory() }) {
                    Label("Clear History", systemImage: "trash")
                }

                Divider()

                Button(action: { NSApp.terminate(nil) }) {
                    Label("Quit", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
                    .frame(minWidth: 32, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .help("More actions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Messages

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if appState.messages.isEmpty {
                        welcomeView
                    } else {
                        ForEach(appState.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        if !appState.pendingActions.isEmpty {
                            ActionApprovalView(
                                actions: appState.pendingActions,
                                onApprove: { appState.approveAction($0) },
                                onReject: { appState.rejectAction($0) },
                                onApproveAll: { appState.approveAllActions() }
                            )
                            .id("approval")
                        }

                        if appState.isLoading {
                            loadingView
                                .id("loading")
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: appState.messages.count) { _, _ in
                if let lastMessage = appState.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: appState.isLoading) { _, isLoading in
                if isLoading {
                    withAnimation {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Welcome to Conductor")
                .font(.title2)
                .fontWeight(.medium)

            Text("Your AI-powered personal assistant.\nPowered by Claude Code.\nAsk me anything or try:")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                suggestionButton("What's on my calendar today?")
                suggestionButton("Remind me to call mom Sunday")
                suggestionButton("Help me plan my week")
            }

            // Cost summary
            if appState.dailyCost > 0 || appState.monthlyCost > 0 {
                Divider()
                    .padding(.vertical, 8)

                HStack(spacing: 16) {
                    costBadge("Today", amount: appState.dailyCost)
                    costBadge("Month", amount: appState.monthlyCost)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func costBadge(_ label: String, amount: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .foregroundColor(.secondary)
            Text(String(format: "$%.2f", amount))
                .fontWeight(.medium)
        }
    }

    private func suggestionButton(_ text: String) -> some View {
        Button(action: {
            inputText = text
            sendMessage()
        }) {
            Text(text)
                .font(.callout)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Thinking...")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.leading, 4)
    }

    // MARK: - CLI Not Found View

    private var cliNotFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Claude CLI Not Found")
                .font(.title2)
                .fontWeight(.medium)

            Text("Conductor requires Claude Code to be installed.\nIt uses your Claude Code Max subscription.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Link("Install Claude Code", destination: URL(string: "https://claude.ai/code")!)
                .buttonStyle(.borderedProminent)

            Button("Retry") {
                Task {
                    await appState.checkCLIStatus()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Input

    private var inputView: some View {
        HStack(spacing: 8) {
            // Microphone button for speech-to-text
            Button(action: {
                speechManager.onTextRecognized = { text in
                    inputText = text
                }
                speechManager.toggleListening()
            }) {
                ZStack {
                    Image(systemName: speechManager.isListening ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundColor(speechManager.isListening ? .red : .secondary)

                    // Pulsing indicator when listening
                    if speechManager.isListening {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .frame(width: 28, height: 28)
                            .scaleEffect(speechManager.isListening ? 1.3 : 1.0)
                            .opacity(speechManager.isListening ? 0 : 1)
                            .animation(
                                Animation.easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                value: speechManager.isListening
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .help(speechManager.isListening ? "Stop listening" : "Start voice input")
            .disabled(appState.isLoading)

            Menu {
                ForEach(PromptPresets.all) { preset in
                    Button(preset.title) {
                        applyPromptPreset(preset)
                    }
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .help("Quick prompts")
            .disabled(appState.isLoading)

            TextField("Ask anything...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }
                .disabled(appState.isLoading)

            Button(action: sendMessage) {
                Image(systemName: appState.isLoading ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.isEmpty && !appState.isLoading ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty && !appState.isLoading)
        }
        .padding(12)
    }

    // MARK: - Actions

    private func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        inputText = ""

        Task {
            await appState.sendMessage(content)
        }
    }

    private func applyPromptPreset(_ preset: PromptPreset) {
        if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = preset.template
        } else {
            inputText = preset.template + inputText
        }
        isInputFocused = true
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let tab: ConductorTab
    let isSelected: Bool
    var badgeCount: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.caption)
                Text(tab.rawValue)
                    .font(.caption)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .cornerRadius(6)
                }
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sessions View

struct SessionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recent Sessions")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if appState.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No sessions yet")
                        .foregroundColor(.secondary)
                    Text("Start a conversation to create your first session.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.sessions) { session in
                        SessionRow(session: session) {
                            appState.resumeSession(session)
                            dismiss()
                        } onDelete: {
                            appState.deleteSession(session)
                        }
                    }
                }
            }
        }
        .frame(width: 350, height: 400)
    }
}

struct SessionRow: View {
    let session: Session
    let onResume: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body)
                    .lineLimit(1)
                Text(session.formattedLastUsed)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onResume)
    }
}
