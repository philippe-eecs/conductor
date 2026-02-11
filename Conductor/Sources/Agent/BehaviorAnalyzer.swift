import Foundation

/// Analyzes behavioral data to generate productivity insights.
final class BehaviorAnalyzer {
    static let shared = BehaviorAnalyzer()

    private let database = Database.shared

    private init() {}

    /// Generate a compact insights summary for injection into morning briefs and system prompts.
    func generateInsights() -> BehaviorInsights {
        let store = BehaviorStore(database: database)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)

        // Peak productivity hours
        let completionsByHour = (try? store.getEventCountByHour(type: .taskCompleted, days: 30)) ?? [:]
        let peakHours = findPeakHours(completionsByHour)

        // Goal completion patterns
        let goalCompletions = (try? store.getTotalCount(type: .goalCompleted, since: thirtyDaysAgo)) ?? 0
        let goalRollovers = (try? store.getTotalCount(type: .goalRolled, since: thirtyDaysAgo)) ?? 0

        // Deferral patterns
        let deferrals = (try? store.getTotalCount(type: .taskDeferred, since: thirtyDaysAgo)) ?? 0

        // Action approval rate
        let approvals = (try? store.getTotalCount(type: .actionApproved, since: thirtyDaysAgo)) ?? 0
        let rejections = (try? store.getTotalCount(type: .actionRejected, since: thirtyDaysAgo)) ?? 0
        let approvalRate: Double
        if approvals + rejections > 0 {
            approvalRate = Double(approvals) / Double(approvals + rejections)
        } else {
            approvalRate = 1.0
        }

        // Day-of-week productivity
        let completionsByDay = (try? store.getEventCountByDayOfWeek(type: .taskCompleted, days: 30)) ?? [:]
        let mostProductiveDay = findMostProductiveDay(completionsByDay)

        return BehaviorInsights(
            peakHours: peakHours,
            goalCompletions30d: goalCompletions,
            goalRollovers30d: goalRollovers,
            deferrals30d: deferrals,
            actionApprovalRate: approvalRate,
            mostProductiveDay: mostProductiveDay
        )
    }

    /// Format insights as a compact summary string for AI context.
    func formatInsightsForPrompt() -> String? {
        let insights = generateInsights()

        // Only include if we have meaningful data
        guard insights.goalCompletions30d > 0 || insights.deferrals30d > 0 else {
            return nil
        }

        var lines: [String] = ["## Behavioral Insights (30 days):"]

        if !insights.peakHours.isEmpty {
            let hourStrings = insights.peakHours.map { formatHour($0) }
            lines.append("- Peak productivity: \(hourStrings.joined(separator: ", "))")
        }

        if insights.goalCompletions30d > 0 {
            lines.append("- Goals completed: \(insights.goalCompletions30d), rolled over: \(insights.goalRollovers30d)")
        }

        if insights.deferrals30d > 0 {
            lines.append("- Tasks deferred: \(insights.deferrals30d)")
        }

        if let day = insights.mostProductiveDay {
            lines.append("- Most productive day: \(day)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Analysis Helpers

    private func findPeakHours(_ hourCounts: [Int: Int]) -> [Int] {
        guard !hourCounts.isEmpty else { return [] }
        let sorted = hourCounts.sorted { $0.value > $1.value }
        let threshold = sorted.first.map { Double($0.value) * 0.7 } ?? 0
        return sorted.filter { Double($0.value) >= threshold }.map(\.key).sorted().prefix(3).map { $0 }
    }

    private func findMostProductiveDay(_ dayCounts: [Int: Int]) -> String? {
        guard let (day, _) = dayCounts.max(by: { $0.value < $1.value }) else { return nil }
        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard day > 0 && day < dayNames.count else { return nil }
        return dayNames[day]
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
}

// MARK: - Models

struct BehaviorInsights {
    let peakHours: [Int]
    let goalCompletions30d: Int
    let goalRollovers30d: Int
    let deferrals30d: Int
    let actionApprovalRate: Double
    let mostProductiveDay: String?
}
