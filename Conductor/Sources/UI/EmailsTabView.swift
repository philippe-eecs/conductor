import SwiftUI

struct EmailsTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var emails: [ProcessedEmail] = []
    @State private var selectedFilter: EmailFilter = .all
    @State private var emailEnabled: Bool = false

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !emailEnabled {
                emailDisabledView
            } else {
                filterBar
                Divider()
                emailList
            }
        }
        .onAppear { refresh() }
        .onReceive(refreshTimer) { _ in refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Emails")
                .font(.headline)
            Spacer()
            Button("Refresh") { refresh() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(EmailFilter.allCases, id: \.self) { filter in
                Button(filter.rawValue) {
                    selectedFilter = filter
                    loadEmails()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(selectedFilter == filter ? .accentColor : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Email List

    private var emailList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if emails.isEmpty {
                    emptyState
                } else {
                    ForEach(emails) { email in
                        EmailRowView(
                            email: email,
                            onPrepareResponse: { prepareResponse(for: email) },
                            onDismiss: { dismissEmail(email) }
                        )
                    }
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No emails to show")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Emails will appear here after the email triage agent runs.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emailDisabledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Email Integration Disabled")
                .font(.title3)
                .fontWeight(.medium)
            Text("Enable email integration in Settings to see triaged emails here.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    private func prepareResponse(for email: ProcessedEmail) {
        // Switch to chat tab with pre-filled context
        let context = """
        I need to respond to this email:
        From: \(email.sender)
        Subject: \(email.subject)
        \(email.aiSummary.map { "Summary: \($0)" } ?? "")
        \(email.actionItem.map { "Action needed: \($0)" } ?? "")

        Please help me draft a response.
        """

        // Post notification to switch to chat with pre-filled text
        NotificationCenter.default.post(
            name: .prepareEmailResponse,
            object: nil,
            userInfo: ["text": context]
        )
    }

    private func dismissEmail(_ email: ProcessedEmail) {
        try? EmailStore(database: Database.shared).dismissEmail(id: email.id)
        loadEmails()
    }

    private func refresh() {
        emailEnabled = (try? Database.shared.getPreference(key: "email_integration_enabled")) == "true"
        loadEmails()
    }

    private func loadEmails() {
        emails = (try? EmailStore(database: Database.shared).getProcessedEmails(filter: selectedFilter)) ?? []
    }
}

// MARK: - Email Row

struct EmailRowView: View {
    let email: ProcessedEmail
    let onPrepareResponse: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: severity + sender
            HStack(spacing: 6) {
                severityBadge
                Text(email.sender)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(email.formattedReceivedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if !email.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 6, height: 6)
                }
            }

            // Subject
            Text(email.subject)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.primary)

            // AI Summary
            if let summary = email.aiSummary {
                Text("Summary: \(summary)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Action Item
            if let action = email.actionItem {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Action: \(action)")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                if email.actionItem != nil {
                    Button("Prepare Response") { onPrepareResponse() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.accentColor)
                }
                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: email.severity == .critical ? 1 : 0)
        )
    }

    private var severityBadge: some View {
        Text(email.severity.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(severityColor)
            .cornerRadius(3)
    }

    private var severityColor: Color {
        switch email.severity {
        case .critical: return .red
        case .important: return .orange
        case .normal: return .blue
        case .low: return .secondary
        }
    }

    private var borderColor: Color {
        email.severity == .critical ? .red.opacity(0.4) : .clear
    }
}

// MARK: - Notification

extension Notification.Name {
    static let prepareEmailResponse = Notification.Name("prepareEmailResponse")
}
