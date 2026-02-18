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
            Log.planning.error("Failed to add goal: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func toggleGoal(_ goal: DailyGoal) {
        do {
            try planningService.toggleGoalCompletion(goal)
        } catch {
            Log.planning.error("Failed to toggle goal: \(error.localizedDescription, privacy: .public)")
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
            Log.planning.error("Failed to delete goal: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rollGoal(_ goal: DailyGoal) {
        do {
            try planningService.rollGoalToTomorrow(goal)
        } catch {
            Log.planning.error("Failed to roll goal: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rollAllOverdue() {
        do {
            try planningService.rollAllIncompleteToTomorrow()
        } catch {
            Log.planning.error("Failed to roll goals: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func generateBrief() {
        Task {
            do {
                _ = try await planningService.generateMorningBrief()
            } catch {
                Log.planning.error("Failed to generate brief: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func markBriefAsRead(_ brief: DailyBrief) {
        do {
            try planningService.markBriefAsRead(brief)
        } catch {
            Log.planning.error("Failed to mark brief as read: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func dismissBrief(_ brief: DailyBrief) {
        do {
            try planningService.dismissBrief(brief)
        } catch {
            Log.planning.error("Failed to dismiss brief: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#Preview {
    DailyPlanningView()
}
