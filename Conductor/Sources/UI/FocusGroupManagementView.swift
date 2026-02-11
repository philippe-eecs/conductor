import SwiftUI

struct FocusGroupManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var focusGroups: [FocusGroup] = []
    @State private var showNewGroup = false
    @State private var editingGroup: FocusGroup?
    @State private var showArchived = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Focus Groups")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Toggle("Archived", isOn: $showArchived)
                    .toggleStyle(.button)
                    .controlSize(.small)
                Button(action: { showNewGroup = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if focusGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No focus groups yet")
                        .foregroundColor(.secondary)
                    Text("Focus Groups help you organize work into\nscheduled time blocks with filtered context.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Create Focus Group") { showNewGroup = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(focusGroups) { group in
                        FocusGroupRowView(group: group, onEdit: {
                            editingGroup = group
                        }, onArchive: {
                            Task {
                                try? Database.shared.archiveFocusGroup(id: group.id)
                                await loadGroups()
                            }
                        }, onDelete: {
                            Task {
                                try? Database.shared.deleteFocusGroup(id: group.id)
                                await loadGroups()
                            }
                        })
                    }
                }
            }
        }
        .frame(width: 450, height: 450)
        .task { await loadGroups() }
        .onChange(of: showArchived) { _, _ in
            Task { await loadGroups() }
        }
        .sheet(isPresented: $showNewGroup) {
            FocusGroupEditSheet(onSave: { group in
                Task {
                    try? Database.shared.createFocusGroup(group)
                    await loadGroups()
                }
            })
        }
        .sheet(item: $editingGroup) { group in
            FocusGroupEditSheet(group: group, onSave: { updated in
                Task {
                    try? Database.shared.updateFocusGroup(updated)
                    await loadGroups()
                }
            })
        }
    }

    private func loadGroups() async {
        focusGroups = (try? Database.shared.getFocusGroups(includeArchived: showArchived)) ?? []
    }
}

// MARK: - Focus Group Row

struct FocusGroupRowView: View {
    let group: FocusGroup
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var taskCount: Int = 0
    @State private var blockCount: Int = 0

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(group.swiftUIColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if group.isArchived {
                        Text("archived")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)
                    }
                }
                HStack(spacing: 8) {
                    if let desc = group.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if let startTime = group.defaultStartTime {
                        Text(startTime)
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if blockCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.caption2)
                            Text("\(blockCount)")
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if taskCount > 0 {
                Text("\(taskCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit") { onEdit() }
            Button(group.isArchived ? "Unarchive" : "Archive") { onArchive() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .task {
            taskCount = (try? Database.shared.getTaskCountForFocusGroup(id: group.id)) ?? 0
            blockCount = (try? Database.shared.getFocusBlocksForGroup(id: group.id).count) ?? 0
        }
    }
}

// MARK: - Focus Group Edit Sheet

struct FocusGroupEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedColor: String
    @State private var description: String
    @State private var keywords: [String]
    @State private var newKeyword: String = ""

    // Focus block scheduling
    @State private var defaultStartTime: Date
    @State private var defaultDuration: Int
    @State private var selectedDays: Set<Weekday> = []

    // Context filter
    @State private var includeCalendar: Bool = true
    @State private var includeReminders: Bool = true
    @State private var includeEmails: Bool = false
    @State private var includeTasks: Bool = true

    // Auto-remind
    @State private var autoRemindLeftover: Bool = false
    @State private var leftoverRemindTime: Date

    private let isEditing: Bool
    private let groupId: String
    let onSave: (FocusGroup) -> Void

    private let colors = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "gray", "indigo", "teal"]
    private let durations = [30, 45, 60, 90, 120]

    init(group: FocusGroup? = nil, onSave: @escaping (FocusGroup) -> Void) {
        self.isEditing = group != nil
        self.groupId = group?.id ?? UUID().uuidString
        _name = State(initialValue: group?.name ?? "")
        _selectedColor = State(initialValue: group?.color ?? "blue")
        _description = State(initialValue: group?.description ?? "")
        _keywords = State(initialValue: [])

        // Parse default start time
        let startComponents = (group?.defaultStartTime ?? "09:00").split(separator: ":")
        let hour = Int(startComponents.first ?? "9") ?? 9
        let minute = Int(startComponents.count > 1 ? startComponents[1] : "0") ?? 0
        _defaultStartTime = State(initialValue: Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date())
        _defaultDuration = State(initialValue: group?.defaultDurationMinutes ?? 60)

        // Context filter
        _includeCalendar = State(initialValue: group?.contextFilter?.includeCalendar ?? true)
        _includeReminders = State(initialValue: group?.contextFilter?.includeReminders ?? true)
        _includeEmails = State(initialValue: group?.contextFilter?.includeEmails ?? false)
        _includeTasks = State(initialValue: group?.contextFilter?.includeTasks ?? true)

        // Auto-remind
        _autoRemindLeftover = State(initialValue: group?.autoRemindLeftover ?? false)
        let remindComponents = (group?.leftoverRemindTime ?? "17:00").split(separator: ":")
        let remindHour = Int(remindComponents.first ?? "17") ?? 17
        let remindMinute = Int(remindComponents.count > 1 ? remindComponents[1] : "0") ?? 0
        _leftoverRemindTime = State(initialValue: Calendar.current.date(bySettingHour: remindHour, minute: remindMinute, second: 0, of: Date()) ?? Date())

        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(isEditing ? "Edit Focus Group" : "New Focus Group")
                    .font(.headline)

                TextField("Focus group name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Description (optional)", text: $description)
                    .textFieldStyle(.roundedBorder)

                // Color picker
                HStack {
                    Text("Color")
                        .foregroundColor(.secondary)
                    Spacer()
                    ForEach(colors, id: \.self) { color in
                        Circle()
                            .fill(colorFor(color))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                            )
                            .onTapGesture { selectedColor = color }
                    }
                }

                Divider()

                // Time Block Scheduling
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default Time Block")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        Text("Start time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        DatePicker("", selection: $defaultStartTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $defaultDuration) {
                            ForEach(durations, id: \.self) { mins in
                                Text("\(mins) min").tag(mins)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }

                    // Recurring days
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recurring days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            ForEach(Weekday.allCases) { day in
                                DayToggle(day: day, isSelected: selectedDays.contains(day)) {
                                    if selectedDays.contains(day) {
                                        selectedDays.remove(day)
                                    } else {
                                        selectedDays.insert(day)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Divider()

                // Context Filter
                VStack(alignment: .leading, spacing: 8) {
                    Text("Context Filter")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("When focused on this group, Claude sees:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        Toggle("Calendar", isOn: $includeCalendar)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        Toggle("Reminders", isOn: $includeReminders)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        Toggle("Tasks", isOn: $includeTasks)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        Toggle("Emails", isOn: $includeEmails)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Divider()

                // Calendar keywords
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendar keywords")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Events matching these keywords will be grouped under this focus group.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        TextField("Add keyword...", text: $newKeyword)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addKeyword() }
                        Button("Add") { addKeyword() }
                            .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !keywords.isEmpty {
                        FlowLayout(spacing: 4) {
                            ForEach(keywords, id: \.self) { kw in
                                HStack(spacing: 2) {
                                    Text(kw)
                                        .font(.caption)
                                    Button(action: { removeKeyword(kw) }) {
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                            }
                        }
                    }
                }

                Divider()

                // Auto-remind
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Remind about unfinished tasks", isOn: $autoRemindLeftover)
                        .font(.subheadline)

                    if autoRemindLeftover {
                        HStack {
                            Text("Remind at")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            DatePicker("", selection: $leftoverRemindTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .frame(width: 100)
                        }
                    }
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.escape)
                    Spacer()
                    Button(isEditing ? "Save" : "Create") {
                        let calendar = Calendar.current
                        let startHour = calendar.component(.hour, from: defaultStartTime)
                        let startMinute = calendar.component(.minute, from: defaultStartTime)
                        let remindHour = calendar.component(.hour, from: leftoverRemindTime)
                        let remindMinute = calendar.component(.minute, from: leftoverRemindTime)

                        let contextFilter = ContextFilter(
                            calendarKeywords: keywords,
                            includeCalendar: includeCalendar,
                            includeReminders: includeReminders,
                            includeEmails: includeEmails,
                            includeTasks: includeTasks
                        )

                        let group = FocusGroup(
                            id: groupId,
                            name: name,
                            color: selectedColor,
                            description: description.isEmpty ? nil : description,
                            defaultStartTime: String(format: "%02d:%02d", startHour, startMinute),
                            defaultDurationMinutes: defaultDuration,
                            contextFilter: contextFilter,
                            autoRemindLeftover: autoRemindLeftover,
                            leftoverRemindTime: String(format: "%02d:%02d", remindHour, remindMinute)
                        )
                        onSave(group)

                        // Save keywords
                        if isEditing {
                            let oldKeywords = (try? Database.shared.getFocusGroupKeywords(forFocusGroup: groupId)) ?? []
                            for kw in oldKeywords {
                                try? Database.shared.removeFocusGroupKeyword(kw, fromFocusGroup: groupId)
                            }
                        }
                        for kw in keywords {
                            try? Database.shared.addFocusGroupKeyword(kw, toFocusGroup: groupId)
                        }

                        // Create recurring focus block if days are selected
                        if !selectedDays.isEmpty {
                            let byDay = selectedDays.map(\.rruleDay).joined(separator: ",")
                            let rule = "FREQ=WEEKLY;BYDAY=\(byDay)"

                            let startDate = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: Date()) ?? Date()
                            let endDate = startDate.addingTimeInterval(Double(defaultDuration * 60))

                            let block = FocusBlock(
                                groupId: groupId,
                                startTime: startDate,
                                endTime: endDate,
                                isRecurring: true,
                                recurrenceRule: rule
                            )
                            try? Database.shared.createFocusBlock(block)
                        }

                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
                }
            }
            .padding()
        }
        .frame(width: 420, height: 600)
        .task {
            if isEditing {
                keywords = (try? Database.shared.getFocusGroupKeywords(forFocusGroup: groupId)) ?? []

                // Load existing recurring block to populate selected days
                let blocks = (try? Database.shared.getFocusBlocksForGroup(id: groupId)) ?? []
                if let recurringBlock = blocks.first(where: { $0.isRecurring }),
                   let rule = recurringBlock.recurrenceRule,
                   let byDayRange = rule.range(of: "BYDAY=") {
                    let byDayStart = byDayRange.upperBound
                    let remaining = String(rule[byDayStart...])
                    let days = remaining.components(separatedBy: ";").first?.components(separatedBy: ",") ?? []
                    for day in days {
                        if let weekday = Weekday.fromRRule(day) {
                            selectedDays.insert(weekday)
                        }
                    }
                }
            }
        }
    }

    private func addKeyword() {
        let kw = newKeyword.trimmingCharacters(in: .whitespaces).lowercased()
        guard !kw.isEmpty, !keywords.contains(kw) else { return }
        keywords.append(kw)
        newKeyword = ""
    }

    private func removeKeyword(_ kw: String) {
        keywords.removeAll { $0 == kw }
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        case "indigo": return .indigo
        case "teal": return .teal
        default: return .blue
        }
    }
}

// MARK: - Weekday

enum Weekday: String, CaseIterable, Identifiable {
    case sunday = "S"
    case monday = "M"
    case tuesday = "T"
    case wednesday = "W"
    case thursday = "Th"
    case friday = "F"
    case saturday = "Sa"

    var id: String { rawValue }

    var rruleDay: String {
        switch self {
        case .sunday: return "SU"
        case .monday: return "MO"
        case .tuesday: return "TU"
        case .wednesday: return "WE"
        case .thursday: return "TH"
        case .friday: return "FR"
        case .saturday: return "SA"
        }
    }

    static func fromRRule(_ day: String) -> Weekday? {
        switch day.uppercased() {
        case "SU": return .sunday
        case "MO": return .monday
        case "TU": return .tuesday
        case "WE": return .wednesday
        case "TH": return .thursday
        case "FR": return .friday
        case "SA": return .saturday
        default: return nil
        }
    }
}

struct DayToggle: View {
    let day: Weekday
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(day.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}
