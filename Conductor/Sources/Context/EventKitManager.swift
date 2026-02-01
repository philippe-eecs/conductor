import EventKit
import Foundation

final class EventKitManager {
    static let shared = EventKitManager()

    private let eventStore = EKEventStore()

    private init() {}

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
            @unknown default:
                return .denied
            }
        }
    }

    func requestCalendarAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                print("Calendar access request failed: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        print("Calendar access request failed: \(error)")
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func requestRemindersAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                print("Reminders access request failed: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        print("Reminders access request failed: \(error)")
                    }
                    continuation.resume(returning: granted)
                }
            }
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
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: startDate)
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

    func getTodayEvents() async -> [CalendarEvent] {
        guard calendarAuthorizationStatus() == .fullAccess else {
            return []
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)

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

    func getUpcomingEvents(days: Int = 7) async -> [CalendarEvent] {
        guard calendarAuthorizationStatus() == .fullAccess else {
            return []
        }

        let calendar = Calendar.current
        let startDate = Date()
        let endDate = calendar.date(byAdding: .day, value: days, to: startDate)!

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)

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

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes

        // Use default calendar or specified calendar
        if let calendarId = calendarIdentifier,
           let calendar = eventStore.calendar(withIdentifier: calendarId) {
            event.calendar = calendar
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }

        try eventStore.save(event, span: .thisEvent)

        return event.eventIdentifier
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

        return await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
                calendars: nil
            )

            eventStore.fetchReminders(matching: predicate) { ekReminders in
                guard let ekReminders = ekReminders else {
                    continuation.resume(returning: [])
                    return
                }

                let reminders = ekReminders.prefix(limit).map { reminder in
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short

                    var dueDateStr: String?
                    if let dueDate = reminder.dueDateComponents?.date {
                        dueDateStr = formatter.string(from: dueDate)
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

    func createReminder(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        priority: Int = 0
    ) async throws -> String {
        guard remindersAuthorizationStatus() == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        let reminder = EKReminder(eventStore: eventStore)
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
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        try eventStore.save(reminder, commit: true)

        return reminder.calendarItemIdentifier
    }

    func completeReminder(id: String) async throws {
        guard remindersAuthorizationStatus() == .fullAccess else {
            throw EventKitError.notAuthorized
        }

        let predicate = eventStore.predicateForReminders(in: nil)

        return try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
                guard let self = self else {
                    continuation.resume(throwing: EventKitError.unknown)
                    return
                }

                guard let reminders = reminders,
                      let reminder = reminders.first(where: { $0.calendarItemIdentifier == id }) else {
                    continuation.resume(throwing: EventKitError.notFound)
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

enum EventKitError: LocalizedError {
    case notAuthorized
    case notFound
    case unknown

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar/Reminders access not authorized"
        case .notFound:
            return "Item not found"
        case .unknown:
            return "Unknown error"
        }
    }
}
