import Foundation

/// Service that handles daily planning workflows including morning briefs,
/// evening shutdowns, goal management, and planning synthesis.
@MainActor
final class DailyPlanningService: ObservableObject {
    static let shared = DailyPlanningService()

    @Published var todaysBrief: DailyBrief?
    @Published var todaysGoals: [DailyGoal] = []
    @Published var isGeneratingBrief: Bool = false
    @Published var overdueGoals: [DailyGoal] = []

    private let database = Database.shared
    private let contextBuilder = ContextBuilder.shared

    private init() {
        Task {
            await loadTodaysData()
        }
    }

    // MARK: - Date Helpers

    nonisolated static var todayDateString: String {
        SharedDateFormatters.databaseDate.string(from: Date())
    }

    nonisolated static var tomorrowDateString: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return SharedDateFormatters.databaseDate.string(from: tomorrow)
    }

    nonisolated static func dateString(for date: Date) -> String {
        SharedDateFormatters.databaseDate.string(from: date)
    }

    // MARK: - Data Loading

    func loadTodaysData() async {
        let today = Self.todayDateString

        // Load today's brief
        if let brief = try? database.getDailyBrief(for: today, type: .morning) {
            todaysBrief = brief
        }

        // Load today's goals
        if let goals = try? database.getGoalsForDate(today) {
            todaysGoals = goals
        }

        // Load overdue goals from previous days
        if let overdue = try? database.getIncompleteGoals(before: today) {
            overdueGoals = overdue
        }
    }

    // MARK: - Brief Generation

    func generateMorningBrief() async throws -> DailyBrief {
        isGeneratingBrief = true
        defer { isGeneratingBrief = false }

        let today = Self.todayDateString
        let context = await buildPlanningContext()
        let prompt = buildMorningBriefPrompt(context: context)

        let planningModel = await Task.detached(priority: .utility) {
            (((try? Database.shared.getPreference(key: "claude_planning_model")) ?? nil) ?? "opus")
        }.value

        let response = try await ClaudeService.shared.sendMessage(
            prompt,
            history: [],
            toolsEnabled: false,
            modelOverride: planningModel
        )

        let brief = DailyBrief(
            date: today,
            briefType: .morning,
            content: response.result
        )

        try database.saveDailyBrief(brief)
        todaysBrief = brief

        return brief
    }

    func generateEveningBrief() async throws -> DailyBrief {
        isGeneratingBrief = true
        defer { isGeneratingBrief = false }

        let today = Self.todayDateString
        let context = await buildPlanningContext()
        let prompt = buildEveningBriefPrompt(context: context)

        let planningModel = await Task.detached(priority: .utility) {
            (((try? Database.shared.getPreference(key: "claude_planning_model")) ?? nil) ?? "opus")
        }.value

        let response = try await ClaudeService.shared.sendMessage(
            prompt,
            history: [],
            toolsEnabled: false,
            modelOverride: planningModel
        )

        let brief = DailyBrief(
            date: today,
            briefType: .evening,
            content: response.result
        )

        try database.saveDailyBrief(brief)

        return brief
    }

    func generateWeeklyReview() async throws -> DailyBrief {
        isGeneratingBrief = true
        defer { isGeneratingBrief = false }

        let today = Self.todayDateString
        let context = await buildWeeklyContext()
        let prompt = buildWeeklyReviewPrompt(context: context)

        let planningModel = await Task.detached(priority: .utility) {
            (((try? Database.shared.getPreference(key: "claude_planning_model")) ?? nil) ?? "opus")
        }.value

        let response = try await ClaudeService.shared.sendMessage(
            prompt,
            history: [],
            toolsEnabled: false,
            modelOverride: planningModel
        )

        let brief = DailyBrief(
            date: today,
            briefType: .weekly,
            content: response.result
        )

        try database.saveDailyBrief(brief)

        return brief
    }

    func generateMonthlyReview() async throws -> DailyBrief {
        isGeneratingBrief = true
        defer { isGeneratingBrief = false }

        let today = Self.todayDateString
        let context = await buildMonthlyContext()
        let prompt = buildMonthlyReviewPrompt(context: context)

        let planningModel = await Task.detached(priority: .utility) {
            (((try? Database.shared.getPreference(key: "claude_planning_model")) ?? nil) ?? "opus")
        }.value

        let response = try await ClaudeService.shared.sendMessage(
            prompt,
            history: [],
            toolsEnabled: false,
            modelOverride: planningModel
        )

        let brief = DailyBrief(
            date: today,
            briefType: .monthly,
            content: response.result
        )

        try database.saveDailyBrief(brief)

        return brief
    }

    // MARK: - Goal Management

    func addGoal(_ text: String, priority: Int? = nil) throws {
        let today = Self.todayDateString
        let goalPriority = priority ?? (todaysGoals.count + 1)

        let goal = DailyGoal(
            date: today,
            goalText: text,
            priority: goalPriority
        )

        try database.saveDailyGoal(goal)
        todaysGoals.append(goal)
        todaysGoals.sort { $0.priority < $1.priority }
    }

    func toggleGoalCompletion(_ goal: DailyGoal) throws {
        if goal.isCompleted {
            try database.markGoalIncomplete(id: goal.id)
        } else {
            try database.markGoalCompleted(id: goal.id)
        }

        // Reload goals
        if let goals = try? database.getGoalsForDate(Self.todayDateString) {
            todaysGoals = goals
        }
    }

    func updateGoal(_ goal: DailyGoal, text: String) throws {
        try database.updateGoalText(id: goal.id, text: text)

        if let index = todaysGoals.firstIndex(where: { $0.id == goal.id }) {
            todaysGoals[index].goalText = text
        }
    }

    func deleteGoal(_ goal: DailyGoal) throws {
        try database.deleteGoal(id: goal.id)
        todaysGoals.removeAll { $0.id == goal.id }
    }

    func reorderGoals(_ goals: [DailyGoal]) throws {
        for (index, goal) in goals.enumerated() {
            try database.updateGoalPriority(id: goal.id, priority: index + 1)
        }
        todaysGoals = goals.enumerated().map { index, goal in
            var updated = goal
            updated.priority = index + 1
            return updated
        }
    }

    // MARK: - Goal Rollover

    func rollGoalToTomorrow(_ goal: DailyGoal) throws {
        let tomorrow = Self.tomorrowDateString

        // Mark original as rolled
        try database.rollGoalToDate(id: goal.id, newDate: tomorrow)

        // Create new goal for tomorrow
        let newGoal = DailyGoal(
            date: tomorrow,
            goalText: goal.goalText,
            priority: goal.priority
        )
        try database.saveDailyGoal(newGoal)

        // Remove from overdue list
        overdueGoals.removeAll { $0.id == goal.id }

        // If it was today's goal, remove from today's list too
        todaysGoals.removeAll { $0.id == goal.id }
    }

    func rollAllIncompleteToTomorrow() throws {
        let tomorrow = Self.tomorrowDateString

        // Roll today's incomplete goals
        for goal in todaysGoals where !goal.isCompleted {
            try database.rollGoalToDate(id: goal.id, newDate: tomorrow)

            let newGoal = DailyGoal(
                date: tomorrow,
                goalText: goal.goalText,
                priority: goal.priority
            )
            try database.saveDailyGoal(newGoal)
        }

        // Roll overdue goals
        for goal in overdueGoals {
            try database.rollGoalToDate(id: goal.id, newDate: tomorrow)

            let newGoal = DailyGoal(
                date: tomorrow,
                goalText: goal.goalText,
                priority: goal.priority
            )
            try database.saveDailyGoal(newGoal)
        }

        // Reload
        if let goals = try? database.getGoalsForDate(Self.todayDateString) {
            todaysGoals = goals
        }
        overdueGoals = []
    }

    // MARK: - Brief Actions

    func markBriefAsRead(_ brief: DailyBrief) throws {
        try database.markBriefAsRead(id: brief.id)
        if todaysBrief?.id == brief.id {
            todaysBrief?.readAt = Date()
        }
    }

    func dismissBrief(_ brief: DailyBrief) throws {
        try database.markBriefAsDismissed(id: brief.id)
        if todaysBrief?.id == brief.id {
            todaysBrief?.dismissed = true
        }
    }

    // MARK: - Statistics

    func getCompletionRate(forDays days: Int = 7) -> Double {
        (try? database.getGoalCompletionRate(forDays: days)) ?? 0
    }

    func getTodaysProgress() -> (completed: Int, total: Int) {
        let completed = todaysGoals.filter { $0.isCompleted }.count
        return (completed, todaysGoals.count)
    }

    // MARK: - Private Methods

    private func buildPlanningContext() async -> PlanningContext {
        let calendarContext = await contextBuilder.buildContext()
        let completionRate = getCompletionRate()
        let overdueCount = overdueGoals.count

        return PlanningContext(
            todayEvents: calendarContext.todayEvents,
            upcomingReminders: calendarContext.upcomingReminders,
            todaysGoals: todaysGoals,
            overdueGoals: overdueGoals,
            completionRate: completionRate,
            overdueCount: overdueCount
        )
    }

    private func buildMorningBriefPrompt(context: PlanningContext) -> String {
        var prompt = """
        You are Conductor, a daily planning assistant. Generate a concise morning briefing.

        Current date: \(formattedDate(Date()))

        """

        // Calendar events
        if !context.todayEvents.isEmpty {
            prompt += "\n## Today's Calendar:\n"
            for event in context.todayEvents {
                prompt += "- \(event.time): \(event.title)"
                if let location = event.location {
                    prompt += " (\(location))"
                }
                prompt += " [\(event.duration)]\n"
            }
        } else {
            prompt += "\n## Today's Calendar:\nNo events scheduled.\n"
        }

        // Reminders
        if !context.upcomingReminders.isEmpty {
            prompt += "\n## Pending Reminders:\n"
            for reminder in context.upcomingReminders {
                prompt += "- \(reminder.title)"
                if let dueDate = reminder.dueDate {
                    prompt += " (due: \(dueDate))"
                }
                prompt += "\n"
            }
        }

        // Existing goals
        if !context.todaysGoals.isEmpty {
            prompt += "\n## Today's Goals (already set):\n"
            for goal in context.todaysGoals {
                let status = goal.isCompleted ? "[x]" : "[ ]"
                prompt += "- \(status) \(goal.goalText)\n"
            }
        }

        // Overdue items
        if context.overdueCount > 0 {
            prompt += "\n## Overdue Items:\n"
            for goal in context.overdueGoals.prefix(5) {
                prompt += "- \(goal.goalText) (from \(goal.date))\n"
            }
            if context.overdueCount > 5 {
                prompt += "... and \(context.overdueCount - 5) more\n"
            }
        }

        // Completion rate
        prompt += "\n## Last 7 Days:\nGoal completion rate: \(Int(context.completionRate * 100))%\n"

        // Active themes with task counts
        if let themes = try? database.getThemes(), !themes.isEmpty {
            prompt += "\n## Active Themes:\n"
            for theme in themes {
                let count = (try? database.getTaskCountForTheme(id: theme.id)) ?? 0
                prompt += "- \(theme.name)"
                if count > 0 { prompt += " (\(count) tasks)" }
                if let desc = theme.themeDescription { prompt += " — \(desc)" }
                prompt += "\n"
            }
        }

        // Email triage summary
        if let emails = try? database.getProcessedEmails(filter: .actionNeeded, limit: 5), !emails.isEmpty {
            prompt += "\n## Email Triage:\n"
            prompt += "Action-needed emails: \(emails.count)\n"
            for email in emails.prefix(3) {
                prompt += "- [\(email.severity.rawValue)] \(email.sender): \(email.subject)"
                if let summary = email.aiSummary { prompt += " — \(summary)" }
                prompt += "\n"
            }
        }

        // Behavioral insights
        if let insights = BehaviorAnalyzer.shared.formatInsightsForPrompt() {
            prompt += "\n\(insights)\n"
        }

        // Active agent tasks
        if let agentTasks = try? database.getActiveAgentTasks(), !agentTasks.isEmpty {
            prompt += "\n## Active Agent Tasks: \(agentTasks.count)\n"
            for task in agentTasks.prefix(5) {
                prompt += "- \(task.name) (\(task.triggerType.rawValue))"
                if let nextRun = task.nextRun {
                    prompt += " next: \(SharedDateFormatters.time24HourWithSeconds.string(from: nextRun))"
                }
                prompt += "\n"
            }
        }

        prompt += """

        Generate a morning briefing with:
        1. A brief greeting appropriate for the time of day
        2. Summary of today's schedule (highlight any conflicts or busy periods)
        3. If no goals are set, suggest 3 top priorities based on calendar and reminders
        4. Any important reminders or overdue items to address
        5. One actionable tip for the day

        Keep it concise (under 200 words). Use bullet points. Be encouraging but not overly enthusiastic.
        """

        return prompt
    }

    private func buildEveningBriefPrompt(context: PlanningContext) -> String {
        let progress = getTodaysProgress()

        var prompt = """
        You are Conductor, a daily planning assistant. Generate a concise evening shutdown summary.

        Current date: \(formattedDate(Date()))

        """

        // Today's goals progress
        prompt += "\n## Today's Goals:\n"
        if context.todaysGoals.isEmpty {
            prompt += "No goals were set for today.\n"
        } else {
            for goal in context.todaysGoals {
                let status = goal.isCompleted ? "[x]" : "[ ]"
                prompt += "- \(status) \(goal.goalText)\n"
            }
            prompt += "\nCompleted: \(progress.completed)/\(progress.total)\n"
        }

        // Incomplete items
        let incomplete = context.todaysGoals.filter { !$0.isCompleted }
        if !incomplete.isEmpty {
            prompt += "\n## Incomplete Items (consider rolling to tomorrow):\n"
            for goal in incomplete {
                prompt += "- \(goal.goalText)\n"
            }
        }

        // Tomorrow's calendar preview (if available from context)
        prompt += "\n## Completion Rate (7-day): \(Int(context.completionRate * 100))%\n"

        prompt += """

        Generate an evening shutdown summary with:
        1. Brief acknowledgment of today's progress
        2. If there are incomplete items, suggest rolling them to tomorrow or reconsidering
        3. Ask for tomorrow's top 3 priorities (frame as a question)
        4. One reflection prompt (e.g., "What went well today?")

        Keep it concise (under 150 words). Be supportive and forward-looking.
        """

        return prompt
    }

    private func formattedDate(_ date: Date) -> String {
        SharedDateFormatters.fullDate.string(from: date)
    }

    // MARK: - Weekly Context

    private func buildWeeklyContext() async -> WeeklyContext {
        let calendar = Calendar.current
        let today = Date()

        // Get last week's date range
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: today)!
        let lastWeekEnd = calendar.date(byAdding: .day, value: -1, to: today)!

        // Get this week's upcoming events
        let upcomingEvents = await EventKitManager.shared.getUpcomingEvents(days: 7)

        // Calculate last week's stats
        let startDateString = SharedDateFormatters.databaseDate.string(from: lastWeekStart)
        let endDateString = SharedDateFormatters.databaseDate.string(from: lastWeekEnd)

        let weeklyStats = calculateWeeklyStats(from: startDateString, to: endDateString)

        // Get rolled items (incomplete goals from before today)
        let rolledItems = (try? database.getIncompleteGoals(before: Self.todayDateString)) ?? []

        return WeeklyContext(
            weekEvents: upcomingEvents.map { event in
                WeeklyContext.EventSummary(
                    day: formatDayOfWeek(event.startDate),
                    time: event.time,
                    title: event.title,
                    duration: event.duration
                )
            },
            lastWeekGoalsCompleted: weeklyStats.completed,
            lastWeekGoalsTotal: weeklyStats.total,
            rolledItems: rolledItems,
            completionRate: getCompletionRate(forDays: 7)
        )
    }

    private func calculateWeeklyStats(from startDate: String, to endDate: String) -> (completed: Int, total: Int) {
        var completed = 0
        var total = 0

        // Get goals for each day in the range
        if let start = SharedDateFormatters.databaseDate.date(from: startDate),
           let end = SharedDateFormatters.databaseDate.date(from: endDate) {
            var current = start
            while current <= end {
                let dateString = SharedDateFormatters.databaseDate.string(from: current)
                if let goals = try? database.getGoalsForDate(dateString) {
                    total += goals.count
                    completed += goals.filter { $0.isCompleted }.count
                }
                current = Calendar.current.date(byAdding: .day, value: 1, to: current)!
            }
        }

        return (completed, total)
    }

    private func formatDayOfWeek(_ date: Date) -> String {
        SharedDateFormatters.dayOfWeek.string(from: date)
    }

    private func buildWeeklyReviewPrompt(context: WeeklyContext) -> String {
        var prompt = """
        You are Conductor, a weekly planning assistant. Generate a concise weekly review.

        Current week starting: \(formattedDate(Date()))

        """

        // Last week's performance
        prompt += "\n## Last Week's Performance:\n"
        if context.lastWeekGoalsTotal > 0 {
            let rate = Double(context.lastWeekGoalsCompleted) / Double(context.lastWeekGoalsTotal) * 100
            prompt += "- Goals completed: \(context.lastWeekGoalsCompleted)/\(context.lastWeekGoalsTotal) (\(Int(rate))%)\n"
        } else {
            prompt += "- No goals were tracked last week\n"
        }

        // This week's calendar
        if !context.weekEvents.isEmpty {
            prompt += "\n## This Week's Calendar:\n"
            var currentDay = ""
            for event in context.weekEvents {
                if event.day != currentDay {
                    currentDay = event.day
                    prompt += "\n### \(event.day)\n"
                }
                prompt += "- \(event.time): \(event.title) [\(event.duration)]\n"
            }
        } else {
            prompt += "\n## This Week's Calendar:\nNo events scheduled.\n"
        }

        // Rolled items
        if !context.rolledItems.isEmpty {
            prompt += "\n## Carried Over from Previous Weeks:\n"
            for item in context.rolledItems.prefix(5) {
                prompt += "- \(item.goalText) (from \(item.date))\n"
            }
            if context.rolledItems.count > 5 {
                prompt += "... and \(context.rolledItems.count - 5) more\n"
            }
        }

        prompt += """

        Generate a weekly review with:
        1. Brief reflection on last week's progress
        2. Key themes or focus areas for this week based on calendar
        3. Identify any potential conflicts or particularly busy days
        4. Suggest 2-3 weekly goals or themes
        5. If there are carried-over items, suggest addressing or dropping them

        Keep it concise (under 250 words). Use bullet points. Be practical and forward-looking.
        """

        return prompt
    }

    // MARK: - Monthly Context

    private func buildMonthlyContext() async -> MonthlyContext {
        let calendar = Calendar.current
        let today = Date()

        // Get last 30 days stats
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!
        let startDateString = SharedDateFormatters.databaseDate.string(from: thirtyDaysAgo)
        let endDateString = SharedDateFormatters.databaseDate.string(from: today)

        // Calculate monthly stats
        let monthlyStats = calculateMonthlyStats(from: startDateString, to: endDateString)

        // Get productivity stats if available
        let recentStats = (try? database.getRecentProductivityStats(days: 30)) ?? []

        // Calculate meeting vs focus time
        let meetingHours = recentStats.reduce(0.0) { $0 + $1.meetingsHours }
        let focusHours = recentStats.reduce(0.0) { $0 + $1.focusHours }

        // Find patterns in rolled tasks
        let frequentlyRolledPatterns = analyzeRolledTaskPatterns()

        return MonthlyContext(
            goalsCompleted: monthlyStats.completed,
            goalsTotal: monthlyStats.total,
            meetingHours: meetingHours,
            focusHours: focusHours,
            averageOverdueCount: recentStats.isEmpty ? 0 : Double(recentStats.reduce(0) { $0 + $1.overdueCount }) / Double(recentStats.count),
            frequentlyRolledPatterns: frequentlyRolledPatterns,
            completionTrend: calculateCompletionTrend()
        )
    }

    private func calculateMonthlyStats(from startDate: String, to endDate: String) -> (completed: Int, total: Int) {
        var completed = 0
        var total = 0

        if let start = SharedDateFormatters.databaseDate.date(from: startDate),
           let end = SharedDateFormatters.databaseDate.date(from: endDate) {
            var current = start
            while current <= end {
                let dateString = SharedDateFormatters.databaseDate.string(from: current)
                if let goals = try? database.getGoalsForDate(dateString) {
                    total += goals.count
                    completed += goals.filter { $0.isCompleted }.count
                }
                current = Calendar.current.date(byAdding: .day, value: 1, to: current)!
            }
        }

        return (completed, total)
    }

    private func analyzeRolledTaskPatterns() -> [String] {
        // Find tasks that have been rolled multiple times
        // For now, just return the text of overdue items
        return overdueGoals.prefix(3).map { $0.goalText }
    }

    private func calculateCompletionTrend() -> String {
        let lastWeekRate = getCompletionRate(forDays: 7)
        let previousWeekRate = getCompletionRate(forDays: 14) - lastWeekRate // Approximate

        if lastWeekRate > previousWeekRate + 0.1 {
            return "improving"
        } else if lastWeekRate < previousWeekRate - 0.1 {
            return "declining"
        } else {
            return "stable"
        }
    }

    private func buildMonthlyReviewPrompt(context: MonthlyContext) -> String {
        var prompt = """
        You are Conductor, a monthly planning assistant. Generate a comprehensive monthly review.

        Review period: Last 30 days ending \(formattedDate(Date()))

        """

        // Goal completion
        prompt += "\n## Goal Completion:\n"
        if context.goalsTotal > 0 {
            let rate = Double(context.goalsCompleted) / Double(context.goalsTotal) * 100
            prompt += "- Goals completed: \(context.goalsCompleted)/\(context.goalsTotal) (\(Int(rate))%)\n"
            prompt += "- Trend: \(context.completionTrend)\n"
        } else {
            prompt += "- No goals were tracked this month\n"
        }

        // Time allocation
        prompt += "\n## Time Allocation:\n"
        prompt += "- Meeting hours: \(String(format: "%.1f", context.meetingHours))\n"
        prompt += "- Focus hours: \(String(format: "%.1f", context.focusHours))\n"

        // Overdue analysis
        if context.averageOverdueCount > 0 {
            prompt += "\n## Task Backlog:\n"
            prompt += "- Average overdue items: \(String(format: "%.1f", context.averageOverdueCount))\n"
        }

        // Patterns
        if !context.frequentlyRolledPatterns.isEmpty {
            prompt += "\n## Recurring Incomplete Items:\n"
            for pattern in context.frequentlyRolledPatterns {
                prompt += "- \(pattern)\n"
            }
        }

        prompt += """

        Generate a monthly review with:
        1. Overall productivity assessment (what went well, what needs attention)
        2. Analysis of goal completion patterns
        3. Time management insights (meeting vs focus time balance)
        4. If there are recurring incomplete items, suggest why and how to address
        5. 2-3 specific recommendations for the coming month
        6. One key metric to focus on improving

        Keep it concise but insightful (under 350 words). Be honest and constructive.
        """

        return prompt
    }
}

// MARK: - Planning Context

struct PlanningContext {
    let todayEvents: [ContextData.EventSummary]
    let upcomingReminders: [ContextData.ReminderSummary]
    let todaysGoals: [DailyGoal]
    let overdueGoals: [DailyGoal]
    let completionRate: Double
    let overdueCount: Int
}

struct WeeklyContext {
    struct EventSummary {
        let day: String
        let time: String
        let title: String
        let duration: String
    }

    let weekEvents: [EventSummary]
    let lastWeekGoalsCompleted: Int
    let lastWeekGoalsTotal: Int
    let rolledItems: [DailyGoal]
    let completionRate: Double
}

struct MonthlyContext {
    let goalsCompleted: Int
    let goalsTotal: Int
    let meetingHours: Double
    let focusHours: Double
    let averageOverdueCount: Double
    let frequentlyRolledPatterns: [String]
    let completionTrend: String
}
