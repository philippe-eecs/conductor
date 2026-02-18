import EventKit
import Foundation

final class EventKitManager: @unchecked Sendable {
    static let shared = EventKitManager()

    private let accessQueue = DispatchQueue(label: "com.conductor.eventkit")
    private let eventStore = EKEventStore()

    private init() {}

    private func perform<T>(_ body: @escaping (EKEventStore) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            accessQueue.async {
                do {
                    let value = try body(self.eventStore)
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func perform<T>(_ body: @escaping (EKEventStore) -> T) async -> T {
        await withCheckedContinuation { continuation in
            accessQueue.async {
                continuation.resume(returning: body(self.eventStore))
            }
        }
    }

    private func resetEventStoreCache() async {
        await perform { store in store.reset() }
    }

    // MARK: - Authorization

    enum AuthorizationStatus {
        case notDetermined, restricted, denied, fullAccess, writeOnly
    }

    func calendarAuthorizationStatus() -> AuthorizationStatus {
        mapStatus(EKEventStore.authorizationStatus(for: .event))
    }

    func remindersAuthorizationStatus() -> AuthorizationStatus {
        mapStatus(EKEventStore.authorizationStatus(for: .reminder))
    }

    private func mapStatus(_ status: EKAuthorizationStatus) -> AuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess: return .fullAccess
        case .writeOnly: return .writeOnly
        case .authorized: return .fullAccess
        @unknown default: return .denied
        }
    }

    func requestCalendarAccess() async -> Bool {
        guard RuntimeEnvironment.supportsTCCPrompts else {
            Log.eventKit.info("Calendar access request skipped (not in .app bundle)")
            return false
        }
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToEvents()
            if granted { await resetEventStoreCache() }
            return granted
        } catch {
            Log.eventKit.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func requestRemindersAccess() async -> Bool {
        guard RuntimeEnvironment.supportsTCCPrompts else {
            Log.eventKit.info("Reminders access request skipped (not in .app bundle)")
            return false
        }
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToReminders()
            if granted { await resetEventStoreCache() }
            return granted
        } catch {
            Log.eventKit.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Calendar Events

    struct CalendarEvent {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String?
        let notes: String?
        let isAllDay: Bool

        var time: String {
            isAllDay ? "All day" : SharedDateFormatters.shortTime.string(from: startDate)
        }

        var duration: String {
            let interval = endDate.timeIntervalSince(startDate)
            let hours = Int(interval) / 3600
            let minutes = Int(interval) % 3600 / 60
            if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
            else if hours > 0 { return "\(hours)h" }
            else { return "\(minutes)m" }
        }
    }

    func getEvents(from startDate: Date, to endDate: Date) async -> [CalendarEvent] {
        guard calendarAuthorizationStatus() == .fullAccess else { return [] }

        return await perform { store in
            let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
            return store.events(matching: predicate).map { event in
                CalendarEvent(
                    id: event.eventIdentifier,
                    title: event.title ?? "Untitled",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    location: event.location,
                    notes: event.notes,
                    isAllDay: event.isAllDay
                )
            }.sorted { $0.startDate < $1.startDate }
        }
    }

    func getTodayEvents() async -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return await getEvents(from: start, to: end)
    }

    func createCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String? = nil,
        calendarIdentifier: String? = nil
    ) async throws -> String {
        guard calendarAuthorizationStatus() == .fullAccess ||
              calendarAuthorizationStatus() == .writeOnly else {
            throw EventKitError.notAuthorized
        }
        return try await perform { store in
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = startDate
            event.endDate = endDate
            event.notes = notes

            if let calendarId = calendarIdentifier,
               let calendar = store.calendar(withIdentifier: calendarId) {
                event.calendar = calendar
            } else {
                event.calendar = store.defaultCalendarForNewEvents
            }

            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        }
    }

    // MARK: - Reminders

    struct Reminder {
        let id: String
        let title: String
        let notes: String?
        let dueDate: String?
        let isCompleted: Bool
        let priority: Int
    }

    func getUpcomingReminders(limit: Int = 20) async -> [Reminder] {
        guard remindersAuthorizationStatus() == .fullAccess else { return [] }

        do {
            return try await withThrowingTaskGroup(of: [Reminder].self) { group in
                group.addTask {
                    await withCheckedContinuation { continuation in
                        self.accessQueue.async {
                            let predicate = self.eventStore.predicateForIncompleteReminders(
                                withDueDateStarting: nil,
                                ending: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                                calendars: nil
                            )
                            self.eventStore.fetchReminders(matching: predicate) { ekReminders in
                                guard let ekReminders else {
                                    continuation.resume(returning: [])
                                    return
                                }
                                let reminders = ekReminders.prefix(limit).map { reminder in
                                    var dueDateStr: String?
                                    if let dueDate = reminder.dueDateComponents?.date {
                                        dueDateStr = SharedDateFormatters.mediumDateTime.string(from: dueDate)
                                    }
                                    return Reminder(
                                        id: reminder.calendarItemIdentifier,
                                        title: reminder.title ?? "Untitled",
                                        notes: reminder.notes,
                                        dueDate: dueDateStr,
                                        isCompleted: reminder.isCompleted,
                                        priority: reminder.priority
                                    )
                                }
                                continuation.resume(returning: Array(reminders))
                            }
                        }
                    }
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw EventKitError.timeout
                }

                if let result = try await group.next() {
                    group.cancelAll()
                    return result
                }
                return []
            }
        } catch is EventKitError {
            Log.eventKit.warning("Reminders fetch timed out")
            return []
        } catch {
            Log.eventKit.error("Reminders fetch error: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

enum EventKitError: LocalizedError {
    case notAuthorized, notFound, timeout, unknown

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Calendar/Reminders access not authorized"
        case .notFound: return "Item not found"
        case .timeout: return "Operation timed out"
        case .unknown: return "Unknown error"
        }
    }
}
