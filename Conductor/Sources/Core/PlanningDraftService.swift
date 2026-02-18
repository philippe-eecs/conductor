import Foundation

struct ThemeBlockProposal: Identifiable {
    let id: String
    let theme: Theme
    let startTime: Date
    let endTime: Date
    let taskIds: [String]
    let rationale: String
}

struct PlanningDraft {
    let id: String
    let date: Date
    let proposals: [ThemeBlockProposal]
    let createdAt: Date
    let rationale: String
}

struct PublishPlanResult {
    let publishedBlockIds: [String]
    let failedBlockIds: [String]
}

struct WeekPlanningDraft {
    let id: String
    let startDate: Date
    let dailyDrafts: [PlanningDraft]
    let createdAt: Date
}

@MainActor
final class PlanningDraftService {
    static let shared = PlanningDraftService()

    private var draftsById: [String: PlanningDraft] = [:]

    private init() {}

    func planDay(for date: Date = Date()) async -> PlanningDraft {
        let themes = ((try? Database.shared.getThemes()) ?? [])
            .filter { !$0.isArchived && !$0.isLooseBucket }

        let calendar = Calendar.current
        let minimumSchedulableStart = calendar.isDateInToday(date)
            ? TemporalContext.roundedMinimumStart(from: Date())
            : (calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date)

        let dayEvents = await EventKitManager.shared.getEventsForDay(date)
        let existingBlocks = (try? Database.shared.getThemeBlocksForDay(date)) ?? []

        var proposals: [ThemeBlockProposal] = []
        var slot = max(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date, minimumSchedulableStart)

        for theme in themes {
            let dueTasks = ThemeService.shared.tasksForTheme(theme.id)
                .filter { task in
                    guard let due = task.dueDate else { return false }
                    return Calendar.current.isDate(due, inSameDayAs: date) || due < date
                }

            guard !dueTasks.isEmpty else { continue }

            let duration = max(30, min(theme.defaultDurationMinutes, 180))
            let preferredStart = max(parsePreferredTime(theme.defaultStartTime, date: date) ?? slot, minimumSchedulableStart)
            let scheduledStart = nextAvailableStart(
                preferred: max(preferredStart, slot),
                durationMinutes: duration,
                events: dayEvents,
                existingBlocks: existingBlocks + proposals.map { proposal in
                    ThemeBlock(
                        themeId: proposal.theme.id,
                        startTime: proposal.startTime,
                        endTime: proposal.endTime,
                        status: .draft
                    )
                },
                minimumStart: minimumSchedulableStart
            )

            let end = scheduledStart.addingTimeInterval(Double(duration * 60))
            let taskIds = Array(dueTasks.prefix(3).map(\.id))

            proposals.append(
                ThemeBlockProposal(
                    id: UUID().uuidString,
                    theme: theme,
                    startTime: scheduledStart,
                    endTime: end,
                    taskIds: taskIds,
                    rationale: "Scheduled from theme defaults and due tasks"
                )
            )

            slot = end.addingTimeInterval(15 * 60)
        }

        let draft = PlanningDraft(
            id: UUID().uuidString,
            date: date,
            proposals: proposals,
            createdAt: Date(),
            rationale: "Theme-first day plan using due work and existing commitments"
        )
        draftsById[draft.id] = draft
        return draft
    }

    func planWeek(startingOn startDate: Date = Date()) async -> WeekPlanningDraft {
        let calendar = Calendar.current
        let weekStart = calendar.startOfDay(for: startDate)
        var dailyDrafts: [PlanningDraft] = []

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let draft = await planDay(for: day)
            dailyDrafts.append(draft)
        }

        return WeekPlanningDraft(
            id: UUID().uuidString,
            startDate: weekStart,
            dailyDrafts: dailyDrafts,
            createdAt: Date()
        )
    }

    func getDraft(id: String) -> PlanningDraft? {
        draftsById[id]
    }

    func applyDraft(
        _ draft: PlanningDraft,
        status: ThemeBlock.Status = .planned,
        overrides: [String: (Date, Date)] = [:]
    ) throws -> [ThemeBlock] {
        var blocks: [ThemeBlock] = []
        for proposal in draft.proposals {
            let override = overrides[proposal.id]
            let startTime = override?.0 ?? proposal.startTime
            let endTime = override?.1 ?? proposal.endTime
            let block = ThemeBlock(
                themeId: proposal.theme.id,
                startTime: startTime,
                endTime: endTime,
                status: status
            )
            try Database.shared.createThemeBlock(block)
            blocks.append(block)
        }
        return blocks
    }

    func applyDraft(id: String, status: ThemeBlock.Status = .planned) throws -> [ThemeBlock] {
        guard let draft = draftsById[id] else { return [] }
        return try applyDraft(draft, status: status, overrides: [:])
    }

    func applyDraft(
        id: String,
        status: ThemeBlock.Status = .planned,
        overrides: [String: (Date, Date)] = [:]
    ) throws -> [ThemeBlock] {
        guard let draft = draftsById[id] else { return [] }
        return try applyDraft(draft, status: status, overrides: overrides)
    }

    func publishThemeBlocks(_ blockIds: [String]) async -> PublishPlanResult {
        var published: [String] = []
        var failed: [String] = []

        for id in blockIds {
            guard var block = try? Database.shared.getThemeBlock(id: id),
                  let theme = try? Database.shared.getTheme(id: block.themeId) else {
                failed.append(id)
                continue
            }

            do {
                let eventId = try await EventKitManager.shared.createCalendarEvent(
                    title: "Focus: \(theme.name)",
                    startDate: block.startTime,
                    endDate: block.endTime,
                    notes: theme.objective
                )
                block.status = .published
                block.calendarEventId = eventId
                block.updatedAt = Date()
                try Database.shared.updateThemeBlock(block)
                published.append(id)
            } catch {
                failed.append(id)
            }
        }

        return PublishPlanResult(publishedBlockIds: published, failedBlockIds: failed)
    }

    private func parsePreferredTime(_ hhmm: String?, date: Date) -> Date? {
        guard let hhmm else { return nil }
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    private func nextAvailableStart(
        preferred: Date,
        durationMinutes: Int,
        events: [EventKitManager.CalendarEvent],
        existingBlocks: [ThemeBlock],
        minimumStart: Date
    ) -> Date {
        var start = max(preferred, minimumStart)
        let duration = TimeInterval(durationMinutes * 60)

        let intervals: [(Date, Date)] = events.map { ($0.startDate, $0.endDate) } + existingBlocks.map { ($0.startTime, $0.endTime) }

        while true {
            let end = start.addingTimeInterval(duration)
            let conflict = intervals.first { interval in
                interval.0 < end && interval.1 > start
            }
            guard let conflict else { return start }
            start = conflict.1.addingTimeInterval(10 * 60)
        }
    }
}
