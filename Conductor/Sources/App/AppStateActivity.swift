import SwiftUI

// MARK: - Activity Logging, Operation Events & Action Approval

extension AppState {

    // MARK: - Cost Tracking

    func loadCostData() {
        Task {
            let costs = await Task.detached(priority: .userInitiated) {
                let daily = (try? Database.shared.getDailyCost()) ?? 0
                let weekly = (try? Database.shared.getWeeklyCost()) ?? 0
                let monthly = (try? Database.shared.getMonthlyCost()) ?? 0
                return (daily, weekly, monthly)
            }.value
            self.dailyCost = costs.0
            self.weeklyCost = costs.1
            self.monthlyCost = costs.2
        }
    }

    // MARK: - Operation Events

    func refreshOperationEvents(limit: Int = 100) {
        Task {
            let events = await Task.detached(priority: .userInitiated) {
                (try? Database.shared.getRecentOperationEvents(limit: limit)) ?? []
            }.value
            self.recentOperationEvents = events
        }
    }

    var latestOperationEvent: OperationEvent? {
        recentOperationEvents.first
    }

    // MARK: - Action Approval

    func approveAction(_ action: AssistantActionRequest) {
        pendingActions.removeAll { $0.id == action.id }
        pendingApprovalCount = max(0, pendingApprovalCount - 1)
        let correlationId = action.payload?["correlation_id"] ?? UUID().uuidString
        Task {
            let success = await ActionExecutor.shared.execute(action)
            logActivity(.system, success ? "Action approved: \(action.title)" : "Action failed: \(action.title)")
            await appendOperationReceiptMessage(
                correlationId: correlationId,
                fallbackStatus: success ? .success : .failed,
                fallbackMessage: success ? "Approved action: \(action.title)" : "Failed action: \(action.title)"
            )
        }
        Task.detached(priority: .utility) {
            try? Database.shared.recordBehaviorEvent(type: .actionApproved, entityId: action.id)
        }
    }

    func rejectAction(_ action: AssistantActionRequest) {
        pendingActions.removeAll { $0.id == action.id }
        pendingApprovalCount = max(0, pendingApprovalCount - 1)
        logActivity(.system, "Action rejected: \(action.title)")
        let correlationId = action.payload?["correlation_id"] ?? UUID().uuidString
        Task {
            await appendOperationReceiptMessage(
                correlationId: correlationId,
                fallbackStatus: .failed,
                fallbackMessage: "Rejected action: \(action.title)"
            )
        }
        Task.detached(priority: .utility) {
            try? Database.shared.recordBehaviorEvent(type: .actionRejected, entityId: action.id)
        }
    }

    func approveAllActions() {
        let actions = pendingActions
        pendingActions.removeAll()
        pendingApprovalCount = 0
        for action in actions {
            let correlationId = action.payload?["correlation_id"] ?? UUID().uuidString
            Task {
                let success = await ActionExecutor.shared.execute(action)
                logActivity(.system, success ? "Action approved: \(action.title)" : "Action failed: \(action.title)")
                await appendOperationReceiptMessage(
                    correlationId: correlationId,
                    fallbackStatus: success ? .success : .failed,
                    fallbackMessage: success ? "Approved action: \(action.title)" : "Failed action: \(action.title)"
                )
            }
        }
    }

    // MARK: - Activity Logging

    func logActivity(_ type: ActivityLogEntry.ActivityType, _ message: String, metadata: [String: String]? = nil) {
        let entry = ActivityLogEntry(type: type, message: message, metadata: metadata)
        recentActivity.insert(entry, at: 0)

        // Keep only last 100 entries for better audit trail
        if recentActivity.count > 100 {
            recentActivity = Array(recentActivity.prefix(100))
        }
    }

    func recordOperationEvent(_ event: OperationEvent) {
        recentOperationEvents.insert(event, at: 0)
        if recentOperationEvents.count > 200 {
            recentOperationEvents = Array(recentOperationEvents.prefix(200))
        }

        var metadata: [String: String] = [
            "Operation": event.operation.rawValue,
            "Entity": event.entityType,
            "Status": event.status.rawValue,
            "Source": event.source,
            "Correlation": event.correlationId
        ]
        if let entityId = event.entityId {
            metadata["Entity ID"] = entityId
        }
        logActivity(.operation, event.message, metadata: metadata)
    }

    /// Log a security-related event with detailed metadata
    func logSecurityEvent(_ action: String, allowed: Bool, details: [String: String] = [:]) {
        var metadata = details
        metadata["Allowed"] = allowed ? "Yes" : "No"
        metadata["Time"] = SharedDateFormatters.iso8601.string(from: Date())

        let message = allowed ? "Allowed: \(action)" : "Blocked: \(action)"
        logActivity(.security, message, metadata: metadata)
    }
}
