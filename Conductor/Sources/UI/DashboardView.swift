import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    @State private var weekEvents: [EventKitManager.CalendarEvent] = []

    private var sortedTodayEvents: [EventKitManager.CalendarEvent] {
        appState.todayEvents.sorted { $0.startDate < $1.startDate }
    }

    private var weekStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: today) ?? today
    }

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var openTasksThisWeek: [Todo] {
        appState.openTodos.filter { todo in
            guard let due = todo.dueDate else { return false }
            return due >= weekStart && due < weekEnd
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                quickActions
                summaryCards
                weekBoard
                todayAgenda
                todayTodos
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await refreshWeekEvents()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dashboard")
                .font(.title2.weight(.semibold))
            Text(SharedDateFormatters.fullDate.string(from: Date()))
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button {
                appState.openSurface(.calendar, in: .primary)
            } label: {
                Label("Open Calendar", systemImage: "calendar")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                appState.openSurface(.tasks, in: .secondary)
            } label: {
                Label("Review Tasks", systemImage: "checklist")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                appState.openSurface(.chat, in: .secondary)
            } label: {
                Label("Plan with Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            summaryCard(
                title: "Today's Events",
                value: "\(sortedTodayEvents.count)",
                subtitle: sortedTodayEvents.first?.title ?? "No meetings scheduled",
                tint: .blue
            )
            summaryCard(
                title: "Due Today",
                value: "\(appState.todayTodos.count)",
                subtitle: appState.todayTodos.first?.title ?? "No due tasks",
                tint: .orange
            )
            summaryCard(
                title: "Open Tasks",
                value: "\(appState.openTodos.count)",
                subtitle: "\(openTasksThisWeek.count) due this week",
                tint: .green
            )
        }
    }

    private func summaryCard(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(tint)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var weekBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Week")
                .font(.headline)

            ForEach(weekDays, id: \.self) { day in
                HStack(spacing: 10) {
                    Text(SharedDateFormatters.shortDayDate.string(from: day))
                        .font(.caption.weight(.medium))
                        .frame(width: 90, alignment: .leading)

                    let events = events(on: day)
                    let todos = todos(on: day)

                    Text("\(events.count) events")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.14))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())

                    Text("\(todos.count) tasks")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())

                    if let firstTitle = events.first?.title ?? todos.first?.title {
                        Text(firstTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var todayAgenda: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's Agenda")
                    .font(.headline)
                Spacer()
                Button("Open Full Calendar") {
                    appState.openSurface(.calendar)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }

            if sortedTodayEvents.isEmpty {
                Text("No events today.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedTodayEvents, id: \.id) { event in
                    HStack(spacing: 10) {
                        Text(event.time)
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 62, alignment: .trailing)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 16)
                        Text(event.title)
                            .font(.caption)
                        Spacer()
                        Text(event.duration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var todayTodos: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today's Tasks")
                    .font(.headline)
                Spacer()
                Button("Open Tasks") {
                    appState.openSurface(.tasks)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }

            if appState.todayTodos.isEmpty {
                Text("No tasks due today.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(appState.todayTodos, id: \.id) { todo in
                    TodoRowView(
                        todo: todo,
                        projectColor: nil,
                        onToggle: { appState.toggleTodoCompletion(todo.id!) },
                        onSelect: {
                            appState.selectTodo(todo.id)
                            appState.openSurface(.tasks, in: .secondary)
                        },
                        isSelected: appState.selectedTodoId == todo.id
                    )
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func events(on day: Date) -> [EventKitManager.CalendarEvent] {
        weekEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }
    }

    private func todos(on day: Date) -> [Todo] {
        appState.openTodos.filter { todo in
            guard let due = todo.dueDate else { return false }
            return Calendar.current.isDate(due, inSameDayAs: day)
        }
    }

    private func refreshWeekEvents() async {
        weekEvents = await EventKitManager.shared.getEvents(from: weekStart, to: weekEnd)
    }
}
