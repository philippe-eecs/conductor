import SwiftUI

struct EmailWorkspaceView: View {
    @EnvironmentObject var appState: AppState

    @State private var recentEmails: [MailService.EmailSummary] = []
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if appState.mailConnectionStatus != .connected {
                disconnectedView
            } else if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading recent email…")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emailList
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await refreshEmails()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Email")
                    .font(.headline)
                Text("\(appState.unreadEmailCount) unread")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Refresh") {
                Task { await refreshEmails() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var disconnectedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope.badge")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Email is not connected.")
                .font(.callout)
                .foregroundColor(.secondary)
            Button("Connect Mail") {
                Task {
                    _ = await MailService.shared.connectToMailApp()
                    await appState.refreshMailStatus()
                    await refreshEmails()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emailList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if recentEmails.isEmpty {
                    Text("No recent email found.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 12)
                } else {
                    ForEach(Array(recentEmails.enumerated()), id: \.offset) { _, email in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(email.sender)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(SharedDateFormatters.shortTime.string(from: email.receivedDate))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text(email.subject.isEmpty ? "(No Subject)" : email.subject)
                                .font(.callout)
                                .lineLimit(2)

                            HStack {
                                if !email.isRead {
                                    Text("Unread")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15))
                                        .foregroundColor(.blue)
                                        .clipShape(Capsule())
                                }

                                Spacer()

                                Button("Draft Reply in Chat") {
                                    appState.openSurface(.chat, in: .primary)
                                    appState.currentInput = """
                                    Draft a concise reply to this email.
                                    Sender: \(email.sender)
                                    Subject: \(email.subject)
                                    """
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func refreshEmails() async {
        isLoading = true
        await appState.refreshMailStatus()
        if appState.mailConnectionStatus == .connected {
            recentEmails = await MailService.shared.getRecentEmails(hoursBack: 24)
        } else {
            recentEmails = []
        }
        isLoading = false
    }
}
