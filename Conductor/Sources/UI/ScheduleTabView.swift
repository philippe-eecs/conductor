import SwiftUI

/// Calendar view mode
enum CalendarViewMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"

    var icon: String {
        switch self {
        case .month: return "calendar"
        case .week: return "calendar.day.timeline.left"
        }
    }
}

/// Shows a proper calendar grid with events
struct ScheduleTabView: View {
    @State private var viewMode: CalendarViewMode = .month
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var monthEvents: [EventKitManager.CalendarEvent] = []
    @State private var weekEvents: [EventKitManager.CalendarEvent] = []
    @State private var selectedDayEvents: [EventKitManager.CalendarEvent] = []
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
            await loadMonthEvents()
            if viewMode == .week {
                await loadWeekEvents()
            }
        }
        .onChange(of: currentMonth) { _, _ in
            Task {
                await loadMonthEvents()
            }
        }
        .onChange(of: viewMode) { _, newMode in
            if newMode == .week {
                Task { await loadWeekEvents() }
            }
        }
        .onChange(of: selectedDate) { _, _ in
            if viewMode == .week {
                Task { await loadWeekEvents() }
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
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            Text(monthYearString)
                .font(.headline)
                .frame(minWidth: 120)

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")

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
            .frame(width: 80)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                .onTapGesture {
                    selectedDate = date
                }
            }
        }
    }

    // MARK: - Helpers

    private var monthYearString: String {
        SharedDateFormatters.monthYear.string(from: currentMonth)
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

    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
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
