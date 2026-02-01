import SwiftUI

/// Shows what context Claude has access to - calendar, reminders, goals, email
/// Enhanced with skeleton loading states and last refreshed timestamps
struct ContextTabView: View {
    @State private var contextData: ContextData?
    @State private var isLoading = false
    @State private var lastRefreshed: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Last refreshed header
                if let lastRefreshed = lastRefreshed {
                    HStack {
                        Spacer()
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Updated \(lastRefreshed.formatted(.relative(presentation: .numeric)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }

                if isLoading && contextData == nil {
                    // Skeleton loading state
                    calendarSkeletonSection
                    remindersSkeletonSection
                    goalsSkeletonSection
                    emailSkeletonSection
                } else {
                    calendarSection
                    remindersSection
                    goalsSection
                    emailSection
                }
            }
            .padding(12)
        }
        .task {
            await loadContext()
        }
    }

    // MARK: - Skeleton Sections

    private var calendarSkeletonSection: some View {
        SkeletonSection(icon: "calendar", title: "Calendar") {
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonRow()
                }
            }
        }
    }

    private var remindersSkeletonSection: some View {
        SkeletonSection(icon: "checklist", title: "Reminders") {
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonRow()
                }
            }
        }
    }

    private var goalsSkeletonSection: some View {
        SkeletonSection(icon: "target", title: "Goals") {
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonRow()
                }
            }
        }
    }

    private var emailSkeletonSection: some View {
        SkeletonSection(icon: "envelope", title: "Email") {
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonRow(hasSubtitle: true)
                }
            }
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        ContextSection(
            icon: "calendar",
            title: "Calendar",
            count: contextData?.todayEvents.count ?? 0,
            suffix: "events",
            lastRefreshed: lastRefreshed,
            onRefresh: { await loadContext() }
        ) {
            if let events = contextData?.todayEvents, !events.isEmpty {
                ForEach(events.prefix(5), id: \.title) { event in
                    HStack(spacing: 8) {
                        Text(event.time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .leading)

                        Text(event.title)
                            .font(.callout)
                            .lineLimit(1)

                        Spacer()

                        Text(event.duration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if events.count > 5 {
                    Text("+ \(events.count - 5) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                EmptyStateRow(message: "No events today", icon: "calendar.badge.minus")
            }
        }
    }

    // MARK: - Reminders Section

    private var remindersSection: some View {
        ContextSection(
            icon: "checklist",
            title: "Reminders",
            count: contextData?.upcomingReminders.count ?? 0,
            suffix: "pending",
            lastRefreshed: lastRefreshed,
            onRefresh: { await loadContext() }
        ) {
            if let reminders = contextData?.upcomingReminders, !reminders.isEmpty {
                ForEach(reminders.prefix(5), id: \.title) { reminder in
                    HStack(spacing: 8) {
                        Image(systemName: priorityIcon(reminder.priority))
                            .font(.caption)
                            .foregroundColor(priorityColor(reminder.priority))

                        Text(reminder.title)
                            .font(.callout)
                            .lineLimit(1)

                        Spacer()

                        if let due = reminder.dueDate {
                            Text(due)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if reminders.count > 5 {
                    Text("+ \(reminders.count - 5) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                EmptyStateRow(message: "No pending reminders", icon: "checkmark.circle")
            }
        }
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        ContextSection(
            icon: "target",
            title: "Goals",
            count: contextData?.planningContext?.todaysGoals.count ?? 0,
            suffix: completedSuffix,
            lastRefreshed: lastRefreshed,
            onRefresh: { await loadContext() }
        ) {
            if let goals = contextData?.planningContext?.todaysGoals, !goals.isEmpty {
                ForEach(goals, id: \.text) { goal in
                    HStack(spacing: 8) {
                        Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundColor(goal.isCompleted ? .green : .secondary)

                        Text(goal.text)
                            .font(.callout)
                            .lineLimit(1)
                            .strikethrough(goal.isCompleted)
                            .foregroundColor(goal.isCompleted ? .secondary : .primary)

                        Spacer()

                        if goal.priority <= 3 {
                            Text("#\(goal.priority)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let overdue = contextData?.planningContext?.overdueCount, overdue > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(overdue) overdue from previous days")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                }
            } else {
                EmptyStateRow(message: "No goals set for today", icon: "target")
            }
        }
    }

    // MARK: - Email Section

    private var emailSection: some View {
        ContextSection(
            icon: "envelope",
            title: "Email",
            count: contextData?.emailContext?.unreadCount ?? 0,
            suffix: "unread",
            lastRefreshed: lastRefreshed,
            onRefresh: { await loadContext() },
            showEnableButton: contextData?.emailContext == nil
        ) {
            if let email = contextData?.emailContext {
                if !email.importantEmails.isEmpty {
                    ForEach(email.importantEmails.prefix(3), id: \.subject) { mail in
                        HStack(spacing: 8) {
                            Image(systemName: mail.isRead ? "envelope.open" : "envelope.fill")
                                .font(.caption)
                                .foregroundColor(mail.isRead ? .secondary : .accentColor)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(mail.sender)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(mail.subject)
                                    .font(.callout)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    EmptyStateRow(message: "No important emails", icon: "envelope.badge.fill")
                }
            } else {
                HStack {
                    Text("Email integration disabled")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Enable") {
                        enableEmailIntegration()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Helpers

    private var completedSuffix: String {
        guard let goals = contextData?.planningContext?.todaysGoals else { return "" }
        let completed = goals.filter { $0.isCompleted }.count
        let total = goals.count
        return "\(completed)/\(total) complete"
    }

    private func priorityIcon(_ priority: Int) -> String {
        switch priority {
        case 1: return "exclamationmark.3"
        case 2: return "exclamationmark.2"
        default: return "minus"
        }
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 1: return .red
        case 2: return .orange
        default: return .secondary
        }
    }

    private func loadContext() async {
        isLoading = true
        defer {
            isLoading = false
            lastRefreshed = Date()
        }

        contextData = await ContextBuilder.shared.buildContext()
    }

    private func enableEmailIntegration() {
        try? Database.shared.setPreference(key: "email_integration_enabled", value: "true")
        Task {
            await loadContext()
        }
    }
}

// MARK: - Context Section Component

struct ContextSection<Content: View>: View {
    let icon: String
    let title: String
    let count: Int
    let suffix: String
    var lastRefreshed: Date?
    let onRefresh: () async -> Void
    var showEnableButton: Bool = false
    @ViewBuilder let content: Content

    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    HStack(spacing: 4) {
                        Text(title)
                        if count > 0 || !suffix.isEmpty {
                            Text("(\(suffix.isEmpty ? "\(count)" : suffix))")
                                .foregroundColor(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: icon)
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

                Spacer()

                if !showEnableButton {
                    Button(action: {
                        Task {
                            isRefreshing = true
                            await onRefresh()
                            isRefreshing = false
                        }
                    }) {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .help("Refresh")
                }
            }

            content
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Skeleton Components

struct SkeletonSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                ProgressView()
                    .scaleEffect(0.6)
            }

            content
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct SkeletonRow: View {
    var hasSubtitle: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: hasSubtitle ? 4 : 0) {
            HStack(spacing: 8) {
                SkeletonRectangle(width: hasSubtitle ? 16 : 55, height: 12)
                SkeletonRectangle(width: .random(in: 100...180), height: 14)
                Spacer()
                SkeletonRectangle(width: 40, height: 10)
            }

            if hasSubtitle {
                HStack {
                    Spacer().frame(width: 24)
                    SkeletonRectangle(width: .random(in: 80...120), height: 10)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct SkeletonRectangle: View {
    let width: CGFloat
    let height: CGFloat

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(NSColor.separatorColor))
            .frame(width: width, height: height)
            .opacity(isAnimating ? 0.4 : 0.8)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - Empty State Row

struct EmptyStateRow: View {
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContextTabView()
        .frame(width: 400, height: 500)
}
