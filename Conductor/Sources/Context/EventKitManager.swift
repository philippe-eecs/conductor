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
        let calendarIdentifier: String
        let calendarTitle: String
        let externalIdentifier: String?

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
            let deduped = self.deduplicatedEvents(store.events(matching: predicate))
            return deduped.map(Self.mapCalendarEvent(from:)).sorted { $0.startDate < $1.startDate }
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
        location: String? = nil,
        calendarIdentifier: String? = nil
    ) async throws -> String {
        guard calendarAuthorizationStatus() == .fullAccess ||
              calendarAuthorizationStatus() == .writeOnly else {
            throw EventKitError.notAuthorized
        }
        guard startDate < endDate else {
            throw EventKitError.invalidDateRange
        }
        return try await perform { store in
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = startDate
            event.endDate = endDate
            event.notes = notes
            event.location = location

            if let calendarId = calendarIdentifier,
               let calendar = store.calendar(withIdentifier: calendarId) {
                event.calendar = calendar
            } else {
                event.calendar = store.defaultCalendarForNewEvents
            }

            try store.save(event, span: .thisEvent)
            return event.calendarItemIdentifier
        }
    }

    func updateCalendarEvent(
        eventId: String,
        title: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        notes: String? = nil,
        location: String? = nil,
        calendarIdentifier: String? = nil
    ) async throws -> CalendarEvent {
        guard calendarAuthorizationStatus() == .fullAccess ||
              calendarAuthorizationStatus() == .writeOnly else {
            throw EventKitError.notAuthorized
        }

        return try await perform { store in
            guard let event = self.resolvedEvent(eventId, store: store) else {
                throw EventKitError.notFound
            }

            if let title { event.title = title }
            if let startDate { event.startDate = startDate }
            if let endDate { event.endDate = endDate }
            if let notes { event.notes = notes }
            if let location { event.location = location }

            guard event.startDate < event.endDate else {
                throw EventKitError.invalidDateRange
            }

            if let calendarIdentifier,
               let calendar = store.calendar(withIdentifier: calendarIdentifier) {
                event.calendar = calendar
            }

            try store.save(event, span: .thisEvent)
            return Self.mapCalendarEvent(from: event)
        }
    }

    func deleteCalendarEvent(eventId: String) async throws {
        guard calendarAuthorizationStatus() == .fullAccess ||
              calendarAuthorizationStatus() == .writeOnly else {
            throw EventKitError.notAuthorized
        }

        try await perform { store in
            guard let event = self.resolvedEvent(eventId, store: store) else {
                throw EventKitError.notFound
            }
            try store.remove(event, span: .thisEvent)
        }
    }

    func findFirstAvailableSlot(
        windowStart: Date,
        windowEnd: Date,
        durationMinutes: Int,
        stepMinutes: Int = 15
    ) async -> (start: Date, end: Date)? {
        guard calendarAuthorizationStatus() == .fullAccess else { return nil }
        guard windowStart < windowEnd, durationMinutes > 0 else { return nil }

        let busyEvents = await getEvents(from: windowStart, to: windowEnd)
        let duration = TimeInterval(durationMinutes * 60)
        let step = TimeInterval(max(stepMinutes, 5) * 60)
        let busy = mergeIntervals(
            busyEvents.map { ($0.startDate, $0.endDate) }
                .filter { $0.0 < $0.1 }
                .sorted { $0.0 < $1.0 }
        )

        var candidate = alignUp(windowStart, to: step)
        while candidate.addingTimeInterval(duration) <= windowEnd {
            let candidateEnd = candidate.addingTimeInterval(duration)
            if let overlap = busy.first(where: { $0.start < candidateEnd && $0.end > candidate }) {
                candidate = alignUp(max(overlap.end, candidate.addingTimeInterval(step)), to: step)
                continue
            }
            return (candidate, candidateEnd)
        }
        return nil
    }

    // MARK: - Calendar internals

    private static func mapCalendarEvent(from event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.calendarItemIdentifier,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            location: event.location,
            notes: event.notes,
            isAllDay: event.isAllDay,
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            externalIdentifier: event.calendarItemExternalIdentifier
        )
    }

    private func resolvedEvent(_ eventId: String, store: EKEventStore) -> EKEvent? {
        if let event = store.calendarItem(withIdentifier: eventId) as? EKEvent {
            return event
        }
        if let event = store.event(withIdentifier: eventId) {
            return event
        }
        return nil
    }

    private func deduplicatedEvents(_ events: [EKEvent]) -> [EKEvent] {
        var seen: [String: EKEvent] = [:]
        for event in events {
            let key = dedupeKey(for: event)
            if let existing = seen[key] {
                if dedupeScore(event) > dedupeScore(existing) {
                    seen[key] = event
                }
            } else {
                seen[key] = event
            }
        }
        return Array(seen.values)
    }

    private func dedupeKey(for event: EKEvent) -> String {
        let startMinute = Int(event.startDate.timeIntervalSince1970 / 60)
        let endMinute = Int(event.endDate.timeIntervalSince1970 / 60)
        if let external = event.calendarItemExternalIdentifier, !external.isEmpty {
            return "ext|\(external)|\(startMinute)|\(endMinute)"
        }

        let normalizedTitle = event.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "untitled"
        let normalizedLocation = event.location?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return "fallback|\(normalizedTitle)|\(startMinute)|\(endMinute)|\(normalizedLocation)"
    }

    private func dedupeScore(_ event: EKEvent) -> Int {
        var score = 0
        if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 2
        }
        if let location = event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 1
        }
        if event.calendar.source.sourceType == .calDAV {
            score += 1
        }
        return score
    }

    private func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        guard var current = intervals.first else { return [] }
        var merged: [(start: Date, end: Date)] = []

        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current.end = max(current.end, interval.end)
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    private func alignUp(_ date: Date, to step: TimeInterval) -> Date {
        let raw = date.timeIntervalSinceReferenceDate
        let aligned = ceil(raw / step) * step
        return Date(timeIntervalSinceReferenceDate: aligned)
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
    case notAuthorized, notFound, timeout, invalidDateRange, unknown

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Calendar/Reminders access not authorized"
        case .notFound: return "Item not found"
        case .timeout: return "Operation timed out"
        case .invalidDateRange: return "End time must be after start time"
        case .unknown: return "Unknown error"
        }
    }
}
