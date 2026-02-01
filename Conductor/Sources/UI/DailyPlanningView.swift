import SwiftUI

struct DailyPlanningView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planningService = DailyPlanningService.shared
    @State private var newGoalText: String = ""
    @State private var showingAddGoal: Bool = false
    @State private var editingGoal: DailyGoal?
    @State private var editingGoalText: String = ""
    @State private var showingEveningBrief: Bool = false
    @State private var showingWeeklyReview: Bool = false
    @State private var showingMonthlyReview: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    todaysFocusSection
                    scheduleSection
                    overdueSection
                    briefSection
                    reviewsSection
                }
                .padding()
            }
            Divider()
            footerView
        }
        .frame(width: 400, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingEveningBrief) {
            EveningBriefView()
        }
        .sheet(isPresented: $showingWeeklyReview) {
            WeeklyReviewView()
        }
        .sheet(isPresented: $showingMonthlyReview) {
            MonthlyReviewView()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate)
                    .font(.headline)
                Text(greeting)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Today's Focus Section

    private var todaysFocusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Today's Focus", systemImage: "target")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                if !showingAddGoal {
                    Button(action: { showingAddGoal = true }) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add Goal")
                }
            }

            if planningService.todaysGoals.isEmpty && !showingAddGoal {
                emptyGoalsView
            } else {
                VStack(spacing: 6) {
                    ForEach(planningService.todaysGoals) { goal in
                        GoalRowView(
                            goal: goal,
                            onToggle: { toggleGoal(goal) },
                            onEdit: { startEditing(goal) },
                            onDelete: { deleteGoal(goal) }
                        )
                    }

                    if showingAddGoal {
                        addGoalView
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var emptyGoalsView: some View {
        VStack(spacing: 8) {
            Text("No goals set for today")
                .font(.callout)
                .foregroundColor(.secondary)

            Button("Add your top 3 priorities") {
                showingAddGoal = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var addGoalView: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .foregroundColor(.secondary)
                .font(.body)

            TextField("What's your goal?", text: $newGoalText)
                .textFieldStyle(.plain)
                .onSubmit { addGoal() }

            Button(action: addGoal) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(newGoalText.isEmpty ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(newGoalText.isEmpty)

            Button(action: { showingAddGoal = false; newGoalText = "" }) {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Schedule", systemImage: "calendar")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            SchedulePreviewView()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Overdue Section

    @ViewBuilder
    private var overdueSection: some View {
        if !planningService.overdueGoals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("\(planningService.overdueGoals.count) overdue", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)

                    Spacer()

                    Button("Roll All") {
                        rollAllOverdue()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ForEach(planningService.overdueGoals.prefix(3)) { goal in
                    OverdueGoalRow(goal: goal) {
                        rollGoal(goal)
                    }
                }

                if planningService.overdueGoals.count > 3 {
                    Text("+ \(planningService.overdueGoals.count - 3) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Reviews Section

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Reviews", systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button(action: { showingWeeklyReview = true }) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                        Text("Weekly")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { showingMonthlyReview = true }) {
                    HStack {
                        Image(systemName: "calendar")
                        Text("Monthly")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Brief Section

    @ViewBuilder
    private var briefSection: some View {
        if let brief = planningService.todaysBrief, !brief.dismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Morning Brief", systemImage: "sun.max")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: { dismissBrief(brief) }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text(brief.content)
                    .font(.callout)
                    .foregroundColor(.primary)
                    .lineLimit(6)

                if brief.readAt == nil {
                    Button("Mark as Read") {
                        markBriefAsRead(brief)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .onAppear {
                if brief.readAt == nil {
                    markBriefAsRead(brief)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            let progress = planningService.getTodaysProgress()
            if progress.total > 0 {
                Text("\(progress.completed)/\(progress.total) completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if planningService.isGeneratingBrief {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button("Regenerate Brief") {
                    generateBrief()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Evening Shutdown") {
                    showingEveningBrief = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    // MARK: - Computed Properties

    private var formattedDate: String {
        SharedDateFormatters.fullDateNoYear.string(from: Date())
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<21:
            return "Good evening"
        default:
            return "Good night"
        }
    }

    // MARK: - Actions

    private func addGoal() {
        let text = newGoalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        do {
            try planningService.addGoal(text)
            newGoalText = ""
            if planningService.todaysGoals.count >= 3 {
                showingAddGoal = false
            }
        } catch {
            print("Failed to add goal: \(error)")
        }
    }

    private func toggleGoal(_ goal: DailyGoal) {
        do {
            try planningService.toggleGoalCompletion(goal)
        } catch {
            print("Failed to toggle goal: \(error)")
        }
    }

    private func startEditing(_ goal: DailyGoal) {
        editingGoal = goal
        editingGoalText = goal.goalText
    }

    private func deleteGoal(_ goal: DailyGoal) {
        do {
            try planningService.deleteGoal(goal)
        } catch {
            print("Failed to delete goal: \(error)")
        }
    }

    private func rollGoal(_ goal: DailyGoal) {
        do {
            try planningService.rollGoalToTomorrow(goal)
        } catch {
            print("Failed to roll goal: \(error)")
        }
    }

    private func rollAllOverdue() {
        do {
            try planningService.rollAllIncompleteToTomorrow()
        } catch {
            print("Failed to roll goals: \(error)")
        }
    }

    private func generateBrief() {
        Task {
            do {
                _ = try await planningService.generateMorningBrief()
            } catch {
                print("Failed to generate brief: \(error)")
            }
        }
    }

    private func markBriefAsRead(_ brief: DailyBrief) {
        do {
            try planningService.markBriefAsRead(brief)
        } catch {
            print("Failed to mark brief as read: \(error)")
        }
    }

    private func dismissBrief(_ brief: DailyBrief) {
        do {
            try planningService.dismissBrief(brief)
        } catch {
            print("Failed to dismiss brief: \(error)")
        }
    }
}

// MARK: - Goal Row View

struct GoalRowView: View {
    let goal: DailyGoal
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(goal.isCompleted ? .green : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)

            Text(goal.goalText)
                .font(.callout)
                .strikethrough(goal.isCompleted)
                .foregroundColor(goal.isCompleted ? .secondary : .primary)
                .lineLimit(2)

            Spacer()

            if isHovering {
                HStack(spacing: 4) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }

            if goal.priority <= 3 {
                Text("#\(goal.priority)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Overdue Goal Row

struct OverdueGoalRow: View {
    let goal: DailyGoal
    let onRoll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(.orange)
                .font(.caption)

            Text(goal.goalText)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            Text(goal.date)
                .font(.caption2)
                .foregroundColor(.secondary)

            Button("Roll") {
                onRoll()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(6)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(4)
    }
}

// MARK: - Schedule Preview View

struct SchedulePreviewView: View {
    @State private var events: [ContextData.EventSummary] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if events.isEmpty {
                Text("No events scheduled")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(events.prefix(5), id: \.title) { event in
                    HStack(spacing: 8) {
                        Text(event.time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)

                        Text(event.title)
                            .font(.callout)
                            .lineLimit(1)

                        Spacer()

                        Text(event.duration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if events.count > 5 {
                    Text("+ \(events.count - 5) more events")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            let context = await ContextBuilder.shared.buildContext()
            events = context.todayEvents
        }
    }
}

// MARK: - Evening Brief View

struct EveningBriefView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planningService = DailyPlanningService.shared
    @State private var eveningBrief: DailyBrief?
    @State private var isLoading = false
    @State private var tomorrowGoals: [String] = ["", "", ""]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Evening Shutdown")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Today's Summary
                    todaySummarySection

                    // Evening Brief
                    if let brief = eveningBrief {
                        briefContentSection(brief)
                    } else if isLoading {
                        ProgressView("Generating evening summary...")
                            .padding()
                    }

                    // Tomorrow's Goals
                    tomorrowGoalsSection

                    // Rollover Section
                    rolloverSection
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Roll Incomplete & Close") {
                    rollAndClose()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .task {
            await generateEveningBrief()
        }
    }

    private var todaySummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today's Progress", systemImage: "chart.bar")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            let progress = planningService.getTodaysProgress()
            let completionRate = progress.total > 0 ? Double(progress.completed) / Double(progress.total) : 0

            HStack {
                Text("\(progress.completed)/\(progress.total) goals completed")
                    .font(.callout)

                Spacer()

                Text("\(Int(completionRate * 100))%")
                    .font(.headline)
                    .foregroundColor(completionRate >= 0.7 ? .green : (completionRate >= 0.4 ? .orange : .red))
            }

            ProgressView(value: completionRate)
                .tint(completionRate >= 0.7 ? .green : (completionRate >= 0.4 ? .orange : .red))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func briefContentSection(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Summary", systemImage: "text.alignleft")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(brief.content)
                .font(.callout)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var tomorrowGoalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tomorrow's Top 3", systemImage: "sun.max")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    TextField("Goal \(index + 1)", text: $tomorrowGoals[index])
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var rolloverSection: some View {
        let incomplete = planningService.todaysGoals.filter { !$0.isCompleted }
        if !incomplete.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Incomplete Items", systemImage: "arrow.uturn.forward")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)

                ForEach(incomplete) { goal in
                    HStack {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(goal.goalText)
                            .font(.callout)
                            .lineLimit(1)
                    }
                }

                Text("These will be rolled to tomorrow when you close.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private func generateEveningBrief() async {
        isLoading = true
        defer { isLoading = false }

        do {
            eveningBrief = try await planningService.generateEveningBrief()
        } catch {
            print("Failed to generate evening brief: \(error)")
        }
    }

    private func rollAndClose() {
        // Save tomorrow's goals
        let tomorrow = DailyPlanningService.tomorrowDateString
        for (index, goalText) in tomorrowGoals.enumerated() {
            let text = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let goal = DailyGoal(
                date: tomorrow,
                goalText: text,
                priority: index + 1
            )
            try? Database.shared.saveDailyGoal(goal)
        }

        // Roll incomplete
        try? planningService.rollAllIncompleteToTomorrow()

        dismiss()
    }
}

// MARK: - Weekly Review View

struct WeeklyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planningService = DailyPlanningService.shared
    @State private var weeklyBrief: DailyBrief?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Review")
                        .font(.headline)
                    Text(weekRange)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Stats summary
                    statsSection

                    // Review content
                    if let brief = weeklyBrief {
                        reviewContentSection(brief)
                    } else if isLoading {
                        loadingSection
                    } else if let error = errorMessage {
                        errorSection(error)
                    } else {
                        emptySection
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Generate Review") {
                        generateReview()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 420, height: 500)
        .task {
            await loadExistingReview()
        }
    }

    private var weekRange: String {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let startStr = SharedDateFormatters.shortMonthDay.string(from: weekStart)
        let endStr = SharedDateFormatters.shortMonthDay.string(from: today)
        return "\(startStr) - \(endStr)"
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This Week", systemImage: "chart.bar")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                statCard("Completion", value: "\(Int(planningService.getCompletionRate(forDays: 7) * 100))%")
                statCard("Goals", value: "\(planningService.todaysGoals.count)")
                statCard("Overdue", value: "\(planningService.overdueGoals.count)")
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func statCard(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func reviewContentSection(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Review", systemImage: "doc.text")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(brief.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(brief.content)
                .font(.callout)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Generating weekly review...")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.orange)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var emptySection: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No weekly review yet")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Generate a review to see your week's progress and insights.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func loadExistingReview() async {
        let today = DailyPlanningService.todayDateString
        if let brief = try? Database.shared.getDailyBrief(for: today, type: .weekly) {
            weeklyBrief = brief
        }
    }

    private func generateReview() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                weeklyBrief = try await planningService.generateWeeklyReview()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Monthly Review View

struct MonthlyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planningService = DailyPlanningService.shared
    @State private var monthlyBrief: DailyBrief?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Review")
                        .font(.headline)
                    Text(currentMonth)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Monthly stats
                    monthlyStatsSection

                    // Review content
                    if let brief = monthlyBrief {
                        reviewContentSection(brief)
                    } else if isLoading {
                        loadingSection
                    } else if let error = errorMessage {
                        errorSection(error)
                    } else {
                        emptySection
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Generate Review") {
                        generateReview()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 420, height: 520)
        .task {
            await loadExistingReview()
        }
    }

    private var currentMonth: String {
        SharedDateFormatters.monthYear.string(from: Date())
    }

    private var monthlyStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Last 30 Days", systemImage: "calendar")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            // Completion trend
            let weekRate = planningService.getCompletionRate(forDays: 7)
            let monthRate = planningService.getCompletionRate(forDays: 30)

            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(Int(monthRate * 100))%")
                            .font(.title2)
                            .fontWeight(.semibold)
                        trendIndicator(weekRate: weekRate, monthRate: monthRate)
                    }
                    Text("Completion")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("\(planningService.overdueGoals.count)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(planningService.overdueGoals.count > 5 ? .orange : .primary)
                    Text("Overdue")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Monthly Progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(monthRate * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ProgressView(value: monthRate)
                    .tint(progressColor(monthRate))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func trendIndicator(weekRate: Double, monthRate: Double) -> some View {
        let diff = weekRate - monthRate
        if abs(diff) < 0.05 {
            return AnyView(
                Image(systemName: "minus")
                    .font(.caption)
                    .foregroundColor(.secondary)
            )
        } else if diff > 0 {
            return AnyView(
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.green)
            )
        } else {
            return AnyView(
                Image(systemName: "arrow.down.right")
                    .font(.caption)
                    .foregroundColor(.red)
            )
        }
    }

    private func progressColor(_ rate: Double) -> Color {
        if rate >= 0.7 { return .green }
        if rate >= 0.4 { return .orange }
        return .red
    }

    private func reviewContentSection(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Monthly Insights", systemImage: "lightbulb")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(brief.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(brief.content)
                .font(.callout)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Generating monthly review...")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.orange)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var emptySection: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No monthly review yet")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Generate a review to see your month's progress, patterns, and recommendations.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func loadExistingReview() async {
        let today = DailyPlanningService.todayDateString
        if let brief = try? Database.shared.getDailyBrief(for: today, type: .monthly) {
            monthlyBrief = brief
        }
    }

    private func generateReview() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                monthlyBrief = try await planningService.generateMonthlyReview()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    DailyPlanningView()
}
