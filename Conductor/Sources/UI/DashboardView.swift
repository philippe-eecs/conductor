import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    private var sortedTodayEvents: [EventKitManager.CalendarEvent] {
        appState.todayEvents.sorted { $0.startDate < $1.startDate }
    }

    private var upcomingTasks: [Todo] {
        appState.openTodos
            .filter { $0.dueDate != nil }
            .sorted {
                let lhs = $0.dueDate ?? .distantFuture
                let rhs = $1.dueDate ?? .distantFuture
                if lhs == rhs { return $0.priority > $1.priority }
                return lhs < rhs
            }
    }

    private var videoTasks: [Todo] {
        appState.openTodos.filter { todo in
            let titleHit = todo.title.localizedCaseInsensitiveContains("video")
            guard !titleHit else { return true }
            guard let projectId = todo.projectId else { return false }
            let projectName = appState.projects.first { $0.project.id == projectId }?.project.name ?? ""
            return projectName.localizedCaseInsensitiveContains("video")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                calendarCard
                tasksCard
                videoCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await appState.loadTodayData()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dashboard")
                .font(.title2.weight(.semibold))
            Text(SharedDateFormatters.fullDate.string(from: Date()))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calendar")
                    .font(.headline)
                Spacer()
                Button("Open") {
                    appState.openSurface(.calendar, in: .primary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if sortedTodayEvents.isEmpty {
                Text("No events today.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedTodayEvents.prefix(6), id: \.id) { event in
                    HStack(spacing: 8) {
                        Text(event.time)
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 58, alignment: .trailing)
                        Text(event.title)
                            .font(.caption)
                            .lineLimit(1)
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

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks")
                    .font(.headline)
                Spacer()
                Button("Open") {
                    appState.openSurface(.tasks, in: .primary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if upcomingTasks.isEmpty {
                Text("No tasks with due dates.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(upcomingTasks.prefix(6), id: \.id) { todo in
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(todo.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if let due = todo.dueDate {
                            Text(SharedDateFormatters.shortMonthDay.string(from: due))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var videoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Video Tasks")
                .font(.headline)

            if videoTasks.isEmpty {
                Text("No video-related tasks found.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(videoTasks.prefix(5), id: \.id) { todo in
                    HStack(spacing: 8) {
                        Image(systemName: "video")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(todo.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if let due = todo.dueDate {
                            Text(SharedDateFormatters.shortMonthDay.string(from: due))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
