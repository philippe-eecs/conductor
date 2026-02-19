import SwiftUI

private enum InspectorTab: String, CaseIterable {
    case today = "Today"
    case project = "Project"
    case task = "Task"
}

struct ConductorView: View {
    @EnvironmentObject var appState: AppState
    @State private var inspectorTab: InspectorTab = .today
    @State private var showChat: Bool = true

    var body: some View {
        Group {
            if appState.showSetup {
                SetupView()
            } else {
                workspaceShell
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { keyboardShortcuts }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .frame(width: 420, height: 400)
        }
        .onChange(of: appState.selectedProjectId) { _, selected in
            if selected != nil {
                if appState.selectedTodoId == nil {
                    inspectorTab = .project
                }
            } else {
                ensureInspectorTabIsAvailable()
            }
        }
        .onChange(of: appState.selectedTodoId) { _, selected in
            if selected != nil {
                inspectorTab = .task
            } else {
                ensureInspectorTabIsAvailable()
            }
        }
        .onChange(of: appState.showTodayPanel) { _, visible in
            if visible, appState.selectedProjectId == nil, appState.selectedTodoId == nil {
                inspectorTab = .today
            }
            ensureInspectorTabIsAvailable()
        }
    }

    private var workspaceShell: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()
            workspaceContent
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if showChat {
            HSplitView {
                ProjectListView()
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)

                chatPane
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                if showsInspectorPanel {
                    inspectorPanel
                        .frame(minWidth: 320, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                }
            }
            .id("workspace-with-chat")
        } else {
            HStack(spacing: 0) {
                ProjectListView()
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 260, maxHeight: .infinity)

                Divider()

                if showsInspectorPanel {
                    inspectorPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                } else {
                    Color(nsColor: .controlBackgroundColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .id("workspace-inspector-only")
        }
    }

    private var chatPane: some View {
        VStack(spacing: 0) {
            ChatView()
            InputBar()
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspaceTitle)
                    .font(.headline)
                Text(workspaceSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if appState.currentSessionId != nil {
                Text("Live Session")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
            }

            Button {
                appState.showTodayPanel.toggle()
                if appState.showTodayPanel {
                    inspectorTab = .today
                }
            } label: {
                Label("Today", systemImage: appState.showTodayPanel ? "calendar.circle.fill" : "calendar.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .help("Toggle Today Panel")

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showChat.toggle()
                    if !showChat && !showsInspectorPanel {
                        appState.showTodayPanel = true
                        inspectorTab = .today
                    }
                }
            } label: {
                Image(systemName: showChat ? "bubble.left.fill" : "bubble.left")
            }
            .buttonStyle(.plain)
            .help(showChat ? "Hide Chat" : "Show Chat")

            Button {
                appState.startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .help("New Conversation")

            Button {
                appState.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            inspectorHeader
            Divider()
            inspectorBody
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var inspectorHeader: some View {
        HStack(spacing: 8) {
            if availableInspectorTabs.count > 1 {
                Picker("Inspector", selection: $inspectorTab) {
                    ForEach(availableInspectorTabs, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Label(inspectorTitle, systemImage: inspectorIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            if closeButtonAction != nil {
                Button {
                    closeButtonAction?()
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(closeButtonTitle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var inspectorBody: some View {
        if activeInspectorTab == .today {
            TodayPanelView()
        } else if activeInspectorTab == .project, let projectId = appState.selectedProjectId {
            ProjectDetailView(projectId: projectId)
        } else if activeInspectorTab == .task, let todoId = appState.selectedTodoId {
            TaskDetailView(todoId: todoId)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("No inspector content")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedProjectName: String? {
        guard let selectedId = appState.selectedProjectId else { return nil }
        return appState.projects.first(where: { $0.project.id == selectedId })?.project.name
    }

    private var showsInspectorPanel: Bool {
        !availableInspectorTabs.isEmpty
    }

    private var inspectorTitle: String {
        switch activeInspectorTab {
        case .today: return "Today"
        case .project: return "Project"
        case .task: return "Task"
        }
    }

    private var workspaceTitle: String {
        if let todo = appState.selectedTodo {
            return todo.title
        }
        return selectedProjectName ?? "Conductor"
    }

    private var workspaceSubtitle: String {
        if appState.selectedTodoId != nil {
            return "Task workspace"
        }
        if selectedProjectName != nil {
            return "Project workspace"
        }
        if showChat {
            return "Chat workspace"
        }
        return "Calendar workspace"
    }

    private var availableInspectorTabs: [InspectorTab] {
        var tabs: [InspectorTab] = []
        if appState.showTodayPanel { tabs.append(.today) }
        if appState.selectedProjectId != nil { tabs.append(.project) }
        if appState.selectedTodoId != nil { tabs.append(.task) }
        return tabs
    }

    private var activeInspectorTab: InspectorTab {
        if availableInspectorTabs.contains(inspectorTab) {
            return inspectorTab
        }
        return availableInspectorTabs.first ?? .today
    }

    private var closeButtonTitle: String {
        switch activeInspectorTab {
        case .today: return "Hide Today Panel"
        case .project: return "Hide Project Panel"
        case .task: return "Hide Task Panel"
        }
    }

    private var closeButtonAction: (() -> Void)? {
        switch activeInspectorTab {
        case .today:
            guard appState.showTodayPanel else { return nil }
            return {
                appState.showTodayPanel = false
                ensureInspectorTabIsAvailable()
            }
        case .project:
            guard appState.selectedProjectId != nil else { return nil }
            return {
                appState.selectedProjectId = nil
                ensureInspectorTabIsAvailable()
            }
        case .task:
            guard appState.selectedTodoId != nil else { return nil }
            return {
                appState.selectTodo(nil)
                ensureInspectorTabIsAvailable()
            }
        }
    }

    private func ensureInspectorTabIsAvailable() {
        if !availableInspectorTabs.contains(inspectorTab), let fallback = availableInspectorTabs.first {
            inspectorTab = fallback
        }
        if !showChat && availableInspectorTabs.isEmpty {
            appState.showTodayPanel = true
            inspectorTab = .today
        }
    }

    private var inspectorIcon: String {
        switch activeInspectorTab {
        case .today: return "calendar"
        case .project: return "checklist"
        case .task: return "list.bullet.rectangle"
        }
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("") { appState.startNewConversation() }
                .keyboardShortcut("n", modifiers: .command)

            Button("") {
                appState.showTodayPanel.toggle()
                if appState.showTodayPanel {
                    inspectorTab = .today
                }
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showChat.toggle()
                    if !showChat && !showsInspectorPanel {
                        appState.showTodayPanel = true
                        inspectorTab = .today
                    }
                }
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("") { appState.showSettings = true }
                .keyboardShortcut(",", modifiers: .command)

            Button("") { handleEscape() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func handleEscape() {
        if appState.showSettings {
            appState.showSettings = false
            return
        }

        if appState.selectedTodoId != nil {
            appState.selectTodo(nil)
            ensureInspectorTabIsAvailable()
            return
        }

        if appState.selectedProjectId != nil {
            appState.selectedProjectId = nil
            ensureInspectorTabIsAvailable()
            return
        }

        if appState.showTodayPanel {
            appState.showTodayPanel = false
            ensureInspectorTabIsAvailable()
        }
    }
}
