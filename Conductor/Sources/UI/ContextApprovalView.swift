import SwiftUI

/// Approved context ready to be sent with the query
struct ApprovedContext {
    var events: [ContextData.EventSummary]
    var reminders: [ContextData.ReminderSummary]
    var goals: [ContextData.PlanningContextData.GoalSummary]
    var emails: [ContextData.EmailContextData.EmailSummary]
    var notes: [String]
    var customContext: String
    var libraryItems: [ContextLibraryItem]

    /// Check if any context was selected
    var isEmpty: Bool {
        events.isEmpty && reminders.isEmpty && goals.isEmpty &&
        emails.isEmpty && notes.isEmpty && customContext.isEmpty && libraryItems.isEmpty
    }

    /// Build a summary string
    var summary: String {
        var parts: [String] = []
        if !events.isEmpty { parts.append("\(events.count) events") }
        if !reminders.isEmpty { parts.append("\(reminders.count) reminders") }
        if !goals.isEmpty { parts.append("\(goals.count) goals") }
        if !emails.isEmpty { parts.append("\(emails.count) emails") }
        if !notes.isEmpty { parts.append("\(notes.count) notes") }
        if !customContext.isEmpty { parts.append("custom context") }
        if !libraryItems.isEmpty { parts.append("\(libraryItems.count) library items") }
        return parts.isEmpty ? "No context" : parts.joined(separator: ", ")
    }

    /// Convert to ContextData for sending to Claude
    func toContextData() -> ContextData {
        var context = ContextData()
        context.todayEvents = events
        context.upcomingReminders = reminders
        context.recentNotes = notes

        if !goals.isEmpty {
            context.planningContext = ContextData.PlanningContextData(
                todaysGoals: goals,
                completionRate: 0,
                overdueCount: 0,
                focusGaps: []
            )
        }

        if !emails.isEmpty {
            context.emailContext = ContextData.EmailContextData(
                unreadCount: emails.filter { !$0.isRead }.count,
                importantEmails: emails
            )
        }

        return context
    }

    /// Build additional context string for library items and custom context
    func additionalContextString() -> String? {
        var parts: [String] = []

        if !customContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("## User-Provided Context:\n\(customContext)")
        }

        if !libraryItems.isEmpty {
            parts.append("## From Context Library:")
            for item in libraryItems {
                parts.append("### \(item.title)\n\(item.content)")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

/// View for approving/editing context before sending to Claude
struct ContextApprovalView: View {
    let query: String
    let contextNeed: ContextNeed
    let fetchedContext: ContextData
    let persistentLibrary: [ContextLibraryItem]

    let onApprove: (ApprovedContext) -> Void
    let onSkip: () -> Void

    // State for editing
    @State private var selectedEventIds: Set<String> = []
    @State private var selectedReminderIds: Set<String> = []
    @State private var selectedGoalIds: Set<String> = []
    @State private var selectedEmailIds: Set<String> = []
    @State private var selectedNoteIndices: Set<Int> = []
    @State private var selectedLibraryIds: Set<String> = []
    @State private var customContext: String = ""
    @State private var showAddLibraryItem: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Reasoning
                    reasoningView

                    // Status / availability (always visible)
                    sourceStatusView

                    // Context sections
                    if !fetchedContext.todayEvents.isEmpty {
                        calendarSection
                    }

                    if !fetchedContext.upcomingReminders.isEmpty {
                        remindersSection
                    }

                    if let planning = fetchedContext.planningContext, !planning.todaysGoals.isEmpty {
                        goalsSection(planning.todaysGoals)
                    }

                    if let email = fetchedContext.emailContext, !email.importantEmails.isEmpty {
                        emailSection(email.importantEmails)
                    }

                    if !fetchedContext.recentNotes.isEmpty {
                        notesSection
                    }

                    // Custom context
                    customContextSection

                    // Library items
                    if !persistentLibrary.isEmpty {
                        librarySection
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            actionsView
        }
        .frame(width: 450, height: 500)
        .onAppear {
            initializeSelections()
        }
        .sheet(isPresented: $showAddLibraryItem) {
            AddLibraryItemView { item in
                // Item will be saved to database by parent
                selectedLibraryIds.insert(item.id)
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Image(systemName: "shield.checkered")
                .foregroundColor(.blue)
            Text("Context Approval")
                .font(.headline)
            Spacer()
            Button("Skip") {
                onSkip()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding()
    }

    private var reasoningView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                Text("Why this context?")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text(contextNeed.reasoning)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
        }
    }

    private var sourceStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.shield")
                    .foregroundColor(.secondary)
                Text("What Conductor can access right now")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            VStack(alignment: .leading, spacing: 6) {
                statusRow(
                    title: "Calendar",
                    enabled: fetchedContext.calendarReadEnabled,
                    status: fetchedContext.calendarAuthorization
                )
                statusRow(
                    title: "Reminders",
                    enabled: fetchedContext.remindersReadEnabled,
                    status: fetchedContext.remindersAuthorization
                )
                statusRow(
                    title: "Email",
                    enabled: fetchedContext.emailEnabled,
                    statusText: fetchedContext.emailEnabled ? "Enabled (may require Mail to be running)" : "Disabled"
                )
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func statusRow(
        title: String,
        enabled: Bool,
        status: EventKitManager.AuthorizationStatus
    ) -> some View {
        let text: String = {
            guard enabled else { return "Disabled (user preference)" }
            switch status {
            case .fullAccess: return "Full access"
            case .writeOnly: return "Add-only (can't read)"
            case .notDetermined: return "Not requested yet"
            case .denied: return "Denied"
            case .restricted: return "Restricted"
            }
        }()

        return HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(text)
                .font(.caption)
        }
    }

    private func statusRow(
        title: String,
        enabled: Bool,
        statusText: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(enabled ? statusText : "Disabled (user preference)")
                .font(.caption)
        }
    }

    private var calendarSection: some View {
        ApprovalContextSection(
            title: "Calendar Events",
            icon: "calendar",
            selectedCount: selectedEventIds.count,
            totalCount: fetchedContext.todayEvents.count
        ) {
            ForEach(fetchedContext.todayEvents, id: \.title) { event in
                ContextItemToggle(
                    isSelected: selectedEventIds.contains(event.title),
                    title: event.title,
                    subtitle: "\(event.time) - \(event.duration)"
                ) {
                    toggleSelection(event.title, in: &selectedEventIds)
                }
            }
        }
    }

    private var remindersSection: some View {
        ApprovalContextSection(
            title: "Reminders",
            icon: "checklist",
            selectedCount: selectedReminderIds.count,
            totalCount: fetchedContext.upcomingReminders.count
        ) {
            ForEach(fetchedContext.upcomingReminders, id: \.title) { reminder in
                ContextItemToggle(
                    isSelected: selectedReminderIds.contains(reminder.title),
                    title: reminder.title,
                    subtitle: reminder.dueDate
                ) {
                    toggleSelection(reminder.title, in: &selectedReminderIds)
                }
            }
        }
    }

    private func goalsSection(_ goals: [ContextData.PlanningContextData.GoalSummary]) -> some View {
        ApprovalContextSection(
            title: "Today's Goals",
            icon: "target",
            selectedCount: selectedGoalIds.count,
            totalCount: goals.count
        ) {
            ForEach(goals, id: \.text) { goal in
                ContextItemToggle(
                    isSelected: selectedGoalIds.contains(goal.text),
                    title: goal.text,
                    subtitle: goal.isCompleted ? "Completed" : "In progress"
                ) {
                    toggleSelection(goal.text, in: &selectedGoalIds)
                }
            }
        }
    }

    private func emailSection(_ emails: [ContextData.EmailContextData.EmailSummary]) -> some View {
        ApprovalContextSection(
            title: "Important Emails",
            icon: "envelope",
            selectedCount: selectedEmailIds.count,
            totalCount: emails.count
        ) {
            ForEach(emails, id: \.subject) { email in
                ContextItemToggle(
                    isSelected: selectedEmailIds.contains(email.subject),
                    title: email.subject,
                    subtitle: "From: \(email.sender)"
                ) {
                    toggleSelection(email.subject, in: &selectedEmailIds)
                }
            }
        }
    }

    private var notesSection: some View {
        ApprovalContextSection(
            title: "Recent Notes",
            icon: "note.text",
            selectedCount: selectedNoteIndices.count,
            totalCount: fetchedContext.recentNotes.count
        ) {
            ForEach(Array(fetchedContext.recentNotes.enumerated()), id: \.offset) { index, note in
                ContextItemToggle(
                    isSelected: selectedNoteIndices.contains(index),
                    title: String(note.prefix(50)),
                    subtitle: nil
                ) {
                    if selectedNoteIndices.contains(index) {
                        selectedNoteIndices.remove(index)
                    } else {
                        selectedNoteIndices.insert(index)
                    }
                }
            }
        }
    }

    private var customContextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(.orange)
                Text("Add Custom Context")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            TextEditor(text: $customContext)
                .font(.caption)
                .frame(height: 80)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )

            Text("Paste notes, links, or any additional info you'd like Claude to consider.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var librarySection: some View {
        ApprovalContextSection(
            title: "Your Context Library",
            icon: "books.vertical",
            selectedCount: selectedLibraryIds.count,
            totalCount: persistentLibrary.count
        ) {
            ForEach(persistentLibrary) { item in
                ContextItemToggle(
                    isSelected: selectedLibraryIds.contains(item.id),
                    title: item.title,
                    subtitle: item.type.displayName
                ) {
                    toggleSelection(item.id, in: &selectedLibraryIds)
                }
            }
        }
    }

    private var actionsView: some View {
        HStack(spacing: 12) {
            // Summary
            Text(buildApprovedContext().summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Button("Skip Context") {
                onSkip()
            }
            .buttonStyle(.bordered)

            Button("Send with Context") {
                onApprove(buildApprovedContext())
            }
            .buttonStyle(.borderedProminent)
            .disabled(buildApprovedContext().isEmpty && customContext.isEmpty)
        }
        .padding()
    }

    // MARK: - Helper Methods

    private func initializeSelections() {
        // Select all items by default
        for event in fetchedContext.todayEvents {
            selectedEventIds.insert(event.title)
        }
        for reminder in fetchedContext.upcomingReminders {
            selectedReminderIds.insert(reminder.title)
        }
        if let planning = fetchedContext.planningContext {
            for goal in planning.todaysGoals {
                selectedGoalIds.insert(goal.text)
            }
        }
        if let email = fetchedContext.emailContext {
            for emailItem in email.importantEmails {
                selectedEmailIds.insert(emailItem.subject)
            }
        }
        for index in fetchedContext.recentNotes.indices {
            selectedNoteIndices.insert(index)
        }
        // Auto-include library items
        for item in persistentLibrary where item.autoInclude {
            selectedLibraryIds.insert(item.id)
        }
    }

    private func toggleSelection(_ id: String, in set: inout Set<String>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func buildApprovedContext() -> ApprovedContext {
        let events = fetchedContext.todayEvents.filter { selectedEventIds.contains($0.title) }
        let reminders = fetchedContext.upcomingReminders.filter { selectedReminderIds.contains($0.title) }
        let goals = (fetchedContext.planningContext?.todaysGoals ?? []).filter { selectedGoalIds.contains($0.text) }
        let emails = (fetchedContext.emailContext?.importantEmails ?? []).filter { selectedEmailIds.contains($0.subject) }
        let notes = fetchedContext.recentNotes.enumerated().filter { selectedNoteIndices.contains($0.offset) }.map { $0.element }
        let libraryItems = persistentLibrary.filter { selectedLibraryIds.contains($0.id) }

        return ApprovedContext(
            events: events,
            reminders: reminders,
            goals: goals,
            emails: emails,
            notes: notes,
            customContext: customContext.trimmingCharacters(in: .whitespacesAndNewlines),
            libraryItems: libraryItems
        )
    }
}

// MARK: - Supporting Views

struct ApprovalContextSection<Content: View>: View {
    let title: String
    let icon: String
    let selectedCount: Int
    let totalCount: Int
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(selectedCount)/\(totalCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 4) {
                    content()
                }
                .padding(.leading, 24)
            }
        }
    }
}

struct ContextItemToggle: View {
    let isSelected: Bool
    let title: String
    let subtitle: String?
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

// MARK: - Add Library Item View

struct AddLibraryItemView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var itemType: ContextLibraryItem.ItemType = .note
    @State private var autoInclude: Bool = false

    let onSave: (ContextLibraryItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add to Context Library")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)

                Picker("Type", selection: $itemType) {
                    ForEach(ContextLibraryItem.ItemType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.menu)

                Text("Content")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextEditor(text: $content)
                    .font(.body)
                    .frame(height: 150)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )

                Toggle("Auto-include in all queries", isOn: $autoInclude)
                    .font(.subheadline)

                Text("Auto-included items are always shared with Claude without asking.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    let item = ContextLibraryItem(
                        title: title,
                        content: content,
                        type: itemType,
                        autoInclude: autoInclude
                    )
                    // Save to database
                    try? Database.shared.saveContextLibraryItem(item)
                    onSave(item)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || content.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
    }
}
