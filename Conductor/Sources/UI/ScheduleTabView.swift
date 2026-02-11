import SwiftUI
import AppKit

/// Calendar view mode
enum CalendarViewMode: String, CaseIterable {
    case agenda = "Agenda"
    case month = "Month"
    case week = "Week"

    var icon: String {
        switch self {
        case .agenda: return "list.bullet.rectangle"
        case .month: return "calendar"
        case .week: return "calendar.day.timeline.left"
        }
    }
}

/// Shows a proper calendar grid with events
struct ScheduleTabView: View {
    @State private var viewMode: CalendarViewMode = .agenda
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var monthEvents: [EventKitManager.CalendarEvent] = []
    @State private var weekEvents: [EventKitManager.CalendarEvent] = []
    @State private var selectedDayEvents: [EventKitManager.CalendarEvent] = []
    @State private var selectedDayTasks: [TodoTask] = []
    @State private var isLoading = false
    @State private var showDayDetail = false

    private let calendar = Calendar.current
    private let eventKitManager = EventKitManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with view mode picker
            headerView

            Divider()

            // Calendar content
            if isLoading && activeEvents.isEmpty {
                ProgressView("Loading calendar...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewMode {
                case .agenda:
                    agendaView
                case .month:
                    monthView
                case .week:
                    weekView
                }
            }
        }
        .focusable(true)
        .onMoveCommand { direction in
            handleMoveCommand(direction)
        }
        .task {
            switch viewMode {
            case .agenda, .week:
                await loadWeekEvents()
            case .month:
                await loadMonthEvents()
            }
            await loadSelectedDayTasks()
        }
        .onChange(of: currentMonth) { _, _ in
            Task {
                if viewMode == .month {
                    await loadMonthEvents()
                }
            }
        }
        .onChange(of: viewMode) { _, newMode in
            Task {
                switch newMode {
                case .agenda, .week:
                    await loadWeekEvents()
                case .month:
                    await loadMonthEvents()
                }
                await loadSelectedDayTasks()
            }
        }
        .onChange(of: selectedDate) { _, _ in
            currentMonth = selectedDate
            Task {
                if viewMode == .agenda || viewMode == .week {
                    await loadWeekEvents()
                }
                await loadSelectedDayTasks()
            }
        }
        .sheet(isPresented: $showDayDetail) {
            DayDetailView(
                date: selectedDate,
                events: selectedDayEvents,
                onDismiss: { showDayDetail = false }
            )
        }
        .overlay {
            // Cmd+T jumps to today.
            Button("") { jumpToToday() }
                .keyboardShortcut("t", modifiers: [.command])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            // Month navigation
            Button(action: previousPeriod) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(previousLabel)

            Text(headerTitle)
                .font(.headline)
                .frame(minWidth: 120)

            Button(action: nextPeriod) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nextLabel)

            Spacer()

            // Today button
            Button("Today") {
                jumpToToday()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // View mode picker
            Picker("View", selection: $viewMode) {
                ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Agenda View

    private var agendaView: some View {
        VStack(spacing: 0) {
            weekDayHeaders

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(selectedDateString)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        agendaSummaryPill
                    }

                    agendaCalendarSection

                    Divider()

                    agendaTasksSection
                }
                .padding(12)
            }
        }
    }

    private var agendaSummaryPill: some View {
        let auth = EventKitManager.shared.calendarAuthorizationStatus()
        let dayEvents = eventsForDay(selectedDate)

        let text: String = {
            if auth != .fullAccess { return "No calendar access" }
            if dayEvents.isEmpty { return "No events" }
            return "\(dayEvents.count) event\(dayEvents.count == 1 ? "" : "s")"
        }()

        return Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .accessibilityLabel(text)
    }

    private var agendaCalendarSection: some View {
        let auth = EventKitManager.shared.calendarAuthorizationStatus()
        let dayEvents = eventsForDay(selectedDate)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.caption)
                .foregroundColor(.secondary)

            if auth != .fullAccess {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Grant Full Access in System Settings to show your events here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open Calendar Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else if dayEvents.isEmpty {
                Text("No events")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(dayEvents, id: \.id) { event in
                        EventRow(event: event)
                            .onTapGesture {
                                selectedDayEvents = dayEvents
                                showDayDetail = true
                            }
                    }
                }
            }
        }
    }

    private var agendaTasksSection: some View {
        let tasks = selectedDayTasks

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !tasks.isEmpty {
                    Text("\(tasks.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if tasks.isEmpty {
                Text("No tasks due")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tasks, id: \.id) { task in
                        agendaTaskRow(task)
                    }
                }
            }
        }
    }

    private func agendaTaskRow(_ task: TodoTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(task.isCompleted ? .green : .secondary)
                .accessibilityLabel(task.isCompleted ? "Completed" : "Not completed")
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.callout)
                    .lineLimit(1)
                if let dueDate = task.dueDate {
                    Text(SharedDateFormatters.shortDayDate.string(from: dueDate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if task.priority == .high {
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
                    .accessibilityLabel("High priority")
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Month View

    private var monthView: some View {
        VStack(spacing: 0) {
            // Day headers
            dayHeaderRow

            Divider()

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(daysInMonthGrid, id: \.self) { date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            isCurrentMonth: calendar.isDate(date, equalTo: currentMonth, toGranularity: .month),
                            events: eventsForDay(date)
                        ) {
                            selectedDate = date
                            Task {
                                selectedDayEvents = await eventKitManager.getEventsForDay(date)
                                showDayDetail = true
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 50)
                    }
                }
            }

            Spacer()

            // Quick preview of selected day
            selectedDayPreview
        }
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }

    private var selectedDayPreview: some View {
        let dayEvents = eventsForDay(selectedDate)

        return VStack(alignment: .leading, spacing: 6) {
            Divider()

            HStack {
                Text(selectedDateString)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if !dayEvents.isEmpty {
                    Text("\(dayEvents.count) event\(dayEvents.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if dayEvents.isEmpty {
                Text("No events")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(dayEvents.prefix(3), id: \.id) { event in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                        Text(event.time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(event.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                if dayEvents.count > 3 {
                    Text("+ \(dayEvents.count - 3) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Week View

    private var weekView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Day headers for the week
                weekDayHeaders

                Divider()

                // Hour timeline
                ForEach(0..<24, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 0) {
                        // Hour label
                        Text(hourString(hour))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                            .padding(.trailing, 4)

                        // Events for each day at this hour
                        ForEach(weekDays, id: \.self) { date in
                            WeekHourCell(
                                date: date,
                                hour: hour,
                                events: eventsForDayAndHour(date, hour: hour)
                            )
                        }
                    }
                    .frame(height: 40)

                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
    }

    private var weekDayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: 44)

            ForEach(weekDays, id: \.self) { date in
                let count = eventsForDay(date).count
                Button {
                    selectedDate = date
                } label: {
                    VStack(spacing: 2) {
                        Text(dayOfWeekString(date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(dayNumberString(date))
                            .font(.callout)
                            .fontWeight(calendar.isDateInToday(date) ? .bold : .regular)
                            .foregroundColor(calendar.isDateInToday(date) ? .accentColor : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(calendar.isDate(date, inSameDayAs: selectedDate) ? Color.accentColor.opacity(0.1) : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(SharedDateFormatters.fullDateNoYear.string(from: date)), \(count) event\(count == 1 ? "" : "s")")
            }
        }
    }

    // MARK: - Helpers

    private var monthYearString: String {
        SharedDateFormatters.monthYear.string(from: currentMonth)
    }

    private var headerTitle: String {
        switch viewMode {
        case .month:
            return monthYearString
        case .week, .agenda:
            return weekRangeString(for: selectedDate)
        }
    }

    private var previousLabel: String {
        switch viewMode {
        case .month:
            return "Previous month"
        case .week, .agenda:
            return "Previous week"
        }
    }

    private var nextLabel: String {
        switch viewMode {
        case .month:
            return "Next month"
        case .week, .agenda:
            return "Next week"
        }
    }

    private var selectedDateString: String {
        SharedDateFormatters.fullDateNoYear.string(from: selectedDate)
    }

    private func dayOfWeekString(_ date: Date) -> String {
        SharedDateFormatters.shortDayOfWeek.string(from: date)
    }

    private func dayNumberString(_ date: Date) -> String {
        SharedDateFormatters.dayNumber.string(from: date)
    }

    private func hourString(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour == 12 { return "12 PM" }
        if hour < 12 { return "\(hour) AM" }
        return "\(hour - 12) PM"
    }

    private var daysInMonthGrid: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        var days: [Date?] = []
        var currentDate = firstWeek.start

        // Get 6 weeks (42 days) to ensure we cover all cases
        for _ in 0..<42 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return days
    }

    private var weekDays: [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return []
        }

        var days: [Date] = []
        var currentDate = weekInterval.start

        for _ in 0..<7 {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return days
    }

    private var activeEvents: [EventKitManager.CalendarEvent] {
        switch viewMode {
        case .agenda:
            return weekEvents
        case .month:
            return monthEvents
        case .week:
            return weekEvents
        }
    }

    private func eventsForDay(_ date: Date) -> [EventKitManager.CalendarEvent] {
        activeEvents.filter { event in
            calendar.isDate(event.startDate, inSameDayAs: date)
        }
    }

    private func eventsForDayAndHour(_ date: Date, hour: Int) -> [EventKitManager.CalendarEvent] {
        activeEvents.filter { event in
            guard calendar.isDate(event.startDate, inSameDayAs: date) else { return false }
            let eventHour = calendar.component(.hour, from: event.startDate)
            return eventHour == hour
        }
    }

    private func previousPeriod() {
        switch viewMode {
        case .month:
            if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
                currentMonth = newMonth
                selectedDate = newMonth
            }
        case .week, .agenda:
            if let newDate = calendar.date(byAdding: .day, value: -7, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }

    private func nextPeriod() {
        switch viewMode {
        case .month:
            if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
                currentMonth = newMonth
                selectedDate = newMonth
            }
        case .week, .agenda:
            if let newDate = calendar.date(byAdding: .day, value: 7, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }

    private func jumpToToday() {
        let today = Date()
        selectedDate = today
        currentMonth = today
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        let deltaDays: Int
        switch direction {
        case .left:
            deltaDays = -1
        case .right:
            deltaDays = 1
        case .up:
            deltaDays = -7
        case .down:
            deltaDays = 7
        default:
            return
        }

        guard let newDate = calendar.date(byAdding: .day, value: deltaDays, to: selectedDate) else { return }
        selectedDate = newDate
        currentMonth = newDate
    }

    private func weekRangeString(for date: Date) -> String {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return SharedDateFormatters.monthYear.string(from: date)
        }
        let start = SharedDateFormatters.shortMonthDay.string(from: interval.start)
        let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let end = SharedDateFormatters.shortMonthDay.string(from: endDate)
        return "\(start) – \(end)"
    }

    private func loadMonthEvents() async {
        isLoading = true
        defer { isLoading = false }

        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let gridEnd = calendar.date(byAdding: .day, value: 42, to: firstWeek.start) else {
            monthEvents = []
            return
        }

        // Load the visible 6-week grid, not just the month, so leading/trailing days show dots correctly.
        monthEvents = await eventKitManager.getEvents(from: firstWeek.start, to: gridEnd)
    }

    private func loadWeekEvents() async {
        isLoading = true
        defer { isLoading = false }

        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            weekEvents = []
            return
        }

        weekEvents = await eventKitManager.getEvents(from: interval.start, to: interval.end)
    }

    private func loadSelectedDayTasks() async {
        let date = selectedDate
        let tasks = await Task.detached(priority: .utility) {
            (try? Database.shared.getTasksForDay(date, includeCompleted: false, includeOverdue: true)) ?? []
        }.value
        await MainActor.run {
            selectedDayTasks = tasks
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let events: [EventKitManager.CalendarEvent]
    let onTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.callout)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(textColor)

                // Event dots
                if !events.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(0..<min(events.count, 3), id: \.self) { _ in
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    Color.clear.frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(backgroundColor)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let dateText = SharedDateFormatters.fullDate.string(from: date)
        if events.isEmpty {
            return "\(dateText), no events"
        }
        let eventWord = events.count == 1 ? "event" : "events"
        return "\(dateText), \(events.count) \(eventWord)"
    }

    private var textColor: Color {
        if isSelected {
            return .white
        }
        if !isCurrentMonth {
            return .secondary.opacity(0.5)
        }
        if isToday {
            return .accentColor
        }
        return .primary
    }

    private var backgroundColor: Color {
        if isSelected {
            return .accentColor
        }
        if isToday {
            return .accentColor.opacity(0.1)
        }
        return .clear
    }
}

// MARK: - Week Hour Cell

struct WeekHourCell: View {
    let date: Date
    let hour: Int
    let events: [EventKitManager.CalendarEvent]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity)

            if !events.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(events.prefix(2), id: \.id) { event in
                        Text(event.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(2)
                    }
                }
                .padding(2)
            }
        }
        .frame(maxWidth: .infinity)
        .border(Color.secondary.opacity(0.1), width: 0.5)
    }
}

// MARK: - Day Detail View

struct DayDetailView: View {
    let date: Date
    let events: [EventKitManager.CalendarEvent]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(dateString)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Events list
            if events.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No events")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(events, id: \.id) { event in
                            EventRow(event: event)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 350, height: 400)
    }

    private var dateString: String {
        SharedDateFormatters.fullDate.string(from: date)
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: EventKitManager.CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body)
                    .fontWeight(.medium)

                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.isAllDay ? "All day" : "\(event.time) (\(event.duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let location = event.location, !location.isEmpty {
                    HStack {
                        Image(systemName: "location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let notes = event.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    ScheduleTabView()
        .frame(width: 400, height: 500)
}
