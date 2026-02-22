import SwiftUI

private enum CalendarScope: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
}

private struct WeekEventLayout: Identifiable {
    let id: String
    let event: EventKitManager.CalendarEvent
    let dayIndex: Int
    let startMinute: Int
    let endMinute: Int
    let columnIndex: Int
    let columnCount: Int
}

struct CalendarWorkspaceView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedDate: Date = Date()
    @State private var scope: CalendarScope = .week
    @State private var dayEvents: [EventKitManager.CalendarEvent] = []
    @State private var scopedEvents: [EventKitManager.CalendarEvent] = []

    private var calendar: Calendar { Calendar.current }
    private var weekStartDate: Date { weekStart(for: selectedDate) }
    private var weekDatesForSelection: [Date] { weekDates(around: selectedDate) }

    private var weekTimedEvents: [EventKitManager.CalendarEvent] {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStartDate) ?? weekStartDate
        return scopedEvents
            .filter { !$0.isAllDay }
            .filter { event in
                let day = calendar.startOfDay(for: event.startDate)
                return day >= weekStartDate && day < weekEnd
            }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate { return lhs.endDate < rhs.endDate }
                return lhs.startDate < rhs.startDate
            }
    }

    private var weekLayouts: [WeekEventLayout] {
        buildWeekLayouts(events: weekTimedEvents)
    }

    private var weekAllDayEventsByDay: [[EventKitManager.CalendarEvent]] {
        weekDatesForSelection.map { day in
            scopedEvents
                .filter { $0.isAllDay && calendar.isDate($0.startDate, inSameDayAs: day) }
                .sorted { $0.title < $1.title }
        }
    }

    private var dueDeliverablesThisWeek: [Todo] {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStartDate) ?? weekStartDate
        return appState.openTodos
            .filter { todo in
                guard let due = todo.dueDate else { return false }
                return due >= weekStartDate && due < weekEnd
            }
            .sorted { lhs, rhs in
                let lhsDue = lhs.dueDate ?? .distantFuture
                let rhsDue = rhs.dueDate ?? .distantFuture
                if lhsDue == rhsDue { return lhs.priority > rhs.priority }
                return lhsDue < rhsDue
            }
    }

    private var timelineStartHour: Int {
        let minHour = weekTimedEvents.map { calendar.component(.hour, from: $0.startDate) }.min() ?? 8
        return max(0, min(8, minHour - 1))
    }

    private var timelineEndHour: Int {
        let maxHour = weekTimedEvents.map { calendar.component(.hour, from: $0.endDate) + 1 }.max() ?? 18
        return min(24, max(18, maxHour + 1))
    }

    private var timelineHours: [Int] {
        Array(timelineStartHour..<timelineEndHour)
    }

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
                    if scope != .week {
                        agendaList(events: eventsForAgenda)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private var weekGrid: some View {
        let dayColumnWidth: CGFloat = 146
        let hourLabelWidth: CGFloat = 54
        let hourRowHeight: CGFloat = 54
        let headerHeight: CGFloat = 54
        let timelineHeight = CGFloat(max(timelineHours.count, 1)) * hourRowHeight
        let gridWidth = hourLabelWidth + (dayColumnWidth * 7)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Week Schedule")
                .font(.subheadline.weight(.semibold))

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .frame(width: gridWidth, height: headerHeight + timelineHeight)

                    ForEach(weekDatesForSelection.indices, id: \.self) { dayIndex in
                        let dayX = hourLabelWidth + CGFloat(dayIndex) * dayColumnWidth
                        Rectangle()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: 1, height: headerHeight + timelineHeight)
                            .offset(x: dayX, y: 0)

                        Text(SharedDateFormatters.shortDayDate.string(from: weekDatesForSelection[dayIndex]))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: dayColumnWidth - 10, alignment: .leading)
                            .offset(x: dayX + 8, y: 8)

                        let allDay = weekAllDayEventsByDay[dayIndex]
                        if !allDay.isEmpty {
                            let chipTitle = allDay[0].title
                            HStack(spacing: 4) {
                                Text(chipTitle)
                                    .lineLimit(1)
                                if allDay.count > 1 {
                                    Text("+\(allDay.count - 1)")
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.pink.opacity(0.15))
                            .foregroundColor(.pink)
                            .clipShape(Capsule())
                            .frame(width: dayColumnWidth - 12, alignment: .leading)
                            .offset(x: dayX + 6, y: 26)
                        }
                    }

                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: gridWidth, height: 1)
                        .offset(x: 0, y: headerHeight - 1)

                    ForEach(Array(timelineHours.enumerated()), id: \.offset) { idx, hour in
                        let y = headerHeight + CGFloat(idx) * hourRowHeight

                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: gridWidth, height: 1)
                            .offset(x: 0, y: y)

                        Text(timeLabel(hour: hour))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: hourLabelWidth - 8, alignment: .trailing)
                            .offset(x: 0, y: y - 7)
                    }

                    ForEach(weekLayouts) { layout in
                        let dayBaseX = hourLabelWidth + CGFloat(layout.dayIndex) * dayColumnWidth
                        let columnWidth = dayColumnWidth / CGFloat(max(layout.columnCount, 1))
                        let start = max(layout.startMinute, timelineStartHour * 60)
                        let end = min(layout.endMinute, timelineEndHour * 60)
                        if end > start {
                            let y = headerHeight + (CGFloat(start - (timelineStartHour * 60)) / 60.0 * hourRowHeight)
                            let eventHeight = max(18, CGFloat(end - start) / 60.0 * hourRowHeight)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(layout.event.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(2)
                                Text(SharedDateFormatters.shortTime.string(from: layout.event.startDate))
                                    .font(.system(size: 9))
                                    .opacity(0.8)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .frame(
                                width: max(columnWidth - 6, 20),
                                height: eventHeight,
                                alignment: .topLeading
                            )
                            .background(Color.blue.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.blue.opacity(0.4), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .offset(
                                x: dayBaseX + CGFloat(layout.columnIndex) * columnWidth + 3,
                                y: y
                            )
                        }
                    }
                }
                .frame(width: gridWidth, height: headerHeight + timelineHeight)
                .padding(.bottom, 4)
            }
            .frame(minHeight: 360, maxHeight: 500)

            if dueDeliverablesThisWeek.isEmpty {
                Text("No deliverables due this week.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deliverables Due")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    ForEach(dueDeliverablesThisWeek.prefix(8), id: \.id) { todo in
                        HStack(spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.orange)
                            Text(todo.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            if let due = todo.dueDate {
                                Text(SharedDateFormatters.shortDayDate.string(from: due))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
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

    private func timeLabel(hour: Int) -> String {
        let components = DateComponents(hour: hour)
        guard let date = calendar.date(from: components) else {
            return "\(hour):00"
        }
        return SharedDateFormatters.shortTime.string(from: date)
    }

    private func buildWeekLayouts(events: [EventKitManager.CalendarEvent]) -> [WeekEventLayout] {
        var layouts: [WeekEventLayout] = []

        for (dayIndex, day) in weekDatesForSelection.enumerated() {
            let dayEvents = events
                .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
                .sorted {
                    if $0.startDate == $1.startDate { return $0.endDate < $1.endDate }
                    return $0.startDate < $1.startDate
                }

            guard !dayEvents.isEmpty else { continue }

            var eventColumns: [(event: EventKitManager.CalendarEvent, column: Int)] = []
            var activeColumnEnds: [Date] = []

            for event in dayEvents {
                let column = nextAvailableColumn(start: event.startDate, activeColumnEnds: activeColumnEnds)
                if column < activeColumnEnds.count {
                    activeColumnEnds[column] = event.endDate
                } else {
                    activeColumnEnds.append(event.endDate)
                }
                eventColumns.append((event: event, column: column))
            }

            let columnCount = max(activeColumnEnds.count, 1)
            for item in eventColumns {
                let startMinute = calendar.component(.hour, from: item.event.startDate) * 60
                    + calendar.component(.minute, from: item.event.startDate)
                let endMinute = calendar.component(.hour, from: item.event.endDate) * 60
                    + calendar.component(.minute, from: item.event.endDate)

                layouts.append(
                    WeekEventLayout(
                        id: item.event.id,
                        event: item.event,
                        dayIndex: dayIndex,
                        startMinute: startMinute,
                        endMinute: max(endMinute, startMinute + 15),
                        columnIndex: item.column,
                        columnCount: columnCount
                    )
                )
            }
        }

        return layouts
    }

    private func nextAvailableColumn(start: Date, activeColumnEnds: [Date]) -> Int {
        for (index, endDate) in activeColumnEnds.enumerated() where endDate <= start {
            return index
        }
        return activeColumnEnds.count
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
