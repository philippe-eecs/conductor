import SwiftUI

private enum CalendarScope: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
}

struct CalendarWorkspaceView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedDate: Date = Date()
    @State private var scope: CalendarScope = .week
    @State private var dayEvents: [EventKitManager.CalendarEvent] = []
    @State private var scopedEvents: [EventKitManager.CalendarEvent] = []

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        Group {
            if !appState.hasCalendarAccess {
                noAccessView
            } else {
                HSplitView {
                    leftRail
                        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
                    eventBoard
                        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: refreshKey) {
            await refresh()
        }
    }

    private var refreshKey: String {
        "\(scope.rawValue)-\(SharedDateFormatters.databaseDate.string(from: selectedDate))"
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar")
                .font(.title3.weight(.semibold))

            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            Divider()

            Text("This Week")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(weekDates(around: selectedDate), id: \.self) { day in
                Button {
                    selectedDate = day
                    scope = .day
                } label: {
                    HStack {
                        Text(SharedDateFormatters.shortDayDate.string(from: day))
                            .font(.caption)
                        Spacer()
                        let count = scopedEvents.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        calendar.isDate(day, inSameDayAs: selectedDate)
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var eventBoard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(titleForScope)
                    .font(.headline)
                Spacer()
                Picker("Scope", selection: $scope) {
                    ForEach(CalendarScope.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if scope == .week {
                        weekGrid
                    }
                    if scope == .month {
                        monthSummary
                    }
                    agendaList(events: eventsForAgenda)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private var weekGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week Overview")
                .font(.subheadline.weight(.semibold))

            ForEach(weekDates(around: selectedDate), id: \.self) { day in
                let events = scopedEvents.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
                HStack(spacing: 10) {
                    Text(SharedDateFormatters.shortDayDate.string(from: day))
                        .font(.caption.weight(.medium))
                        .frame(width: 88, alignment: .leading)

                    Text("\(events.count) events")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.14))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())

                    if let title = events.first?.title {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("No events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var monthSummary: some View {
        let grouped = Dictionary(grouping: scopedEvents) { event in
            calendar.startOfDay(for: event.startDate)
        }
        let sortedDays = grouped.keys.sorted()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Month Overview")
                .font(.subheadline.weight(.semibold))

            if sortedDays.isEmpty {
                Text("No events in this month.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedDays, id: \.self) { day in
                    HStack(spacing: 8) {
                        Text(SharedDateFormatters.shortDayDate.string(from: day))
                            .font(.caption.weight(.medium))
                            .frame(width: 88, alignment: .leading)
                        Text("\(grouped[day]?.count ?? 0) events")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func agendaList(events: [EventKitManager.CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scope == .day ? "Agenda" : "Events")
                .font(.subheadline.weight(.semibold))

            if events.isEmpty {
                Text("No events in this range.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(events, id: \.id) { event in
                    HStack(spacing: 8) {
                        Text(event.isAllDay ? "All day" : SharedDateFormatters.shortTime.string(from: event.startDate))
                            .font(.caption2.monospacedDigit())
                            .frame(width: 60, alignment: .trailing)
                            .foregroundColor(.secondary)

                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.accentColor)
                            .frame(width: 2, height: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.caption)
                            if let location = event.location, !location.isEmpty {
                                Text(location)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(event.duration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var eventsForAgenda: [EventKitManager.CalendarEvent] {
        switch scope {
        case .day:
            return dayEvents
        case .week, .month:
            return scopedEvents
        }
    }

    private var noAccessView: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Calendar access is not enabled.")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Enable Calendar permissions in Settings to see your schedule.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titleForScope: String {
        switch scope {
        case .day:
            return SharedDateFormatters.fullDate.string(from: selectedDate)
        case .week:
            return "Week of \(SharedDateFormatters.shortMonthDay.string(from: weekStart(for: selectedDate)))"
        case .month:
            return monthTitle(for: selectedDate)
        }
    }

    private func weekStart(for date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: startOfDay) ?? startOfDay
    }

    private func weekDates(around date: Date) -> [Date] {
        let start = weekStart(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func refresh() async {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        dayEvents = await EventKitManager.shared.getEvents(from: dayStart, to: dayEnd)

        let range: (Date, Date)
        switch scope {
        case .day:
            range = (dayStart, dayEnd)
        case .week:
            let start = weekStart(for: selectedDate)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            range = (start, end)
        case .month:
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            let start = calendar.date(from: components) ?? dayStart
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            range = (start, end)
        }

        scopedEvents = await EventKitManager.shared.getEvents(from: range.0, to: range.1)
    }
}
