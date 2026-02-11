import Foundation

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
            print("[ActionExecutor] Unsupported action type: \(action.type)")
            return false
        }
    }

    // MARK: - Task Actions

    private func createTodoTask(_ payload: [String: String]) async -> Bool {
        let title = payload["title"] ?? "Untitled Task"
        let notes = payload["notes"]
        let priority = TodoTask.Priority(rawValue: Int(payload["priority"] ?? "0") ?? 0) ?? .none

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
            print("[ActionExecutor] Created task: \(title)")
            return true
        } catch {
            print("[ActionExecutor] Failed to create task: \(error)")
            return false
        }
    }

    private func updateTodoTask(_ payload: [String: String]) async -> Bool {
        guard let taskId = payload["id"],
              var task = try? Database.shared.getTask(id: taskId) else {
            return false
        }

        if let title = payload["title"] { task.title = title }
        if let notes = payload["notes"] { task.notes = notes }
        if let priorityStr = payload["priority"],
           let priorityInt = Int(priorityStr),
           let priority = TodoTask.Priority(rawValue: priorityInt) {
            task.priority = priority
        }

        do {
            try Database.shared.updateTask(task)
            return true
        } catch {
            print("[ActionExecutor] Failed to update task: \(error)")
            return false
        }
    }

    private func deleteTodoTask(_ payload: [String: String]) async -> Bool {
        guard let taskId = payload["id"] else { return false }
        do {
            try Database.shared.deleteTask(id: taskId)
            return true
        } catch {
            print("[ActionExecutor] Failed to delete task: \(error)")
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
            print("[ActionExecutor] Created goal: \(text)")
            return true
        } catch {
            print("[ActionExecutor] Failed to create goal: \(error)")
            return false
        }
    }

    private func completeGoal(_ payload: [String: String]) async -> Bool {
        guard let goalId = payload["id"] else { return false }
        do {
            try Database.shared.markGoalCompleted(id: goalId)
            return true
        } catch {
            print("[ActionExecutor] Failed to complete goal: \(error)")
            return false
        }
    }

    // MARK: - Calendar Actions

    private func createCalendarEvent(_ payload: [String: String]) async -> Bool {
        let title = payload["title"] ?? "Untitled Event"
        let startStr = payload["start_date"] ?? payload["start"]
        let endStr = payload["end_date"] ?? payload["end"]
        let location = payload["location"]

        guard let startStr, let start = parseDateTime(startStr) else {
            print("[ActionExecutor] Missing or invalid start date for calendar event")
            return false
        }

        let end = endStr.flatMap(parseDateTime) ?? start.addingTimeInterval(3600)

        do {
            try await EventKitManager.shared.createCalendarEvent(
                title: title,
                startDate: start,
                endDate: end,
                notes: location.map { "Location: \($0)" }
            )
            print("[ActionExecutor] Created calendar event: \(title)")
            return true
        } catch {
            print("[ActionExecutor] Failed to create calendar event: \(error)")
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
            print("[ActionExecutor] Created reminder: \(title)")
            return true
        } catch {
            print("[ActionExecutor] Failed to create reminder: \(error)")
            return false
        }
    }

    // MARK: - Email Actions

    private func sendEmail(_ payload: [String: String]) async -> Bool {
        guard let to = payload["to"],
              let subject = payload["subject"],
              let body = payload["body"] else {
            print("[ActionExecutor] Missing required email fields")
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
