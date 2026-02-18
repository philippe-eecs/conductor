import Foundation

final class OperationLogService {
    static let shared = OperationLogService()

    private init() {}

    @discardableResult
    func record(
        operation: OperationKind,
        entityType: String,
        entityId: String? = nil,
        source: String,
        status: OperationStatus,
        message: String,
        payload: [String: String] = [:],
        correlationId: String = UUID().uuidString
    ) -> OperationReceipt {
        let event = OperationEvent(
            correlationId: correlationId,
            operation: operation,
            entityType: entityType,
            entityId: entityId,
            source: source,
            status: status,
            message: message,
            payload: payload
        )

        try? Database.shared.saveOperationEvent(event)

        Task { @MainActor in
            AppState.shared.recordOperationEvent(event)
        }

        return OperationReceipt(from: event)
    }

    func recent(limit: Int = 100) -> [OperationEvent] {
        (try? Database.shared.getRecentOperationEvents(limit: limit)) ?? []
    }
}
