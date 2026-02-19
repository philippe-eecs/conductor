import Foundation

final class MCPToolHandlers: @unchecked Sendable {

    static let allowedToolNames: Set<String> = [
        "conductor_get_calendar",
        "conductor_get_reminders",
        "conductor_get_recent_emails",
        "conductor_find_contact",
        "conductor_get_projects",
        "conductor_get_todos",
        "conductor_create_todo",
        "conductor_update_todo",
        "conductor_create_project",
        "conductor_create_calendar_block",
        "conductor_update_calendar_event",
        "conductor_delete_calendar_event",
        "conductor_schedule_meeting",
        "conductor_dispatch_agent"
    ]

    static func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "conductor_get_calendar",
                "description": "Get calendar events for a date range. Defaults to today.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (YYYY-MM-DD). Defaults to today."],
                        "end_date": ["type": "string", "description": "End date (YYYY-MM-DD). Defaults to start_date + 1 day."],
                        "days": ["type": "integer", "description": "Number of days from start_date. Alternative to end_date."]
                    ]
                ]
            ],
            [
                "name": "conductor_get_reminders",
                "description": "Get upcoming incomplete reminders from Apple Reminders.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": ["type": "integer", "description": "Max reminders to return (default 20)."]
                    ]
                ]
            ],
            [
                "name": "conductor_get_recent_emails",
                "description": "Get recent emails from Apple Mail.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "hours_back": ["type": "integer", "description": "How far back to fetch (default 24 hours)."]
                    ]
                ]
            ],
            [
                "name": "conductor_find_contact",
                "description": "Find a contact by name and return the best-matching email.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Contact name (required)."]
                    ],
                    "required": ["name"]
                ]
            ],
            [
                "name": "conductor_get_projects",
                "description": "List all projects with open TODO count.",
                "inputSchema": ["type": "object", "properties": [:]]
            ],
            [
                "name": "conductor_get_todos",
                "description": "Get TODOs, optionally filtered by project.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "project_id": ["type": "integer", "description": "Filter by project ID. Omit for inbox or all."],
                        "include_completed": ["type": "boolean", "description": "Include completed TODOs (default false)."]
                    ]
                ]
            ],
            [
                "name": "conductor_create_todo",
                "description": "Create a new TODO item.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "TODO title (required)."],
                        "priority": ["type": "integer", "description": "0=none, 1=low, 2=medium, 3=high"],
                        "due_date": ["type": "string", "description": "Due date (YYYY-MM-DD)"],
                        "project_id": ["type": "integer", "description": "Project ID to assign to"]
                    ],
                    "required": ["title"]
                ]
            ],
            [
                "name": "conductor_update_todo",
                "description": "Update or complete a TODO.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "todo_id": ["type": "integer", "description": "TODO ID (required)"],
                        "title": ["type": "string", "description": "New title"],
                        "priority": ["type": "integer", "description": "New priority"],
                        "completed": ["type": "boolean", "description": "Mark as complete"],
                        "project_id": ["type": "integer", "description": "Move to project"]
                    ],
                    "required": ["todo_id"]
                ]
            ],
            [
                "name": "conductor_create_project",
                "description": "Create a new project.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Project name (required)"],
                        "color": ["type": "string", "description": "Hex color (e.g. #FF5733)"],
                        "description": ["type": "string", "description": "Project description"]
                    ],
                    "required": ["name"]
                ]
            ],
            [
                "name": "conductor_create_calendar_block",
                "description": "Create a calendar event for time blocking.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Event title (required)"],
                        "start_time": ["type": "string", "description": "Start time ISO 8601 (required)"],
                        "end_time": ["type": "string", "description": "End time ISO 8601 (required)"],
                        "notes": ["type": "string", "description": "Event notes"],
                        "location": ["type": "string", "description": "Event location"]
                    ],
                    "required": ["title", "start_time", "end_time"]
                ]
            ],
            [
                "name": "conductor_update_calendar_event",
                "description": "Update or reschedule an existing calendar event.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "event_id": ["type": "string", "description": "Calendar event ID (required)."],
                        "title": ["type": "string", "description": "New event title."],
                        "start_time": ["type": "string", "description": "New start time in ISO 8601."],
                        "end_time": ["type": "string", "description": "New end time in ISO 8601."],
                        "notes": ["type": "string", "description": "Updated event notes."],
                        "location": ["type": "string", "description": "Updated location."]
                    ],
                    "required": ["event_id"]
                ]
            ],
            [
                "name": "conductor_delete_calendar_event",
                "description": "Delete a calendar event by ID.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "event_id": ["type": "string", "description": "Calendar event ID (required)."]
                    ],
                    "required": ["event_id"]
                ]
            ],
            [
                "name": "conductor_schedule_meeting",
                "description": "Schedule a meeting with a contact name or email by finding the first free slot in a constrained window.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "contact_name": ["type": "string", "description": "Contact name to resolve to an email."],
                        "contact_email": ["type": "string", "description": "Contact email if already known."],
                        "window_start": ["type": "string", "description": "Earliest allowed start in ISO 8601 (required)."],
                        "window_end": ["type": "string", "description": "Latest allowed end in ISO 8601 (required)."],
                        "duration_minutes": ["type": "integer", "description": "Meeting duration in minutes (required)."],
                        "title": ["type": "string", "description": "Meeting title (default: Meeting with contact)."],
                        "notes": ["type": "string", "description": "Meeting notes."],
                        "location": ["type": "string", "description": "Meeting location or call link."]
                    ],
                    "required": ["window_start", "window_end", "duration_minutes"]
                ]
            ],
            [
                "name": "conductor_dispatch_agent",
                "description": "Dispatch an AI agent to work on a TODO. The agent runs in the background.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "todo_id": ["type": "integer", "description": "TODO ID to work on (required)"],
                        "prompt": ["type": "string", "description": "Instructions for the agent (required)"]
                    ],
                    "required": ["todo_id", "prompt"]
                ]
            ]
        ]
    }

    func handleToolCall(name: String, arguments: [String: Any]) async -> [String: Any] {
        do {
            switch name {
            case "conductor_get_calendar":
                return try await handleGetCalendar(arguments)
            case "conductor_get_reminders":
                return try await handleGetReminders(arguments)
            case "conductor_get_recent_emails":
                return try await handleGetRecentEmails(arguments)
            case "conductor_find_contact":
                return try await handleFindContact(arguments)
            case "conductor_get_projects":
                return try handleGetProjects(arguments)
            case "conductor_get_todos":
                return try handleGetTodos(arguments)
            case "conductor_create_todo":
                return try handleCreateTodo(arguments)
            case "conductor_update_todo":
                return try handleUpdateTodo(arguments)
            case "conductor_create_project":
                return try handleCreateProject(arguments)
            case "conductor_create_calendar_block":
                return try await handleCreateCalendarBlock(arguments)
            case "conductor_update_calendar_event":
                return try await handleUpdateCalendarEvent(arguments)
            case "conductor_delete_calendar_event":
                return try await handleDeleteCalendarEvent(arguments)
            case "conductor_schedule_meeting":
                return try await handleScheduleMeeting(arguments)
            case "conductor_dispatch_agent":
                return try await handleDispatchAgent(arguments)
            default:
                return errorResult("Unknown tool: \(name)")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    // MARK: - READ Tools

    private func handleGetCalendar(_ args: [String: Any]) async throws -> [String: Any] {
        let calendar = Calendar.current
        let now = Date()

        let startDate: Date
        if let startStr = args["start_date"] as? String,
           let parsed = SharedDateFormatters.databaseDate.date(from: startStr) {
            startDate = parsed
        } else {
            startDate = calendar.startOfDay(for: now)
        }

        let endDate: Date
        if let endStr = args["end_date"] as? String,
           let parsed = SharedDateFormatters.databaseDate.date(from: endStr) {
            endDate = calendar.date(byAdding: .day, value: 1, to: parsed) ?? parsed
        } else if let days = args["days"] as? Int {
            endDate = calendar.date(byAdding: .day, value: days, to: startDate)!
        } else {
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
        }

        let events = await EventKitManager.shared.getEvents(from: startDate, to: endDate)

        let formatted = events.map { event -> [String: Any] in
            var dict: [String: Any] = [
                "id": event.id,
                "title": event.title,
                "start": SharedDateFormatters.fullDateTime.string(from: event.startDate),
                "end": SharedDateFormatters.fullDateTime.string(from: event.endDate),
                "start_iso": iso8601String(event.startDate),
                "end_iso": iso8601String(event.endDate),
                "calendar": event.calendarTitle,
                "calendar_id": event.calendarIdentifier,
                "all_day": event.isAllDay
            ]
            if let location = event.location { dict["location"] = location }
            if let notes = event.notes { dict["notes"] = notes }
            if let externalId = event.externalIdentifier { dict["external_id"] = externalId }
            return dict
        }

        return contentResult(formatted)
    }

    private func handleGetReminders(_ args: [String: Any]) async throws -> [String: Any] {
        let limit = args["limit"] as? Int ?? 20
        let reminders = await EventKitManager.shared.getUpcomingReminders(limit: limit)

        let formatted = reminders.map { reminder -> [String: Any] in
            var dict: [String: Any] = [
                "title": reminder.title,
                "completed": reminder.isCompleted,
                "priority": reminder.priority
            ]
            if let dueDate = reminder.dueDate { dict["due_date"] = dueDate }
            if let notes = reminder.notes { dict["notes"] = notes }
            return dict
        }

        return contentResult(formatted)
    }

    private func handleGetRecentEmails(_ args: [String: Any]) async throws -> [String: Any] {
        let hoursBack = args["hours_back"] as? Int ?? 24
        let emails = await MailService.shared.getRecentEmails(hoursBack: max(hoursBack, 1))

        let formatted = emails.map { email in
            [
                "sender": email.sender,
                "subject": email.subject,
                "received_at": SharedDateFormatters.fullDateTime.string(from: email.receivedDate),
                "received_at_iso": iso8601String(email.receivedDate),
                "is_read": email.isRead,
                "mailbox": email.mailbox
            ]
        }
        return contentResult(formatted)
    }

    private func handleFindContact(_ args: [String: Any]) async throws -> [String: Any] {
        guard let name = args["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return errorResult("name is required")
        }

        if ContactsManager.shared.contactsAuthorizationStatus() == .notDetermined {
            _ = await ContactsManager.shared.requestContactsAccess()
        }
        let contact = try await ContactsManager.shared.findContact(named: name)

        return contentResult([
            "name": contact.fullName,
            "email": contact.email
        ])
    }

    private func handleGetProjects(_ args: [String: Any]) throws -> [String: Any] {
        let repo = ProjectRepository(db: AppDatabase.shared)
        let summaries = try repo.projectSummaries()

        let formatted = summaries.map { summary -> [String: Any] in
            [
                "id": summary.project.id ?? 0,
                "name": summary.project.name,
                "color": summary.project.color,
                "open_todos": summary.openTodoCount,
                "deliverables": summary.totalDeliverables,
                "description": summary.project.description ?? ""
            ]
        }

        return contentResult(formatted)
    }

    private func handleGetTodos(_ args: [String: Any]) throws -> [String: Any] {
        let repo = ProjectRepository(db: AppDatabase.shared)
        let projectId = args["project_id"] as? Int64
        let includeCompleted = args["include_completed"] as? Bool ?? false

        let todos: [Todo]
        if let projectId {
            todos = try repo.todosForProject(projectId)
        } else {
            todos = try repo.allOpenTodos()
        }

        let filtered = includeCompleted ? todos : todos.filter { !$0.completed }

        let formatted = filtered.map { todo -> [String: Any] in
            var dict: [String: Any] = [
                "id": todo.id ?? 0,
                "title": todo.title,
                "priority": todo.priority,
                "completed": todo.completed
            ]
            if let projectId = todo.projectId { dict["project_id"] = projectId }
            if let dueDate = todo.dueDate {
                dict["due_date"] = SharedDateFormatters.databaseDate.string(from: dueDate)
            }
            return dict
        }

        return contentResult(formatted)
    }

    // MARK: - WRITE Tools

    private func handleCreateTodo(_ args: [String: Any]) throws -> [String: Any] {
        guard let title = args["title"] as? String, !title.isEmpty else {
            return errorResult("title is required")
        }

        let repo = ProjectRepository(db: AppDatabase.shared)
        let priority = args["priority"] as? Int ?? 0
        let projectId = args["project_id"] as? Int64

        var dueDate: Date?
        if let dueDateStr = args["due_date"] as? String {
            dueDate = SharedDateFormatters.databaseDate.date(from: dueDateStr)
        }

        let todo = try repo.createTodo(title: title, priority: priority, dueDate: dueDate, projectId: projectId)

        // Resolve project name for display
        var projectName: String?
        if let pid = projectId, let project = try? repo.project(id: pid) {
            projectName = project.name
        }

        notifyProjectsChanged()
        notifyOperationReceipt(OperationReceiptData(
            entityType: "todo", entityName: title, entityId: todo.id, operation: .created,
            priority: priority > 0 ? priority : nil,
            dueDate: dueDate,
            projectName: projectName
        ))

        return contentResult([
            "id": todo.id ?? 0,
            "title": todo.title,
            "status": "created"
        ])
    }

    private func handleUpdateTodo(_ args: [String: Any]) throws -> [String: Any] {
        guard let todoId = args["todo_id"] as? Int64 else {
            return errorResult("todo_id is required")
        }

        let repo = ProjectRepository(db: AppDatabase.shared)
        guard var todo = try repo.todo(id: todoId) else {
            return errorResult("TODO not found with id \(todoId)")
        }

        if let title = args["title"] as? String { todo.title = title }
        if let priority = args["priority"] as? Int { todo.priority = priority }
        if let completed = args["completed"] as? Bool {
            todo.completed = completed
            if completed { todo.completedAt = Date() }
        }
        if let projectId = args["project_id"] as? Int64 { todo.projectId = projectId }

        try repo.updateTodo(todo)

        // Resolve project name for display
        var projectName: String?
        if let pid = todo.projectId, let project = try? repo.project(id: pid) {
            projectName = project.name
        }

        notifyProjectsChanged()

        let op: OperationType = (args["completed"] as? Bool == true) ? .completed : .updated
        notifyOperationReceipt(OperationReceiptData(
            entityType: "todo", entityName: todo.title, entityId: todo.id, operation: op,
            priority: todo.priority > 0 ? todo.priority : nil,
            dueDate: todo.dueDate,
            projectName: projectName
        ))

        return contentResult([
            "id": todo.id ?? 0,
            "title": todo.title,
            "completed": todo.completed,
            "status": "updated"
        ])
    }

    private func handleCreateProject(_ args: [String: Any]) throws -> [String: Any] {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return errorResult("name is required")
        }

        let repo = ProjectRepository(db: AppDatabase.shared)
        let color = args["color"] as? String ?? "#007AFF"
        let description = args["description"] as? String

        let project = try repo.createProject(name: name, color: color, description: description)

        notifyProjectsChanged()
        notifyOperationReceipt(OperationReceiptData(
            entityType: "project", entityName: name, entityId: project.id, operation: .created
        ))

        return contentResult([
            "id": project.id ?? 0,
            "name": project.name,
            "status": "created"
        ])
    }

    private func handleCreateCalendarBlock(_ args: [String: Any]) async throws -> [String: Any] {
        guard let title = args["title"] as? String,
              let startStr = args["start_time"] as? String,
              let endStr = args["end_time"] as? String else {
            return errorResult("title, start_time, and end_time are required")
        }

        guard let startDate = parseISODate(startStr),
              let endDate = parseISODate(endStr) else {
            return errorResult("Invalid date format. Use ISO 8601 (e.g. 2025-01-15T09:00:00-08:00)")
        }

        let notes = args["notes"] as? String
        let location = args["location"] as? String

        let eventId = try await EventKitManager.shared.createCalendarEvent(
            title: title, startDate: startDate, endDate: endDate, notes: notes, location: location
        )

        notifyOperationReceipt(OperationReceiptData(
            entityType: "calendar_event", entityName: title, entityId: nil, operation: .created
        ))

        return contentResult([
            "event_id": eventId,
            "title": title,
            "status": "created"
        ])
    }

    private func handleUpdateCalendarEvent(_ args: [String: Any]) async throws -> [String: Any] {
        guard let eventId = args["event_id"] as? String, !eventId.isEmpty else {
            return errorResult("event_id is required")
        }

        let startDate = (args["start_time"] as? String).flatMap { parseISODate($0) }
        let endDate = (args["end_time"] as? String).flatMap { parseISODate($0) }

        let updated = try await EventKitManager.shared.updateCalendarEvent(
            eventId: eventId,
            title: args["title"] as? String,
            startDate: startDate,
            endDate: endDate,
            notes: args["notes"] as? String,
            location: args["location"] as? String,
            calendarIdentifier: args["calendar_id"] as? String
        )

        notifyOperationReceipt(OperationReceiptData(
            entityType: "calendar_event", entityName: updated.title, entityId: nil, operation: .updated
        ))

        return contentResult([
            "event_id": updated.id,
            "title": updated.title,
            "start_iso": iso8601String(updated.startDate),
            "end_iso": iso8601String(updated.endDate),
            "status": "updated"
        ])
    }

    private func handleDeleteCalendarEvent(_ args: [String: Any]) async throws -> [String: Any] {
        guard let eventId = args["event_id"] as? String, !eventId.isEmpty else {
            return errorResult("event_id is required")
        }

        try await EventKitManager.shared.deleteCalendarEvent(eventId: eventId)

        notifyOperationReceipt(OperationReceiptData(
            entityType: "calendar_event", entityName: "Calendar Event", entityId: nil, operation: .deleted
        ))

        return contentResult([
            "event_id": eventId,
            "status": "deleted"
        ])
    }

    private func handleScheduleMeeting(_ args: [String: Any]) async throws -> [String: Any] {
        guard let windowStartRaw = args["window_start"] as? String,
              let windowEndRaw = args["window_end"] as? String,
              let durationMinutes = args["duration_minutes"] as? Int else {
            return errorResult("window_start, window_end, and duration_minutes are required")
        }

        guard let windowStart = parseISODate(windowStartRaw),
              let windowEnd = parseISODate(windowEndRaw) else {
            return errorResult("window_start and window_end must be ISO 8601")
        }

        guard windowStart < windowEnd else {
            return errorResult("window_end must be after window_start")
        }

        guard durationMinutes > 0 else {
            return errorResult("duration_minutes must be greater than zero")
        }

        let contactName = (args["contact_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var contactEmail = (args["contact_email"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedName = contactName

        if (contactEmail == nil || contactEmail?.isEmpty == true) {
            guard let contactName, !contactName.isEmpty else {
                return errorResult("Provide contact_name or contact_email")
            }

            if ContactsManager.shared.contactsAuthorizationStatus() == .notDetermined {
                _ = await ContactsManager.shared.requestContactsAccess()
            }

            let match = try await ContactsManager.shared.findContact(named: contactName)
            resolvedName = match.fullName
            contactEmail = match.email
        }

        guard let email = contactEmail, !email.isEmpty else {
            return errorResult("Could not resolve contact email")
        }

        guard let slot = await EventKitManager.shared.findFirstAvailableSlot(
            windowStart: windowStart,
            windowEnd: windowEnd,
            durationMinutes: durationMinutes
        ) else {
            return contentResult([
                "status": "no_slot_found",
                "contact_name": resolvedName ?? contactName ?? "",
                "contact_email": email,
                "window_start": iso8601String(windowStart),
                "window_end": iso8601String(windowEnd)
            ])
        }

        let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = resolvedName ?? contactName ?? email
        let meetingTitle = (title?.isEmpty == false) ? title! : "Meeting with \(fallbackName)"
        var notes = args["notes"] as? String ?? ""
        if !notes.isEmpty { notes += "\n\n" }
        notes += "Attendee: \(fallbackName) <\(email)>"
        let location = args["location"] as? String

        let eventId = try await EventKitManager.shared.createCalendarEvent(
            title: meetingTitle,
            startDate: slot.start,
            endDate: slot.end,
            notes: notes,
            location: location
        )

        notifyOperationReceipt(OperationReceiptData(
            entityType: "calendar_event",
            entityName: meetingTitle,
            entityId: nil,
            operation: .created
        ))

        return contentResult([
            "status": "scheduled",
            "event_id": eventId,
            "title": meetingTitle,
            "start_iso": iso8601String(slot.start),
            "end_iso": iso8601String(slot.end),
            "contact_name": fallbackName,
            "contact_email": email
        ])
    }

    private func handleDispatchAgent(_ args: [String: Any]) async throws -> [String: Any] {
        guard let todoId = args["todo_id"] as? Int64,
              let prompt = args["prompt"] as? String, !prompt.isEmpty else {
            return errorResult("todo_id and prompt are required")
        }

        let repo = ProjectRepository(db: AppDatabase.shared)
        guard let todo = try repo.todo(id: todoId) else {
            return errorResult("TODO not found with id \(todoId)")
        }

        // Dispatch agent asynchronously
        let blinkRepo = BlinkRepository(db: AppDatabase.shared)
        let run = try blinkRepo.createAgentRun(todoId: todoId, prompt: prompt)

        Task.detached {
            await AgentDispatcher.shared.execute(runId: run.id!, todoId: todoId, prompt: prompt)
        }

        notifyOperationReceipt(OperationReceiptData(
            entityType: "agent", entityName: "Agent for: \(todo.title)", entityId: run.id, operation: .dispatched
        ))

        return contentResult([
            "agent_run_id": run.id ?? 0,
            "todo": todo.title,
            "status": "dispatched"
        ])
    }

    // MARK: - Helpers

    private func parseISODate(_ raw: String) -> Date? {
        if let parsed = Self.iso8601.date(from: raw) {
            return parsed
        }
        return Self.iso8601Fractional.date(from: raw)
    }

    private func iso8601String(_ date: Date) -> String {
        Self.iso8601.string(from: date)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func contentResult(_ value: Any) -> [String: Any] {
        let jsonString: String
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            jsonString = str
        } else {
            jsonString = String(describing: value)
        }

        return [
            "content": [
                ["type": "text", "text": jsonString]
            ]
        ]
    }

    private func errorResult(_ message: String) -> [String: Any] {
        [
            "content": [
                ["type": "text", "text": "Error: \(message)"]
            ],
            "isError": true
        ]
    }

    private func notifyProjectsChanged() {
        DispatchQueue.main.async {
            AppState.shared.loadProjects()
        }
    }

    private func notifyOperationReceipt(_ receipt: OperationReceiptData) {
        NotificationCenter.default.post(name: .mcpOperationReceipt, object: receipt)
    }
}
