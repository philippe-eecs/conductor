import Foundation
import UserNotifications

/// Tracks and reports on Claude CLI usage costs
final class CostTracker: ObservableObject {
    static let shared = CostTracker()

    @Published var dailyCost: Double = 0
    @Published var weeklyCost: Double = 0
    @Published var monthlyCost: Double = 0
    @Published var dailyBudget: Double? = nil
    @Published var monthlyBudget: Double? = nil

    private var hasRequestedNotificationPermission = false

    private init() {
        refresh()
        loadBudgetSettings()
        requestNotificationPermission()
    }

    // MARK: - Public Methods

    /// Refresh cost data from database
    func refresh() {
        do {
            dailyCost = try Database.shared.getDailyCost()
            weeklyCost = try Database.shared.getWeeklyCost()
            monthlyCost = try Database.shared.getMonthlyCost()
        } catch {
            Log.cost.error("Failed to refresh cost data: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Log a cost entry
    func logCost(amount: Double, sessionId: String?) {
        do {
            try Database.shared.logCost(amount: amount, sessionId: sessionId)
            refresh()
            checkBudgetAlerts()
        } catch {
            Log.cost.error("Failed to log cost: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Get cost history for charting
    func getCostHistory(days: Int = 30) -> [(date: Date, amount: Double)] {
        do {
            return try Database.shared.getCostHistory(days: days)
        } catch {
            Log.cost.error("Failed to get cost history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Get daily cost breakdown for the past week
    func getDailyBreakdown() -> [(date: Date, total: Double)] {
        let history = getCostHistory(days: 7)
        let calendar = Calendar.current

        // Group by day
        var dailyTotals: [Date: Double] = [:]

        for entry in history {
            let day = calendar.startOfDay(for: entry.date)
            dailyTotals[day, default: 0] += entry.amount
        }

        return dailyTotals
            .map { (date: $0.key, total: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Format cost as currency string
    func formatCost(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    // MARK: - Budget Management

    func setDailyBudget(_ budget: Double?) {
        dailyBudget = budget
        saveBudgetSettings()
    }

    func setMonthlyBudget(_ budget: Double?) {
        monthlyBudget = budget
        saveBudgetSettings()
    }

    var isDailyBudgetExceeded: Bool {
        guard let budget = dailyBudget else { return false }
        return dailyCost >= budget
    }

    var isMonthlyBudgetExceeded: Bool {
        guard let budget = monthlyBudget else { return false }
        return monthlyCost >= budget
    }

    var dailyBudgetRemaining: Double? {
        guard let budget = dailyBudget else { return nil }
        return max(0, budget - dailyCost)
    }

    var monthlyBudgetRemaining: Double? {
        guard let budget = monthlyBudget else { return nil }
        return max(0, budget - monthlyCost)
    }

    var dailyBudgetPercentUsed: Double? {
        guard let budget = dailyBudget, budget > 0 else { return nil }
        return min(1.0, dailyCost / budget)
    }

    var monthlyBudgetPercentUsed: Double? {
        guard let budget = monthlyBudget, budget > 0 else { return nil }
        return min(1.0, monthlyCost / budget)
    }

    // MARK: - Private Methods

    private func loadBudgetSettings() {
        if let dailyBudgetStr = try? Database.shared.getPreference(key: "daily_budget"),
           let daily = Double(dailyBudgetStr) {
            dailyBudget = daily
        }

        if let monthlyBudgetStr = try? Database.shared.getPreference(key: "monthly_budget"),
           let monthly = Double(monthlyBudgetStr) {
            monthlyBudget = monthly
        }
    }

    private func saveBudgetSettings() {
        do {
            if let daily = dailyBudget {
                try Database.shared.setPreference(key: "daily_budget", value: String(daily))
            } else {
                try Database.shared.deletePreference(key: "daily_budget")
            }

            if let monthly = monthlyBudget {
                try Database.shared.setPreference(key: "monthly_budget", value: String(monthly))
            } else {
                try Database.shared.deletePreference(key: "monthly_budget")
            }
        } catch {
            Log.cost.error("Failed to save budget settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestNotificationPermission() {
        guard !hasRequestedNotificationPermission else { return }
        hasRequestedNotificationPermission = true

        guard RuntimeEnvironment.supportsUserNotifications else {
            NSLog("CostTracker notifications disabled (not running inside a .app bundle).")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                Log.cost.error("Failed to request notification permission: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func checkBudgetAlerts() {
        // Check if we should alert about budget
        if isDailyBudgetExceeded {
            sendBudgetAlert(type: "daily", budget: dailyBudget!, spent: dailyCost)
        }

        if isMonthlyBudgetExceeded {
            sendBudgetAlert(type: "monthly", budget: monthlyBudget!, spent: monthlyCost)
        }
    }

    private func sendBudgetAlert(type: String, budget: Double, spent: Double) {
        guard RuntimeEnvironment.supportsUserNotifications else {
            Log.cost.info("Budget alert (\(type, privacy: .public)) skipped (notifications unavailable): budget=\(self.formatCost(budget), privacy: .public), spent=\(self.formatCost(spent), privacy: .public)")
            return
        }
        // Use ISO 8601 date format for stable, locale-independent keys
        let dateKey = SharedDateFormatters.iso8601.string(from: Date())

        let alertKey = "budget_alert_\(type)_\(dateKey)"

        // Check if we already sent an alert today
        if let _ = try? Database.shared.getPreference(key: alertKey) {
            return // Already alerted today
        }

        // Send notification using UserNotifications framework (modern API)
        let content = UNMutableNotificationContent()
        content.title = "Conductor Budget Alert"
        content.body = "You've exceeded your \(type) budget of \(formatCost(budget)). Current spend: \(formatCost(spent))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: alertKey,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Log.cost.error("Failed to send notification: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Mark as alerted
        do {
            try Database.shared.setPreference(key: alertKey, value: "1")
        } catch {
            Log.cost.error("Failed to mark alert key: \(error.localizedDescription, privacy: .public)")
        }

        // Clean up old alert keys (keep only last 7 days)
        cleanupOldAlertKeys()
    }

    private func cleanupOldAlertKeys() {
        // Remove alert keys older than 7 days to prevent accumulation
        let calendar = Calendar.current

        // Delete keys for days 8-30 ago (keeping only last 7 days)
        for dayOffset in 8...30 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let dateKey = SharedDateFormatters.iso8601.string(from: date)
                do {
                    try Database.shared.deletePreference(key: "budget_alert_daily_\(dateKey)")
                    try Database.shared.deletePreference(key: "budget_alert_monthly_\(dateKey)")
                } catch {
                    Log.cost.error("Failed to clean up alert key for \(dateKey, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

// MARK: - Cost Summary

struct CostSummary {
    let daily: Double
    let weekly: Double
    let monthly: Double
    let allTime: Double

    var formattedDaily: String {
        CostTracker.shared.formatCost(daily)
    }

    var formattedWeekly: String {
        CostTracker.shared.formatCost(weekly)
    }

    var formattedMonthly: String {
        CostTracker.shared.formatCost(monthly)
    }

    var formattedAllTime: String {
        CostTracker.shared.formatCost(allTime)
    }
}
