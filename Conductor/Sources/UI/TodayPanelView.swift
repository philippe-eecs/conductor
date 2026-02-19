import SwiftUI

struct TodayPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var isCollapsed = false

    private var allDayEvents: [EventKitManager.CalendarEvent] {
        appState.todayEvents
            .filter(\.isAllDay)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var timedEvents: [EventKitManager.CalendarEvent] {
        appState.todayEvents
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Today", systemImage: "calendar")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                        Text(SharedDateFormatters.fullDate.string(from: Date()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("\(appState.todayEvents.count) events")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())

                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !allDayEvents.isEmpty {
                            sectionTitle("All-Day")
                            ForEach(allDayEvents, id: \.id) { event in
                                eventRow(event, isActive: false, leadingText: "All day")
                            }
                        }

                        if !timedEvents.isEmpty {
                            if !allDayEvents.isEmpty {
                                Divider().padding(.vertical, 2)
                            }
                            sectionTitle("Timeline")
                            timedEventsWithNow(timedEvents)
                        }

                        if !appState.todayTodos.isEmpty {
                            Divider().padding(.vertical, 2)
                            sectionTitle("Due Today")
                            ForEach(appState.todayTodos, id: \.id) { todo in
                                todoRow(todo)
                            }
                        }

                        if appState.todayEvents.isEmpty && appState.todayTodos.isEmpty {
                            HStack {
                                Spacer()
                                Text("No events or due todos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 16)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func timedEventsWithNow(_ timed: [EventKitManager.CalendarEvent]) -> some View {
        let now = Date()
        let nowIndex = timed.firstIndex(where: { $0.startDate > now }) ?? timed.count

        ForEach(Array(timed.enumerated()), id: \.element.id) { index, event in
            if index == nowIndex {
                nowIndicator
            }
            eventRow(
                event,
                isActive: event.startDate <= now && now < event.endDate,
                leadingText: SharedDateFormatters.shortTime.string(from: event.startDate)
            )
        }

        if nowIndex == timed.count && !timed.isEmpty {
            nowIndicator
        }
    }

    private func eventRow(
        _ event: EventKitManager.CalendarEvent,
        isActive: Bool,
        leadingText: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(leadingText)
                .font(.caption2.monospacedDigit())
                .foregroundColor(isActive ? .accentColor : .secondary)
                .frame(width: 56, alignment: .trailing)

            RoundedRectangle(cornerRadius: 1)
                .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 2, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(event.duration)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func todoRow(_ todo: Todo) -> some View {
        TodoRowView(
            todo: todo,
            projectColor: nil,
            onToggle: { appState.toggleTodoCompletion(todo.id!) },
            onSelect: { appState.selectTodo(todo.id) },
            isSelected: appState.selectedTodoId == todo.id
        )
    }

    private var nowIndicator: some View {
        HStack(spacing: 6) {
            Text("Now")
                .font(.caption2.weight(.bold))
                .foregroundColor(.red)
                .frame(width: 56, alignment: .trailing)

            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
    }
}
