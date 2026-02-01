import Foundation

/// Manages notification fatigue by rate limiting and learning preferences
final class FatigueManager {
    static let shared = FatigueManager()

    private var recentAlerts: [ShownAlert] = []
    private var categoryDismissals: [ProactiveAlert.Category: Int] = [:]
    private var categoryClicks: [ProactiveAlert.Category: Int] = [:]

    private let maxPerHour = 3
    private let maxPerDay = 12
    private let minGapSeconds: TimeInterval = 15 * 60 // 15 minutes

    private init() {}

    struct ShownAlert {
        let id: String
        let category: ProactiveAlert.Category
        let timestamp: Date
    }

    /// Determine if an alert should be shown based on fatigue rules
    func shouldShow(alert: ProactiveAlert) -> Bool {
        let now = Date()

        // Check quiet hours
        if LocalRuleEngine.shared.isQuietHours() {
            // Only allow high priority during quiet hours
            if alert.priority != .high {
                return false
            }
        }

        // Check hourly limit
        let oneHourAgo = now.addingTimeInterval(-3600)
        let alertsInLastHour = recentAlerts.filter { $0.timestamp > oneHourAgo }
        if alertsInLastHour.count >= maxPerHour {
            return false
        }

        // Check daily limit
        let startOfDay = Calendar.current.startOfDay(for: now)
        let alertsToday = recentAlerts.filter { $0.timestamp >= startOfDay }
        if alertsToday.count >= maxPerDay {
            return false
        }

        // Check minimum gap for same category
        let recentSameCategory = recentAlerts
            .filter { $0.category == alert.category }
            .sorted { $0.timestamp > $1.timestamp }
            .first

        if let recent = recentSameCategory {
            if now.timeIntervalSince(recent.timestamp) < minGapSeconds {
                return false
            }
        }

        // Check if user tends to dismiss this category
        let dismissRate = categoryDismissRate(alert.category)
        if dismissRate > 0.8 && alert.priority == .low {
            // User dismisses 80%+ of this category, skip low priority
            return false
        }

        return true
    }

    /// Record that an alert was shown
    func recordShown(alert: ProactiveAlert) {
        let shown = ShownAlert(
            id: alert.id,
            category: alert.category,
            timestamp: Date()
        )
        recentAlerts.append(shown)

        // Clean up old alerts (keep last 24 hours)
        let oneDayAgo = Date().addingTimeInterval(-86400)
        recentAlerts.removeAll { $0.timestamp < oneDayAgo }
    }

    /// Record user dismissal of a notification
    func recordDismissal(category: ProactiveAlert.Category) {
        categoryDismissals[category, default: 0] += 1
    }

    /// Record user click on a notification
    func recordClick(category: ProactiveAlert.Category) {
        categoryClicks[category, default: 0] += 1
    }

    /// Calculate dismiss rate for a category
    private func categoryDismissRate(_ category: ProactiveAlert.Category) -> Double {
        let dismissals = categoryDismissals[category] ?? 0
        let clicks = categoryClicks[category] ?? 0
        let total = dismissals + clicks

        guard total > 5 else {
            // Not enough data
            return 0
        }

        return Double(dismissals) / Double(total)
    }

    /// Reset all fatigue tracking
    func reset() {
        recentAlerts = []
        categoryDismissals = [:]
        categoryClicks = [:]
    }

    /// Get current stats for debugging
    func getStats() -> (alertsToday: Int, alertsLastHour: Int) {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let oneHourAgo = now.addingTimeInterval(-3600)

        let alertsToday = recentAlerts.filter { $0.timestamp >= startOfDay }.count
        let alertsLastHour = recentAlerts.filter { $0.timestamp > oneHourAgo }.count

        return (alertsToday, alertsLastHour)
    }
}
