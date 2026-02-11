import Foundation

protocol EventKitProviding {
    func calendarAuthorizationStatus() -> EventKitManager.AuthorizationStatus
    func remindersAuthorizationStatus() -> EventKitManager.AuthorizationStatus
    func getTodayEvents() async -> [EventKitManager.CalendarEvent]
    func getUpcomingReminders(limit: Int) async -> [EventKitManager.Reminder]
    func getMonthEvents(for date: Date) async -> [EventKitManager.CalendarEvent]
    func getWeekEvents(for date: Date) async -> [EventKitManager.CalendarEvent]
    func getEventsForDay(_ date: Date) async -> [EventKitManager.CalendarEvent]
}

extension EventKitManager: EventKitProviding {}
