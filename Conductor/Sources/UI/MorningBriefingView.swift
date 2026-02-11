import SwiftUI

struct MorningBriefingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var events: [EventKitManager.CalendarEvent] = []
    @State private var tasks: [TodoTask] = []
    @State private var taskLists: [TaskList] = []
    @State private var weekGoals: [DailyGoal] = []
    @State private var actionEmails: [ProcessedEmail] = []
    @State private var emailCount: Int = 0
    @State private var isLoading: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    scheduleSection
                    tasksSection
                    goalsSection
                    emailSection
                }
                .padding()
            }
        }
        .frame(width: 420, height: 560)
        .onAppear { loadData() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(dateText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good Morning"
        } else if hour < 17 {
            return "Good Afternoon"
        } else {
            return "Good Evening"
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Today's Schedule", icon: "calendar")

            if events.isEmpty {
                Text("No events today")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            } else {
                // Timeline strip
                let timeBlocks = events.compactMap { event -> TimeBlock? in
                    guard !event.isAllDay else { return nil }
                    return TimeBlock(
                        id: event.id,
                        title: event.title,
                        startTime: event.startDate,
                        endTime: event.endDate,
                        color: .blue,
                        type: .event
                    )
                }

                if !timeBlocks.isEmpty {
                    TimelineStrip(events: timeBlocks, hours: 7...21)
                        .padding(.bottom, 4)
                }

                // Event list
                ForEach(events, id: \.id) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: EventKitManager.CalendarEvent) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.blue)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(event.time + (event.isAllDay ? "" : " (\(event.duration))"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let location = event.location, !location.isEmpty {
                Text(location)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tasks (\(tasks.count))", icon: "checklist")

            if tasks.isEmpty {
                Text("No tasks for today")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            } else {
                let grouped = groupedTasks
                ForEach(grouped.keys.sorted(), id: \.self) { groupName in
                    if let groupTasks = grouped[groupName] {
                        taskGroupView(name: groupName, tasks: groupTasks)
                    }
                }
            }
        }
    }

    private var groupedTasks: [String: [TodoTask]] {
        let listMap = Dictionary(uniqueKeysWithValues: taskLists.map { ($0.id, $0) })
        var groups: [String: [TodoTask]] = [:]

        for task in tasks {
            let groupName: String
            if let listId = task.listId, let list = listMap[listId] {
                groupName = list.name
            } else {
                groupName = "Misc"
            }
            groups[groupName, default: []].append(task)
        }

        return groups
    }

    private func taskGroupView(name: String, tasks: [TodoTask]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let listColor = taskLists.first(where: { $0.name == name })?.swiftUIColor ?? .secondary

            HStack(spacing: 6) {
                Circle()
                    .fill(listColor)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            ForEach(tasks, id: \.id) { task in
                taskRow(task, accentColor: listColor)
            }
        }
        .padding(.leading, 4)
    }

    private func taskRow(_ task: TodoTask, accentColor: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(task.isCompleted ? .green : accentColor)

            Text(task.title)
                .font(.callout)
                .lineLimit(1)
                .strikethrough(task.isCompleted)
                .foregroundColor(task.isCompleted ? .secondary : .primary)

            Spacer()

            if let priority = task.priority.icon {
                Image(systemName: priority)
                    .font(.caption2)
                    .foregroundColor(task.priority.color)
            }

            if let label = task.dueDateLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(task.isOverdue ? .red : .secondary)
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Week Goals", icon: "target")

            if weekGoals.isEmpty {
                Text("No goals set this week")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            } else {
                ForEach(weekGoals) { goal in
                    goalRow(goal)
                }
            }
        }
    }

    private func goalRow(_ goal: DailyGoal) -> some View {
        HStack(spacing: 8) {
            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(goal.isCompleted ? .green : .orange)

            Text(goal.goalText)
                .font(.callout)
                .lineLimit(2)
                .strikethrough(goal.isCompleted)
                .foregroundColor(goal.isCompleted ? .secondary : .primary)

            Spacer()
        }
        .padding(.vertical, 1)
    }

    // MARK: - Email Section

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Emails Needing Action (\(emailCount))", icon: "envelope.badge")

            if actionEmails.isEmpty {
                Text("No emails need action")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            } else {
                ForEach(actionEmails.prefix(5)) { email in
                    emailRow(email)
                }

                if emailCount > 5 {
                    Text("+ \(emailCount - 5) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
    }

    private func emailRow(_ email: ProcessedEmail) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope")
                .font(.caption)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(email.subject)
                    .font(.callout)
                    .lineLimit(1)
                Text(email.sender)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(email.formattedReceivedDate)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }

    private func loadData() {
        Task {
            // Fetch calendar events
            let loadedEvents = await EventKitManager.shared.getTodayEvents()

            // Fetch DB data on background thread
            let (loadedTasks, loadedLists, loadedGoals, loadedEmails, loadedEmailCount) = await Task.detached(priority: .userInitiated) {
                let tasks = (try? Database.shared.getTodayTasks(includeCompleted: true)) ?? []
                let lists = (try? Database.shared.getTaskLists()) ?? []

                // Get goals for the current week (Mon-Sun)
                let calendar = Calendar.current
                let today = Date()
                let weekday = calendar.component(.weekday, from: today)
                // weekday: 1 = Sunday, 2 = Monday, ...
                let daysToMonday = weekday == 1 ? -6 : -(weekday - 2)
                let monday = calendar.date(byAdding: .day, value: daysToMonday, to: today)!

                var goals: [DailyGoal] = []
                for offset in 0..<7 {
                    let date = calendar.date(byAdding: .day, value: offset, to: monday)!
                    let dateString = Self.dateString(from: date)
                    if let dayGoals = try? Database.shared.getGoalsForDate(dateString) {
                        goals.append(contentsOf: dayGoals)
                    }
                }

                let emails = (try? Database.shared.getProcessedEmails(filter: .actionNeeded, limit: 5)) ?? []
                let count = (try? Database.shared.getEmailActionNeededCount()) ?? 0

                return (tasks, lists, goals, emails, count)
            }.value

            await MainActor.run {
                events = loadedEvents
                tasks = loadedTasks
                taskLists = loadedLists
                weekGoals = loadedGoals
                actionEmails = loadedEmails
                emailCount = loadedEmailCount
                isLoading = false
            }
        }
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
