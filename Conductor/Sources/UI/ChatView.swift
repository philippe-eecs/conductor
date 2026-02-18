import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if appState.messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "brain")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Conductor")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("Ask me about your schedule, projects, or anything.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(appState.messages, id: \.id) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if appState.isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .id("loading")
                    }
                }
                .padding()
            }
            .onChange(of: appState.messages.count) { _ in
                withAnimation {
                    if let lastId = appState.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: appState.isLoading) { loading in
                if loading {
                    withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 40) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(LocalizedStringKey(message.content))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor)
                    .foregroundColor(message.role == "user" ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let cost = message.costUsd, cost > 0 {
                    Text(String(format: "$%.4f", cost))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if message.role != "user" { Spacer(minLength: 40) }
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case "user":
            return .accentColor
        case "system":
            return Color.red.opacity(0.15)
        default:
            return Color(nsColor: .controlBackgroundColor)
        }
    }
}
