import Foundation

struct DayReviewSnapshot {
    struct ThemeTaskBucket: Identifiable {
        let id: String
        let theme: Theme
        let tasks: [TodoTask]
    }

    struct WeekThemeSummary: Identifiable {
        let id: String
        let themeName: String
        let openCount: Int
        let highPriorityCount: Int
    }

    let date: Date
    let todayEvents: [EventKitManager.CalendarEvent]
    let activeTheme: Theme?
    let todayThemeBuckets: [ThemeTaskBucket]
    let looseTasks: [TodoTask]
    let weekSummaries: [WeekThemeSummary]
    let actionNeededEmails: [ProcessedEmail]
}

@MainActor
final class DayReviewService {
    static let shared = DayReviewService()

    private let dayReviewSeenKey = "day_review_last_seen_date"
    private let database: Database
    private let todayProvider: () -> String

    init(
        database: Database = .shared,
        todayProvider: @escaping () -> String = { DailyPlanningService.todayDateString }
    ) {
        self.database = database
        self.todayProvider = todayProvider
    }

    func shouldAutoShowOnLaunch() -> Bool {
        let today = todayProvider()
        return (try? database.getPreference(key: dayReviewSeenKey)) != today
    }

    func markShownToday() {
        let today = todayProvider()
        try? database.setPreference(key: dayReviewSeenKey, value: today)
    }

    func buildSnapshot(for date: Date = Date()) async -> DayReviewSnapshot {
        let todayEvents = await EventKitManager.shared.getEventsForDay(date)
        let activeTheme = ThemeService.shared.activeTheme(at: date)

        let allOpenTasks = (try? database.getAllTasks(includeCompleted: false)) ?? []
        let looseTheme = ThemeService.shared.ensureLooseTheme()

        let themes = (try? database.getThemes()) ?? []
        let nonLooseThemes = themes.filter { !$0.isLooseBucket }

        var buckets: [DayReviewSnapshot.ThemeTaskBucket] = []
        for theme in nonLooseThemes {
            let tasks = ThemeService.shared.tasksForTheme(theme.id)
                .filter { task in
                    guard let due = task.dueDate else { return false }
                    return Calendar.current.isDate(due, inSameDayAs: date) || due < date
                }
            if !tasks.isEmpty {
                buckets.append(.init(id: theme.id, theme: theme, tasks: tasks))
            }
        }

        let looseTaskIds = Set((try? database.getTaskIdsForTheme(id: looseTheme.id)) ?? [])
        let looseTasks = allOpenTasks.filter { looseTaskIds.contains($0.id) }

        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date
        var weekSummaries: [DayReviewSnapshot.WeekThemeSummary] = []
        for theme in nonLooseThemes {
            let tasks = ThemeService.shared.tasksForTheme(theme.id).filter { task in
                guard let due = task.dueDate else { return false }
                return due >= Calendar.current.startOfDay(for: date) && due <= weekEnd
            }
            guard !tasks.isEmpty else { continue }
            weekSummaries.append(
                .init(
                    id: theme.id,
                    themeName: theme.name,
                    openCount: tasks.count,
                    highPriorityCount: tasks.filter { $0.priority == .high }.count
                )
            )
        }
        weekSummaries.sort { lhs, rhs in
            if lhs.highPriorityCount != rhs.highPriorityCount {
                return lhs.highPriorityCount > rhs.highPriorityCount
            }
            return lhs.openCount > rhs.openCount
        }

        let actionNeededEmails = (try? database.getProcessedEmails(filter: .actionNeeded, limit: 10)) ?? []

        return DayReviewSnapshot(
            date: date,
            todayEvents: todayEvents,
            activeTheme: activeTheme,
            todayThemeBuckets: buckets,
            looseTasks: looseTasks,
            weekSummaries: weekSummaries,
            actionNeededEmails: actionNeededEmails
        )
    }
}
