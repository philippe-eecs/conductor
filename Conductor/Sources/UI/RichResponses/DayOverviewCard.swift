import SwiftUI

/// Data for day overview display
struct DayOverviewData: Codable, Equatable {
    let date: Date
    let events: [TimeBlockData]
    let tasks: [TaskData]
    let goals: [GoalData]
    let actionEmails: Int

    struct TimeBlockData: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let startTime: Date
        let endTime: Date
        let colorName: String
        let type: String  // "event" or "focusBlock"
    }

    struct TaskData: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let isCompleted: Bool
        let priority: String
        let dueTime: Date?
    }

    struct GoalData: Codable, Equatable, Identifiable {
        let id: String
        let text: String
        let isCompleted: Bool
        let priority: Int
    }
}

/// Visual day summary card
struct DayOverviewCard: View {
    let data: DayOverviewData

    private var timeBlocks: [TimeBlock] {
        data.events.map { event in
            TimeBlock(
                id: event.id,
                title: event.title,
                startTime: event.startTime,
                endTime: event.endTime,
                color: colorFromName(event.colorName),
                type: event.type == "focusBlock" ? .focusBlock : .event
            )
        }
    }

    private var eventCount: Int {
        data.events.filter { $0.type == "event" }.count
    }

    private var focusBlockCount: Int {
        data.events.filter { $0.type == "focusBlock" }.count
    }

    private var pendingTaskCount: Int {
        data.tasks.filter { !$0.isCompleted }.count
    }

    private var completedGoalCount: Int {
        data.goals.filter { $0.isCompleted }.count
    }

    private var bigItems: [AnyHashable] {
        // High priority tasks and goals
        let highPriorityTasks = data.tasks.filter { $0.priority == "high" && !$0.isCompleted }
        let pendingGoals = data.goals.filter { !$0.isCompleted }
        return Array((highPriorityTasks.map { AnyHashable($0.id) } + pendingGoals.map { AnyHashable($0.id) }).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            dateHeader

            // Mini timeline (8am-8pm)
            TimelineStrip(events: timeBlocks, hours: 8...20)

            // Summary chips
            summaryChips

            // Big agenda items (high-priority tasks, goals)
            if !data.goals.isEmpty || !data.tasks.filter({ $0.priority == "high" && !$0.isCompleted }).isEmpty {
                Divider()
                agendaSection
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var dateHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate)
                    .font(.headline)
                if isToday {
                    Text("Today")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            Spacer()
            if data.actionEmails > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "envelope.badge")
                        .font(.caption)
                    Text("\(data.actionEmails)")
                        .font(.caption)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }

    private var summaryChips: some View {
        HStack(spacing: 12) {
            if eventCount > 0 {
                summaryChip(
                    icon: "calendar",
                    count: eventCount,
                    label: eventCount == 1 ? "meeting" : "meetings",
                    color: .blue
                )
            }

            if focusBlockCount > 0 {
                summaryChip(
                    icon: "target",
                    count: focusBlockCount,
                    label: focusBlockCount == 1 ? "focus block" : "focus blocks",
                    color: .green
                )
            }

            if pendingTaskCount > 0 {
                summaryChip(
                    icon: "checklist",
                    count: pendingTaskCount,
                    label: pendingTaskCount == 1 ? "task" : "tasks",
                    color: .purple
                )
            }

            if !data.goals.isEmpty {
                summaryChip(
                    icon: "flag",
                    count: completedGoalCount,
                    label: "of \(data.goals.count) goals",
                    color: .orange
                )
            }

            Spacer()
        }
    }

    private func summaryChip(icon: String, count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text("\(count) \(label)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Priorities")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            // Goals
            ForEach(data.goals.filter { !$0.isCompleted }.prefix(2)) { goal in
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(goal.text)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                }
            }

            // High priority tasks
            ForEach(data.tasks.filter { $0.priority == "high" && !$0.isCompleted }.prefix(2)) { task in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(task.title)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    if let dueTime = task.dueTime {
                        Text(SharedDateFormatters.time12Hour.string(from: dueTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: data.date)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(data.date)
    }

    private func colorFromName(_ name: String) -> Color {
        switch name.lowercased() {
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

#Preview {
    let calendar = Calendar.current
    let now = Date()

    let data = DayOverviewData(
        date: now,
        events: [
            DayOverviewData.TimeBlockData(
                id: "1",
                title: "Team standup",
                startTime: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!,
                endTime: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now)!,
                colorName: "blue",
                type: "event"
            ),
            DayOverviewData.TimeBlockData(
                id: "2",
                title: "Deep work",
                startTime: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)!,
                endTime: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!,
                colorName: "green",
                type: "focusBlock"
            )
        ],
        tasks: [
            DayOverviewData.TaskData(id: "t1", title: "Review PR", isCompleted: false, priority: "high", dueTime: nil),
            DayOverviewData.TaskData(id: "t2", title: "Write docs", isCompleted: false, priority: "medium", dueTime: nil)
        ],
        goals: [
            DayOverviewData.GoalData(id: "g1", text: "Ship feature X", isCompleted: false, priority: 1),
            DayOverviewData.GoalData(id: "g2", text: "Code review", isCompleted: true, priority: 2)
        ],
        actionEmails: 3
    )

    return DayOverviewCard(data: data)
        .frame(width: 350)
        .padding()
}
