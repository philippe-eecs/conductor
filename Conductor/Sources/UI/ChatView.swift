import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if appState.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(appState.messages, id: \.id) { message in
                            MessageBubble(
                                message: message,
                                metadata: appState.messageMetadata[message.id ?? -1],
                                onAction: { appState.handleChatAction($0) }
                            )
                            .id(message.id)
                            .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                        }
                    }

                    if appState.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Conductor is thinking…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .id("loading")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                scrollToLatest(proxy: proxy, animated: false)
            }
            .onChange(of: appState.messages.count) { _, _ in
                scrollToLatest(proxy: proxy, animated: true)
            }
            .onChange(of: appState.isLoading) { _, loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 36)

            Image(systemName: "brain")
                .font(.system(size: 42))
                .foregroundColor(.secondary)

            Text("Ask Conductor")
                .font(.title3.weight(.semibold))

            Text("Schedule, projects, and planning in one thread.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(quickActions, id: \.0) { action in
                    Button {
                        appState.currentInput = action.1
                        appState.sendMessage(action.1)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.2)
                                .font(.caption)
                            Text(action.0)
                                .font(.callout)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
    }

    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool) {
        guard let lastId = appState.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    private var quickActions: [(String, String, String)] {
        [
            ("What is on my calendar today?", "What's on my calendar today?", "calendar"),
            ("Show open todos", "Show all my open todos", "checklist"),
            ("Plan my afternoon", "Help me plan my afternoon around today's events", "sparkles"),
        ]
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    let metadata: MessageMetadata?
    let onAction: (ChatAction) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
            roleRow

            VStack(alignment: .leading, spacing: 8) {
                if let meta = metadata, !meta.uiElements.isEmpty {
                    ChatUIElementsView(elements: meta.uiElements, onAction: onAction)
                }

                Text(verbatim: message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let cost = message.costUsd, cost > 0 {
                    Text(String(format: "$%.4f", cost))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(bubbleBackground)
            .foregroundColor(message.role == "user" ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .frame(maxWidth: 640, alignment: .leading)
            .overlay(alignment: message.role == "user" ? .topLeading : .topTrailing) {
                if isHovering {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .padding(5)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .offset(x: message.role == "user" ? -6 : 6, y: -6)
                }
            }
        }
        .onHover { isHovering = $0 }
    }

    private var roleRow: some View {
        HStack(spacing: 6) {
            if message.role != "user" {
                Image(systemName: roleIcon)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(roleName)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }

            if let model = metadata?.model ?? message.model {
                Text(formatModelName(model))
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.16))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if let tools = metadata?.toolCallNames, !tools.isEmpty {
                ToolCallsBadge(toolNames: tools)
            }

            Text(SharedDateFormatters.shortTime.string(from: message.createdAt))
                .font(.caption2)
                .foregroundColor(.secondary)

            if message.role == "user" {
                Text(roleName)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                Image(systemName: roleIcon)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var roleIcon: String {
        switch message.role {
        case "user": return "person.fill"
        case "system": return "exclamationmark.triangle.fill"
        default: return "brain"
        }
    }

    private var roleName: String {
        switch message.role {
        case "user": return "You"
        case "system": return "System"
        default: return "Conductor"
        }
    }

    private var bubbleBackground: some View {
        Group {
            switch message.role {
            case "user":
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "system":
                Color.red.opacity(0.14)
            default:
                Color(nsColor: .controlBackgroundColor)
            }
        }
    }

    private func formatModelName(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        return model.replacingOccurrences(of: "claude-", with: "")
    }
}

// MARK: - Tool Calls Badge

struct ToolCallsBadge: View {
    let toolNames: [String]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "wrench.fill")
                        .font(.system(size: 8))
                    Text("\(toolNames.count)")
                        .font(.system(size: 9, weight: .medium))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15))
                .foregroundColor(.orange)
                .cornerRadius(3)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(toolNames.enumerated()), id: \.offset) { _, name in
                        Text(formatToolName(name))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
        }
    }

    private func formatToolName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "mcp__conductor-context__", with: "")
            .replacingOccurrences(of: "conductor_", with: "")
    }
}
