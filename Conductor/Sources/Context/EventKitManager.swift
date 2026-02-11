import EventKit
import Foundation

final class EventKitManager: @unchecked Sendable {
    static let shared = EventKitManager()

    // EKEventStore is not documented as thread-safe. Conductor queries calendar/reminders
    // from various async contexts, so we serialize all EKEventStore usage through one queue.
    private let accessQueue = DispatchQueue(label: "com.conductor.eventkit")
    private let accessQueueKey = DispatchSpecificKey<UInt8>()
    private let eventStore = EKEventStore()

    private init() {
        accessQueue.setSpecific(key: accessQueueKey, value: 1)
    }

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
        await perform { store in
            store.reset()
        }
    }

    // MARK: - Authorization

    enum AuthorizationStatus {
        case notDetermined
        case restricted
        case denied
        case fullAccess
        case writeOnly
    }

    func calendarAuthorizationStatus() -> AuthorizationStatus {
        if #available(macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .fullAccess:
                return .fullAccess
            case .writeOnly:
                return .writeOnly
            @unknown default:
                return .denied
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .authorized:
                return .fullAccess
            case .fullAccess:
                return .fullAccess
            case .writeOnly:
                return .writeOnly
            @unknown default:
                return .denied
            }
        }
    }

    func remindersAuthorizationStatus() -> AuthorizationStatus {
        if #available(macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .fullAccess:
                return .fullAccess
            case .writeOnly:
                return .writeOnly
            @unknown default:
                return .denied
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .authorized:
                return .fullAccess
            case .fullAccess:
                return .fullAccess
            case .writeOnly:
                return .writeOnly
            @unknown default:
                return .denied
            }
        }
    }

    func requestCalendarAccess() async -> Bool {
        guard RuntimeEnvironment.supportsTCCPrompts else {
            print("Calendar access request skipped (not running inside a .app bundle).")
            return false
        }
        // Use a dedicated store for requesting permission so we don't race with
        // concurrent reads/writes on our serialized `eventStore`.
        let store = EKEventStore()
        if #available(macOS 14.0, *) {
            do {
                let granted = try await store.requestFullAccessToEvents()
                if granted {
                    await resetEventStoreCache()
                }
                return granted
            } catch {
                print("Calendar access request failed: \(error)")
                return false
            }
        } else {
            let granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        print("Calendar access request failed: \(error)")
                    }
                    continuation.resume(returning: granted)
                }
            }
            if granted {
                await resetEventStoreCache()
            }
            return granted
        }
    }

    func requestRemindersAccess() async -> Bool {
        guard RuntimeEnvironment.supportsTCCPrompts else {
            print("Reminders access request skipped (not running inside a .app bundle).")
            return false
        }
        // Use a dedicated store for requesting permission so we don't race with
        // concurrent reads/writes on our serialized `eventStore`.
        let store = EKEventStore()
        if #available(macOS 14.0, *) {
            do {
                let granted = try await store.requestFullAccessToReminders()
                if granted {
                    await resetEventStoreCache()
                }
                return granted
            } catch {
                print("Reminders access request failed: \(error)")
                return false
            }
        } else {
            let granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        print("Reminders access request failed: \(error)")
                    }
                    continuation.resume(returning: granted)
                }
            }
            if granted {
                await resetEventStoreCache()
            }
            return granted
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
            if isAllDay {
                return "All day"
            }
            return SharedDateFormatters.shortTime.string(from: startDate)
        }

        var duration: String {
            let interval = endDate.timeIntervalSince(startDate)
            let hours = Int(interval) / 3600
            let minutes = Int(interval) % 3600 / 60

            if hours > 0 && minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else if hours > 0 {
                return "\(hours)h"
            } else {
                return "\(minutes)m"
            }
        }
    }

    /// Fetches calendar events in a date range.
    /// Note: This returns an empty list if calendar access isn't granted.
    func getEvents(from startDate: Date, to endDate: Date) async -> [CalendarEvent] {
        guard calendarAuthorizationStatus() == .fullAccess else {
            return []
        }

        return await perform { store in
            let predicate = store.predicateForEvents(
                withStart: startDate,
                end: endDate,
                calendars: nil
            )

            let events = store.events(matching: predicate)

            return events.map { event in
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
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return await getEvents(from: startOfDay, to: endOfDay)
    }

    func getUpcomingEvents(days: Int = 7) async -> [CalendarEvent] {
        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .day, value: days, to: startDate)!
        return await getEvents(from: startDate, to: endDate)
    }

    /// Get events for an entire month
    func getMonthEvents(for date: Date) async -> [CalendarEvent] {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return []
        }
        return await getEvents(from: startOfMonth, to: endOfMonth)
    }

    /// Get events for a specific week
    func getWeekEvents(for date: Date) async -> [CalendarEvent] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }
        return await getEvents(from: interval.start, to: interval.end)
    }

    /// Get events for a specific day
    func getEventsForDay(_ date: Date) async -> [CalendarEvent] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            return []
        }
        return await getEvents(from: interval.start, to: interval.end)
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

            // Use default calendar or specified calendar
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
        guard remindersAuthorizationStatus() == .fullAccess else {
            return []
        }

        // Use a task group with timeout to prevent indefinite hangs
        do {
            return try await withThrowingTaskGroup(of: [Reminder].self) { group in
                // Task 1: Fetch reminders
                group.addTask {
                    await withCheckedContinuation { continuation in
                        self.accessQueue.async {
                            let predicate = self.eventStore.predicateForIncompleteReminders(
                                withDueDateStarting: nil,
                                ending: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                                calendars: nil
                            )

                            self.eventStore.fetchReminders(matching: predicate) { ekReminders in
                                guard let ekReminders = ekReminders else {
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

                // Task 2: Timeout after 5 seconds
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw EventKitError.timeout
                }

                // Return the first to complete, cancel the other
                if let result = try await group.next() {
                    group.cancelAll()
                    return result
                }
                return []
            }
        } catch is EventKitError {
            print("Reminders fetch timed out after 5 seconds")
            return []
        } catch {
            print("Reminders fetch error: \(error)")
            return []
        }
    }

    func createReminder(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        priority: Int = 0
    ) async throws -> String {
        guard remindersAuthorizationStatus() == .fullAccess else {
            throw EventKitError.notAuthorized
        }
        return try await perform { store in
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.notes = notes
            reminder.priority = priority

            if let dueDate = dueDate {
                let calendar = Calendar.current
                reminder.dueDateComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
            }

            // Use default reminders list
            reminder.calendar = store.defaultCalendarForNewReminders()

            try store.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        }
    }

    func completeReminder(id: String) async throws {
        guard remindersAuthorizationStatus() == .fullAccess else {
            throw EventKitError.notAuthorized
        }
        return try await withCheckedThrowingContinuation { continuation in
            accessQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: EventKitError.unknown)
                    return
                }

                let predicate = self.eventStore.predicateForReminders(in: nil)

                self.eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
                    guard let self else {
                        continuation.resume(throwing: EventKitError.unknown)
                        return
                    }

                    guard let reminders,
                          let reminder = reminders.first(where: { $0.calendarItemIdentifier == id }) else {
                        continuation.resume(throwing: EventKitError.notFound)
                        return
                    }

                    self.accessQueue.async { [weak self] in
                        guard let self else {
                            continuation.resume(throwing: EventKitError.unknown)
                            return
                        }

                        reminder.isCompleted = true
                        do {
                            try self.eventStore.save(reminder, commit: true)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }
}

enum EventKitError: LocalizedError {
    case notAuthorized
    case notFound
    case timeout
    case unknown

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar/Reminders access not authorized"
        case .notFound:
            return "Item not found"
        case .timeout:
            return "Operation timed out"
        case .unknown:
            return "Unknown error"
        }
    }
}
