import SwiftUI
import AppKit

struct ConductorView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""
    @State private var showSettings: Bool = false
    @State private var showSessions: Bool = false
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

            // Messages
            if appState.cliAvailable {
                messagesView
            } else {
                cliNotFoundView
            }

            Divider()

            // Input
            if appState.cliAvailable {
                inputView
            }
        }
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showSessions) {
            SessionsView()
                .environmentObject(appState)
        }
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
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

            // Sessions button
            Button(action: { showSessions = true }) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .help("Session History")

            // New conversation
            Button(action: { appState.startNewConversation() }) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .help("New Conversation")

            Button(action: { showSettings = true }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button(action: { appState.clearHistory() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Clear history")

            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("Quit Conductor")
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
