import Foundation
import os

/// Dispatches approved actions to the appropriate service.
final class ActionExecutor {
    static let shared = ActionExecutor()

    private init() {}

    /// Safe action types that can be auto-executed without user approval.
    static let safeActionTypes: Set<AssistantActionRequest.ActionType> = [
        .createTodoTask, .createGoal, .completeGoal
    ]

    /// Execute an approved action. Returns true on success.
    func execute(_ action: AssistantActionRequest) async -> Bool {
        let payload = action.payload ?? [:]

        switch action.type {
        case .createTodoTask:
            return await createTodoTask(payload)
        case .updateTodoTask:
            return await updateTodoTask(payload)
        case .deleteTodoTask:
            return await deleteTodoTask(payload)
        case .createGoal:
            return await createGoal(payload)
        case .completeGoal:
            return await completeGoal(payload)
        case .createCalendarEvent:
            return await createCalendarEvent(payload)
        case .createReminder:
            return await createReminder(payload)
        case .sendEmail:
            return await sendEmail(payload)
        default:
            Log.action.error("Unsupported action type: \(String(describing: action.type), privacy: .public)")
            return false
        }
    }

    // MARK: - Task Actions

    private func createTodoTask(_ payload: [String: String]) async -> Bool {
        let title = payload["title"] ?? "Untitled Task"
        let notes = payload["notes"]
        let priority = TodoTask.Priority(rawValue: Int(payload["priority"] ?? "0") ?? 0) ?? .none
        let correlationId = payload["correlation_id"] ?? UUID().uuidString

        var dueDate: Date?
        if let dueDateStr = payload["due_date"] {
            dueDate = SharedDateFormatters.databaseDate.date(from: dueDateStr)
                ?? SharedDateFormatters.iso8601.date(from: dueDateStr)
        }

        let task = TodoTask(
            title: title,
            notes: notes,
            dueDate: dueDate,
            priority: priority
        )

        do {
            try Database.shared.createTask(task)
            let requestedThemeId = payload["theme_id"]
            let requestedThemeName = payload["theme_name"]
            let createIfMissing = payload["create_theme_if_missing"]?.lowercased() != "false"
            let requestedColor = payload["theme_color"] ?? "blue"
            let resolvedTheme = await ThemeService.shared.resolveTheme(
                themeId: requestedThemeId,
                themeName: requestedThemeName,
                createIfMissing: createIfMissing,
                color: requestedColor
            )
            await ThemeService.shared.assignTask(task.id, toThemeId: resolvedTheme?.id)

            var payloadMeta: [String: String] = ["title": title]
            if let dueDate {
                payloadMeta["due_date"] = SharedDateFormatters.databaseDate.string(from: dueDate)
            }
            if let resolvedTheme {
                payloadMeta["theme_id"] = resolvedTheme.id
                payloadMeta["theme_name"] = resolvedTheme.name
            } else {
                payloadMeta["theme_name"] = "Loose"
            }
            _ = OperationLogService.shared.record(
                operation: .created,
                entityType: "todo_task",
                entityId: task.id,
                source: "action:createTodoTask",
                status: .success,
                message: "Created todo task '\(title)'",
                payload: payloadMeta,
                correlationId: correlationId
            )
            Log.action.info("Created task: \(title, privacy: .public)")
            return true
        } catch {
            _ = OperationLogService.shared.record(
                operation: .failed,
                entityType: "todo_task",
                entityId: task.id,
                source: "action:createTodoTask",
                status: .failed,
                message: "Failed to create todo task '\(title)': \(error.localizedDescription)",
                payload: ["title": title],
                correlationId: correlationId
            )
            Log.action.error("Failed to create task: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func updateTodoTask(_ payload: [String: String]) async -> Bool {
        guard let taskId = payload["id"],
              var task = try? Database.shared.getTask(id: taskId) else {
            return false
        }
        let correlationId = payload["correlation_id"] ?? UUID().uuidString

        if let title = payload["title"] { task.title = title }
        if let notes = payload["notes"] { task.notes = notes }
        if let priorityStr = payload["priority"],
           let priorityInt = Int(priorityStr),
           let priority = TodoTask.Priority(rawValue: priorityInt) {
            task.priority = priority
        }

        do {
            try Database.shared.updateTask(task)
            _ = OperationLogService.shared.record(
                operation: .updated,
                entityType: "todo_task",
                entityId: task.id,
                source: "action:updateTodoTask",
                status: .success,
                message: "Updated todo task '\(task.title)'",
                correlationId: correlationId
            )
            return true
        } catch {
            _ = OperationLogService.shared.record(
                operation: .failed,
                entityType: "todo_task",
                entityId: task.id,
                source: "action:updateTodoTask",
                status: .failed,
                message: "Failed to update todo task '\(task.title)': \(error.localizedDescription)",
                correlationId: correlationId
            )
            Log.action.error("Failed to update task: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func deleteTodoTask(_ payload: [String: String]) async -> Bool {
        guard let taskId = payload["id"] else { return false }
        let correlationId = payload["correlation_id"] ?? UUID().uuidString
        let taskTitle = ((try? Database.shared.getTask(id: taskId)) ?? nil)?.title ?? taskId
        do {
            try Database.shared.deleteTask(id: taskId)
            _ = OperationLogService.shared.record(
                operation: .deleted,
                entityType: "todo_task",
                entityId: taskId,
                source: "action:deleteTodoTask",
                status: .success,
                message: "Deleted todo task '\(taskTitle)'",
                correlationId: correlationId
            )
            return true
        } catch {
            _ = OperationLogService.shared.record(
                operation: .failed,
                entityType: "todo_task",
                entityId: taskId,
                source: "action:deleteTodoTask",
                status: .failed,
                message: "Failed to delete todo task '\(taskTitle)': \(error.localizedDescription)",
                correlationId: correlationId
            )
            Log.action.error("Failed to delete task: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Goal Actions

    private func createGoal(_ payload: [String: String]) async -> Bool {
        let text = payload["text"] ?? payload["title"] ?? "Untitled Goal"
        let priority = Int(payload["priority"] ?? "0") ?? 0
        let date = payload["date"] ?? DailyPlanningService.todayDateString

        let goal = DailyGoal(date: date, goalText: text, priority: priority)

        do {
            try Database.shared.saveDailyGoal(goal)
            Log.action.info("Created goal: \(text, privacy: .public)")
            return true
        } catch {
            Log.action.error("Failed to create goal: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func completeGoal(_ payload: [String: String]) async -> Bool {
        guard let goalId = payload["id"] else { return false }
        do {
            try Database.shared.markGoalCompleted(id: goalId)
            return true
        } catch {
            Log.action.error("Failed to complete goal: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Calendar Actions

    private func createCalendarEvent(_ payload: [String: String]) async -> Bool {
        let title = payload["title"] ?? "Untitled Event"
        let startStr = payload["start_date"] ?? payload["start"]
        let endStr = payload["end_date"] ?? payload["end"]
        let location = payload["location"]
        let correlationId = payload["correlation_id"] ?? UUID().uuidString

        guard let startStr, let start = parseDateTime(startStr) else {
            Log.action.error("Missing or invalid start date for calendar event")
            _ = OperationLogService.shared.record(
                operation: .failed,
                entityType: "calendar_event",
                source: "action:createCalendarEvent",
                status: .failed,
                message: "Missing or invalid start date for calendar event '\(title)'",
                correlationId: correlationId
            )
            return false
        }

        let end = endStr.flatMap(parseDateTime) ?? start.addingTimeInterval(3600)

        do {
            let eventId = try await EventKitManager.shared.createCalendarEvent(
                title: title,
                startDate: start,
                endDate: end,
                notes: location.map { "Location: \($0)" }
            )
            _ = OperationLogService.shared.record(
                operation: .created,
                entityType: "calendar_event",
                entityId: eventId,
                source: "action:createCalendarEvent",
                status: .success,
                message: "Created calendar event '\(title)'",
                payload: [
                    "start_date": SharedDateFormatters.iso8601DateTime.string(from: start),
                    "end_date": SharedDateFormatters.iso8601DateTime.string(from: end)
                ],
                correlationId: correlationId
            )
            Log.action.info("Created calendar event: \(title, privacy: .public)")
            return true
        } catch {
            _ = OperationLogService.shared.record(
                operation: .failed,
                entityType: "calendar_event",
                source: "action:createCalendarEvent",
                status: .failed,
                message: "Failed to create calendar event '\(title)': \(error.localizedDescription)",
                correlationId: correlationId
            )
            Log.action.error("Failed to create calendar event: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Reminder Actions

    private func createReminder(_ payload: [String: String]) async -> Bool {
        let title = payload["title"] ?? "Untitled Reminder"
        let dueDateStr = payload["due_date"]
        let dueDate = dueDateStr.flatMap(parseDateTime)

        do {
            _ = try await EventKitManager.shared.createReminder(title: title, dueDate: dueDate)
            Log.action.info("Created reminder: \(title, privacy: .public)")
            return true
        } catch {
            Log.action.error("Failed to create reminder: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Email Actions

    private func sendEmail(_ payload: [String: String]) async -> Bool {
        guard let to = payload["to"],
              let subject = payload["subject"],
              let body = payload["body"] else {
            Log.action.error("Missing required email fields")
            return false
        }

        let cc = payload["cc"]
        return await MailService.shared.sendEmail(to: to, subject: subject, body: body, cc: cc)
    }

    // MARK: - Helpers

    private func parseDateTime(_ string: String) -> Date? {
        // Try ISO 8601 with time
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) { return date }

        // Try date-only
        if let date = SharedDateFormatters.databaseDate.date(from: string) { return date }
        if let date = SharedDateFormatters.iso8601.date(from: string) { return date }

        // Try natural date parsing
        let fullFormatter = DateFormatter()
        fullFormatter.locale = Locale(identifier: "en_US_POSIX")
        fullFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = fullFormatter.date(from: string) { return date }

        fullFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        if let date = fullFormatter.date(from: string) { return date }

        return nil
    }
}
