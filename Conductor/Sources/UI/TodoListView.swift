import SwiftUI

/// Smart list types
enum SmartList: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case scheduled = "Scheduled"
    case flagged = "Flagged"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .today: return "star"
        case .scheduled: return "calendar"
        case .flagged: return "flag"
        }
    }

    var color: Color {
        switch self {
        case .all: return .secondary
        case .today: return .blue
        case .scheduled: return .orange
        case .flagged: return .red
        }
    }
}

/// Grouping modes for task display
enum TaskGrouping: String, CaseIterable {
    case byTime = "By Time"
    case byPriority = "By Priority"

    var icon: String {
        switch self {
        case .byTime: return "clock"
        case .byPriority: return "exclamationmark.triangle"
        }
    }
}

/// TODO list view with sidebar and flexible grouping
struct TodoListView: View {
    @State private var selectedSmartList: SmartList? = .today
    @State private var selectedUserList: TaskList?
    @State private var tasks: [TodoTask] = []
    @State private var taskLists: [TaskList] = []
    @State private var grouping: TaskGrouping = .byTime
    @State private var showCompleted = false
    @State private var newTaskTitle = ""
    @State private var showNewListSheet = false
    @State private var showTaskDetail: TodoTask?
    @State private var isLoading = false

    @FocusState private var isNewTaskFocused: Bool

    var body: some View {
        HSplitView {
            // Sidebar
            sidebarView
                .frame(minWidth: 120, idealWidth: 140, maxWidth: 180)

            // Main content
            mainContentView
        }
        .task {
            await loadData()
        }
        .sheet(isPresented: $showNewListSheet) {
            NewListSheet(onSave: { name, color, icon in
                Task {
                    _ = try? Database.shared.createTaskList(name: name, color: color, icon: icon)
                    await loadData()
                }
            })
        }
        .sheet(item: $showTaskDetail) { task in
            TaskDetailSheet(
                task: task,
                lists: taskLists,
                onSave: { updatedTask in
                    Task {
                        try? Database.shared.updateTask(updatedTask)
                        await loadData()
                    }
                },
                onDelete: { taskId in
                    Task {
                        try? Database.shared.deleteTask(id: taskId)
                        await loadData()
                    }
                }
            )
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Smart Lists
            Section {
                ForEach(SmartList.allCases) { smartList in
                    SidebarRow(
                        title: smartList.rawValue,
                        icon: smartList.icon,
                        color: smartList.color,
                        count: countForSmartList(smartList),
                        isSelected: selectedSmartList == smartList && selectedUserList == nil
                    ) {
                        selectedSmartList = smartList
                        selectedUserList = nil
                        Task { await loadTasks() }
                    }
                }
            } header: {
                Text("Smart Lists")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }

            Divider()
                .padding(.vertical, 8)

            // User Lists
            Section {
                ForEach(taskLists) { list in
                    SidebarRow(
                        title: list.name,
                        icon: list.icon,
                        color: list.swiftUIColor,
                        count: countForList(list.id),
                        isSelected: selectedUserList?.id == list.id
                    ) {
                        selectedUserList = list
                        selectedSmartList = nil
                        Task { await loadTasks() }
                    }
                    .contextMenu {
                        Button("Delete List", role: .destructive) {
                            Task {
                                try? Database.shared.deleteTaskList(id: list.id)
                                if selectedUserList?.id == list.id {
                                    selectedUserList = nil
                                    selectedSmartList = .all
                                }
                                await loadData()
                            }
                        }
                    }
                }

                // Add list button
                Button(action: { showNewListSheet = true }) {
                    Label("Add List", systemImage: "plus")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } header: {
                Text("My Lists")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Main Content

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Task list
            if isLoading && tasks.isEmpty {
                ProgressView("Loading tasks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tasks.isEmpty {
                emptyStateView
            } else {
                taskListView
            }

            Divider()

            // Quick add
            quickAddView
        }
    }

    private var headerView: some View {
        HStack {
            // Title
            if let userList = selectedUserList {
                Image(systemName: userList.icon)
                    .foregroundColor(userList.swiftUIColor)
                Text(userList.name)
                    .font(.headline)
            } else if let smartList = selectedSmartList {
                Image(systemName: smartList.icon)
                    .foregroundColor(smartList.color)
                Text(smartList.rawValue)
                    .font(.headline)
            }

            Spacer()

            // Grouping picker (only for All view)
            if selectedSmartList == .all {
                Picker("Group", selection: $grouping) {
                    ForEach(TaskGrouping.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: grouping) { _, _ in
                    Task { await loadTasks() }
                }
            }

            // Show completed toggle
            Toggle(isOn: $showCompleted) {
                Image(systemName: "checkmark.circle")
            }
            .toggleStyle(.button)
            .help("Show completed tasks")
            .onChange(of: showCompleted) { _, _ in
                Task { await loadTasks() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var taskListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if selectedSmartList == .all && grouping == .byTime {
                    // Group by time
                    taskSection("Overdue", tasks: tasks.filter { $0.isOverdue })
                    taskSection("Today", tasks: tasks.filter { $0.isDueToday && !$0.isOverdue })
                    taskSection("Tomorrow", tasks: tasks.filter { $0.isDueTomorrow })
                    taskSection("This Week", tasks: tasks.filter { $0.isDueThisWeek && !$0.isDueToday && !$0.isDueTomorrow && !$0.isOverdue })
                    taskSection("Later", tasks: tasks.filter { !$0.isDueThisWeek && !$0.isOverdue && $0.dueDate != nil })
                    taskSection("Someday", tasks: tasks.filter { $0.dueDate == nil })
                } else if selectedSmartList == .all && grouping == .byPriority {
                    // Group by priority
                    taskSection("High Priority", tasks: tasks.filter { $0.priority == .high })
                    taskSection("Medium Priority", tasks: tasks.filter { $0.priority == .medium })
                    taskSection("Low Priority", tasks: tasks.filter { $0.priority == .low })
                    taskSection("No Priority", tasks: tasks.filter { $0.priority == .none })
                } else {
                    // No grouping
                    ForEach(tasks) { task in
                        TaskRow(task: task, onToggle: {
                            Task {
                                try? Database.shared.toggleTaskCompleted(id: task.id)
                                await loadTasks()
                            }
                        }, onTap: {
                            showTaskDetail = task
                        })
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func taskSection(_ title: String, tasks: [TodoTask]) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ForEach(tasks) { task in
                    TaskRow(task: task, onToggle: {
                        Task {
                            try? Database.shared.toggleTaskCompleted(id: task.id)
                            await loadTasks()
                        }
                    }, onTap: {
                        showTaskDetail = task
                    })
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(emptyStateMessage)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if let smartList = selectedSmartList {
            switch smartList {
            case .all: return "No tasks yet.\nAdd one below!"
            case .today: return "Nothing due today.\nEnjoy your day!"
            case .scheduled: return "No scheduled tasks.\nAdd due dates to see them here."
            case .flagged: return "No flagged tasks.\nMark important tasks as high priority."
            }
        } else if selectedUserList != nil {
            return "No tasks in this list.\nAdd one below!"
        }
        return "No tasks"
    }

    private var quickAddView: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.accentColor)

            TextField("Add task...", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .focused($isNewTaskFocused)
                .onSubmit {
                    addTask()
                }

            if !newTaskTitle.isEmpty {
                Button("Add") {
                    addTask()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        taskLists = (try? Database.shared.getTaskLists()) ?? []
        await loadTasks()
    }

    private func loadTasks() async {
        if let smartList = selectedSmartList {
            switch smartList {
            case .all:
                tasks = (try? Database.shared.getAllTasks(includeCompleted: showCompleted)) ?? []
            case .today:
                tasks = (try? Database.shared.getTodayTasks(includeCompleted: showCompleted)) ?? []
            case .scheduled:
                tasks = (try? Database.shared.getScheduledTasks(includeCompleted: showCompleted)) ?? []
            case .flagged:
                tasks = (try? Database.shared.getFlaggedTasks(includeCompleted: showCompleted)) ?? []
            }
        } else if let userList = selectedUserList {
            tasks = (try? Database.shared.getTasksForList(userList.id, includeCompleted: showCompleted)) ?? []
        }
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        // Parse natural language (simple version)
        let (parsedTitle, dueDate, listId) = parseTaskInput(title)

        let task = TodoTask(
            title: parsedTitle,
            dueDate: dueDate,
            listId: listId ?? selectedUserList?.id
        )

        Task {
            try? Database.shared.createTask(task)
            newTaskTitle = ""
            await loadTasks()
        }
    }

    /// Simple natural language parser for task input
    /// Supports: "Call mom tomorrow", "Buy groceries #personal", "Meeting at 3pm"
    private func parseTaskInput(_ input: String) -> (title: String, dueDate: Date?, listId: String?) {
        var title = input
        var dueDate: Date?
        var listId: String?

        // Check for list hashtag
        if let hashRange = title.range(of: #"\s*#(\w+)\s*$"#, options: .regularExpression) {
            let tag = String(title[hashRange]).trimmingCharacters(in: .whitespaces).dropFirst()
            title = String(title[..<hashRange.lowerBound])

            // Find matching list
            if let list = taskLists.first(where: { $0.name.lowercased() == tag.lowercased() }) {
                listId = list.id
            }
        }

        // Check for time keywords
        let lowercased = title.lowercased()
        let calendar = Calendar.current

        if lowercased.contains("today") {
            dueDate = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: Date())
            title = title.replacingOccurrences(of: "today", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
        } else if lowercased.contains("tomorrow") {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) {
                dueDate = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow)
            }
            title = title.replacingOccurrences(of: "tomorrow", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
        } else if lowercased.contains("next week") {
            if let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) {
                dueDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextWeek)
            }
            title = title.replacingOccurrences(of: "next week", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
        }

        return (title, dueDate, listId)
    }

    private func countForSmartList(_ list: SmartList) -> Int {
        switch list {
        case .all:
            return (try? Database.shared.getAllTasks(includeCompleted: false).count) ?? 0
        case .today:
            return (try? Database.shared.getTodayTasks(includeCompleted: false).count) ?? 0
        case .scheduled:
            return (try? Database.shared.getScheduledTasks(includeCompleted: false).count) ?? 0
        case .flagged:
            return (try? Database.shared.getFlaggedTasks(includeCompleted: false).count) ?? 0
        }
    }

    private func countForList(_ listId: String) -> Int {
        return (try? Database.shared.getTasksForList(listId, includeCompleted: false).count) ?? 0
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)

                Text(title)
                    .lineLimit(1)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: TodoTask
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .strikethrough(task.isCompleted)
                        .foregroundColor(task.isCompleted ? .secondary : .primary)

                    if task.priority != .none, let icon = task.priority.icon {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundColor(task.priority.color)
                    }
                }

                HStack(spacing: 8) {
                    if let dueLabel = task.dueDateLabel {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(dueLabel)
                                .font(.caption)
                        }
                        .foregroundColor(task.isOverdue ? .red : .secondary)
                    }

                    if task.notes != nil {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - New List Sheet

struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedColor = "blue"
    @State private var selectedIcon = "list.bullet"

    let onSave: (String, String, String) -> Void

    private let colors = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "gray"]
    private let icons = ["list.bullet", "folder", "star", "heart", "bookmark", "tag", "briefcase", "house"]

    var body: some View {
        VStack(spacing: 16) {
            Text("New List")
                .font(.headline)

            TextField("List name", text: $name)
                .textFieldStyle(.roundedBorder)

            // Color picker
            HStack {
                Text("Color")
                    .foregroundColor(.secondary)
                Spacer()
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(colorFor(color))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                        )
                        .onTapGesture { selectedColor = color }
                }
            }

            // Icon picker
            HStack {
                Text("Icon")
                    .foregroundColor(.secondary)
                Spacer()
                ForEach(icons, id: \.self) { icon in
                    Image(systemName: icon)
                        .frame(width: 28, height: 28)
                        .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                        .onTapGesture { selectedIcon = icon }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Create") {
                    onSave(name, selectedColor, selectedIcon)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
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
        default: return .blue
        }
    }
}

// MARK: - Task Detail Sheet

struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var task: TodoTask
    let lists: [TaskList]
    let onSave: (TodoTask) -> Void
    let onDelete: (String) -> Void

    init(task: TodoTask, lists: [TaskList], onSave: @escaping (TodoTask) -> Void, onDelete: @escaping (String) -> Void) {
        _task = State(initialValue: task)
        self.lists = lists
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Text("Task Details")
                    .font(.headline)
                Spacer()
                Button("Save") {
                    onSave(task)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                TextField("Title", text: $task.title)

                Section("Notes") {
                    TextEditor(text: Binding(
                        get: { task.notes ?? "" },
                        set: { task.notes = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(height: 80)
                }

                DatePicker(
                    "Due Date",
                    selection: Binding(
                        get: { task.dueDate ?? Date() },
                        set: { task.dueDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )

                Toggle("Has Due Date", isOn: Binding(
                    get: { task.dueDate != nil },
                    set: { if !$0 { task.dueDate = nil } else { task.dueDate = Date() } }
                ))

                Picker("List", selection: $task.listId) {
                    Text("None").tag(nil as String?)
                    ForEach(lists) { list in
                        Label(list.name, systemImage: list.icon)
                            .tag(list.id as String?)
                    }
                }

                Picker("Priority", selection: $task.priority) {
                    ForEach(TodoTask.Priority.allCases, id: \.self) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
            }
            .formStyle(.grouped)

            // Delete button
            Button(role: .destructive) {
                onDelete(task.id)
                dismiss()
            } label: {
                Label("Delete Task", systemImage: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding()
        }
        .frame(width: 400, height: 500)
    }
}

#Preview {
    TodoListView()
        .frame(width: 500, height: 400)
}
