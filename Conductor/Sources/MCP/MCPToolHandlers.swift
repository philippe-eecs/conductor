import Foundation

/// Implements MCP tool handlers that call EventKit and Database directly.
/// Checks DB preferences before each tool call (server-side gating).
///
/// Handler implementations are in extension files:
///   - MCPCalendarHandlers.swift  (calendar, reminders, goals, notes, emails)
///   - MCPTaskHandlers.swift      (todo tasks, agent tasks, assign theme)
///   - MCPThemeHandlers.swift     (theme CRUD, day review, operation events)
///   - MCPPlanningHandlers.swift  (plan day/week, apply/publish blocks, create block)
final class MCPToolHandlers: Sendable {

    // MARK: - Safety Limits

    static let maxDateRangeDays = 30
    static let maxItemsPerCall = 50
    static let validThemeColors = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "gray", "indigo", "teal"]

    // MARK: - Tool Definitions

    static func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "conductor_get_calendar",
                "description": "Get calendar events for a date range. Defaults to today if no dates specified.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "start_date": [
                            "type": "string",
                            "description": "Start date in ISO 8601 format (YYYY-MM-DD). Defaults to today."
                        ],
                        "end_date": [
                            "type": "string",
                            "description": "End date in ISO 8601 format (YYYY-MM-DD). Defaults to end of start_date."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_reminders",
                "description": "Get upcoming incomplete reminders.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of reminders to return (default 20, max 50)."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_goals",
                "description": "Get today's goals with completion status and overdue count.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_notes",
                "description": "Get recent notes.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of notes to return (default 5, max 50)."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_emails",
                "description": "Get important/VIP emails from Apple Mail.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "filter": [
                            "type": "string",
                            "description": "Optional filter string to match against sender or subject."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_create_todo_task",
                "description": "Create a TODO task (canonical task record), optionally assigning it to a theme or Loose.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "Task title."
                        ],
                        "notes": [
                            "type": "string",
                            "description": "Optional notes for the task."
                        ],
                        "due_date": [
                            "type": "string",
                            "description": "Optional due date in YYYY-MM-DD or ISO 8601."
                        ],
                        "priority": [
                            "type": "integer",
                            "description": "Task priority: 0 none, 1 low, 2 medium, 3 high."
                        ],
                        "theme_id": [
                            "type": "string",
                            "description": "Optional existing theme ID."
                        ],
                        "theme_name": [
                            "type": "string",
                            "description": "Optional theme name. Use 'Loose' to unassign."
                        ],
                        "create_if_missing": [
                            "type": "boolean",
                            "description": "Create the named theme if it does not exist (default true)."
                        ],
                        "color": [
                            "type": "string",
                            "description": "Optional color if creating a new theme."
                        ]
                    ],
                    "required": ["title"]
                ]
            ],
            [
                "name": "conductor_create_agent_task",
                "description": "Create a background agent task that runs autonomously at a specified time or on a schedule. Use this when the user asks you to remind them, follow up, check on something later, or schedule any recurring action.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Short name for the task (e.g. 'Follow up with John')"
                        ],
                        "prompt": [
                            "type": "string",
                            "description": "The instruction for the agent to execute when the task fires"
                        ],
                        "trigger_type": [
                            "type": "string",
                            "enum": ["time", "recurring", "checkin", "manual"],
                            "description": "When to trigger: 'time' for one-shot at specific time, 'recurring' for repeated, 'checkin' for check-in phases, 'manual' for on-demand"
                        ],
                        "fire_at": [
                            "type": "string",
                            "description": "ISO 8601 datetime for one-shot tasks (e.g. '2025-01-15T14:00:00')"
                        ],
                        "interval_minutes": [
                            "type": "integer",
                            "description": "Repeat interval in minutes for recurring tasks"
                        ],
                        "cron_hour": [
                            "type": "integer",
                            "description": "Hour (0-23) for daily recurring tasks"
                        ],
                        "cron_minute": [
                            "type": "integer",
                            "description": "Minute (0-59) for daily recurring tasks"
                        ],
                        "checkin_phase": [
                            "type": "string",
                            "enum": ["morning", "midmorning", "afternoon", "winddown", "evening"],
                            "description": "Which check-in phase triggers this task"
                        ],
                        "context_needs": [
                            "type": "array",
                            "items": ["type": "string", "enum": ["calendar", "reminders", "goals", "email", "notes", "tasks"]],
                            "description": "What context the agent needs when running"
                        ],
                        "max_runs": [
                            "type": "integer",
                            "description": "Maximum number of times to run (null = unlimited for recurring)"
                        ],
                        "todo_title": [
                            "type": "string",
                            "description": "Optional TODO title (defaults to task name)."
                        ],
                        "notes": [
                            "type": "string",
                            "description": "Optional TODO notes."
                        ],
                        "due_date": [
                            "type": "string",
                            "description": "Optional TODO due date in YYYY-MM-DD or ISO 8601."
                        ],
                        "priority": [
                            "type": "integer",
                            "description": "Optional TODO priority: 0 none, 1 low, 2 medium, 3 high."
                        ],
                        "theme_id": [
                            "type": "string",
                            "description": "Optional existing theme ID for the linked TODO."
                        ],
                        "theme_name": [
                            "type": "string",
                            "description": "Optional theme name for the linked TODO."
                        ],
                        "create_if_missing": [
                            "type": "boolean",
                            "description": "Create theme if theme_name is missing (default true)."
                        ],
                        "color": [
                            "type": "string",
                            "description": "Optional color if creating a new theme."
                        ]
                    ],
                    "required": ["name", "prompt", "trigger_type"]
                ]
            ],
            [
                "name": "conductor_list_agent_tasks",
                "description": "List all agent tasks (background tasks, reminders, scheduled actions).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "status": [
                            "type": "string",
                            "enum": ["active", "paused", "completed", "all"],
                            "description": "Filter by status. Default: 'active'"
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_themes",
                "description": "Get active themes with task counts. Themes group related tasks, goals, and notes.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "include_archived": [
                            "type": "boolean",
                            "description": "Include archived themes (default false)"
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_create_theme",
                "description": "Create a new theme to group related tasks, goals, and notes. Use this when the user wants to organize work around a topic, project, or area of focus.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Theme name (e.g. 'ViTok-v2 arxiv', '3D Vision Class')"
                        ],
                        "color": [
                            "type": "string",
                            "enum": ["red", "orange", "yellow", "green", "blue", "purple", "pink", "gray", "indigo", "teal"],
                            "description": "Theme color (default: blue)"
                        ],
                        "description": [
                            "type": "string",
                            "description": "Optional description of what this theme covers"
                        ],
                        "keywords": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Calendar event keywords for auto-matching events to this theme"
                        ]
                    ],
                    "required": ["name"]
                ]
            ],
            [
                "name": "conductor_delete_theme",
                "description": "Archive or delete a theme/group. Default behavior is archive for safety.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "theme_id": [
                            "type": "string",
                            "description": "Theme ID to remove."
                        ],
                        "theme_name": [
                            "type": "string",
                            "description": "Theme name to remove (case-insensitive exact match)."
                        ],
                        "mode": [
                            "type": "string",
                            "enum": ["archive", "delete"],
                            "description": "archive (default) keeps data hidden; delete permanently removes theme links/blocks."
                        ],
                        "force": [
                            "type": "boolean",
                            "description": "Required for permanent delete when theme still has linked tasks."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_day_review",
                "description": "Get a day review snapshot with today's commitments, theme-linked tasks, week outlook, and important email details.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "date": [
                            "type": "string",
                            "description": "Optional date in YYYY-MM-DD format. Defaults to today."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_get_operation_events",
                "description": "Get durable operation history (created, updated, deleted, assigned, linked, published, failed).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": [
                            "type": "integer",
                            "description": "Maximum events to return (default 25, max 100)."
                        ],
                        "status": [
                            "type": "string",
                            "enum": ["success", "failed", "partial_success"],
                            "description": "Optional status filter."
                        ],
                        "correlation_id": [
                            "type": "string",
                            "description": "Optional correlation ID to fetch related operations."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_assign_task_theme",
                "description": "Assign a task to a theme (or move it to Loose).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": [
                            "type": "string",
                            "description": "Task ID to assign."
                        ],
                        "agent_task_id": [
                            "type": "string",
                            "description": "Agent task ID to resolve through linked TODO."
                        ],
                        "theme_id": [
                            "type": "string",
                            "description": "Existing theme ID."
                        ],
                        "theme_name": [
                            "type": "string",
                            "description": "Theme name (used if theme_id is omitted). Use 'Loose' to unassign."
                        ],
                        "create_if_missing": [
                            "type": "boolean",
                            "description": "Create the named theme if it doesn't exist (default true)."
                        ],
                        "color": [
                            "type": "string",
                            "description": "Optional color when creating a theme."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_plan_day",
                "description": "Generate a theme-first draft day plan with suggested time blocks.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "date": [
                            "type": "string",
                            "description": "Optional date in YYYY-MM-DD format. Defaults to today."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_plan_week",
                "description": "Generate draft plans for the next 7 days.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "start_date": [
                            "type": "string",
                            "description": "Optional week start date in YYYY-MM-DD format. Defaults to today."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_apply_plan_blocks",
                "description": "Apply a generated draft (by draft_id) into stored theme blocks.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "draft_id": [
                            "type": "string",
                            "description": "Draft ID from conductor_plan_day or conductor_plan_week output."
                        ],
                        "status": [
                            "type": "string",
                            "enum": ["draft", "planned", "published"],
                            "description": "Initial block status (default planned)."
                        ],
                        "theme_name": [
                            "type": "string",
                            "description": "Optional theme name whose draft block should be overridden."
                        ],
                        "start_time": [
                            "type": "string",
                            "description": "Optional custom start datetime (ISO 8601). Requires end_time."
                        ],
                        "end_time": [
                            "type": "string",
                            "description": "Optional custom end datetime (ISO 8601). Requires start_time."
                        ],
                        "publish": [
                            "type": "boolean",
                            "description": "If true, also publish applied blocks to calendar (default false)."
                        ]
                    ],
                    "required": ["draft_id"]
                ]
            ],
            [
                "name": "conductor_publish_plan_blocks",
                "description": "Publish planned theme blocks to calendar (writes calendar_event_id).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "block_ids": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Optional block IDs to publish. Defaults to today's planned blocks."
                        ]
                    ],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "conductor_create_theme_block",
                "description": "Create a theme block directly (no draft required). Optionally publish to calendar.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "theme_id": [
                            "type": "string",
                            "description": "ID of the theme."
                        ],
                        "start_time": [
                            "type": "string",
                            "description": "Start datetime in ISO 8601 format."
                        ],
                        "end_time": [
                            "type": "string",
                            "description": "End datetime in ISO 8601 format."
                        ],
                        "publish": [
                            "type": "boolean",
                            "description": "If true, also create a calendar event (default false)."
                        ],
                        "correlation_id": [
                            "type": "string",
                            "description": "Optional correlation ID for operation tracking."
                        ]
                    ],
                    "required": ["theme_id", "start_time", "end_time"]
                ]
            ],
            [
                "name": "conductor_cancel_agent_task",
                "description": "Cancel, pause, or resume an agent task.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": [
                            "type": "string",
                            "description": "ID of the agent task"
                        ],
                        "action": [
                            "type": "string",
                            "enum": ["cancel", "pause", "resume"],
                            "description": "Action to take on the task"
                        ]
                    ],
                    "required": ["task_id", "action"]
                ]
            ]
        ]
    }

    static var allowedToolNames: Set<String> {
        Set(toolDefinitions().compactMap { $0["name"] as? String })
    }

    // MARK: - Tool Dispatch

    func handleToolCall(name: String, arguments: [String: Any]) async -> [String: Any] {
        switch name {
        case "conductor_get_calendar":
            return await handleGetCalendar(arguments)
        case "conductor_get_reminders":
            return await handleGetReminders(arguments)
        case "conductor_get_goals":
            return await handleGetGoals(arguments)
        case "conductor_get_notes":
            return await handleGetNotes(arguments)
        case "conductor_get_emails":
            return await handleGetEmails(arguments)
        case "conductor_create_todo_task":
            return await handleCreateTodoTask(arguments)
        case "conductor_create_agent_task":
            return await handleCreateAgentTask(arguments)
        case "conductor_list_agent_tasks":
            return await handleListAgentTasks(arguments)
        case "conductor_get_themes":
            return await handleGetThemes(arguments)
        case "conductor_create_theme":
            return await handleCreateTheme(arguments)
        case "conductor_delete_theme":
            return await handleDeleteTheme(arguments)
        case "conductor_get_day_review":
            return await handleGetDayReview(arguments)
        case "conductor_get_operation_events":
            return await handleGetOperationEvents(arguments)
        case "conductor_assign_task_theme":
            return await handleAssignTaskTheme(arguments)
        case "conductor_plan_day":
            return await handlePlanDay(arguments)
        case "conductor_plan_week":
            return await handlePlanWeek(arguments)
        case "conductor_apply_plan_blocks":
            return await handleApplyPlanBlocks(arguments)
        case "conductor_publish_plan_blocks":
            return await handlePublishPlanBlocks(arguments)
        case "conductor_create_theme_block":
            return await handleCreateThemeBlock(arguments)
        case "conductor_cancel_agent_task":
            return await handleCancelAgentTask(arguments)
        default:
            return mcpError("Unknown tool: \(name)")
        }
    }

    // MARK: - Shared Types

    struct ReceiptBackedError: Error {
        let message: String
        let receipt: OperationReceipt
    }

    struct ResolvedThemeTarget {
        let themeId: String?
        let themeName: String
        let createdTheme: Theme?
    }

    struct TodoCreationResult {
        let task: TodoTask
        let themeTarget: ResolvedThemeTarget
        let receipt: OperationReceipt
    }

    // MARK: - Helpers

    func createCanonicalTodoTask(
        args: [String: Any],
        defaultTitle: String?,
        correlationId: String,
        source: String
    ) async throws -> TodoCreationResult {
        let providedTitle = (args["title"] as? String) ?? defaultTitle ?? "Untitled Task"
        let title = providedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "todo_task",
                source: source,
                status: .failed,
                message: "Missing required field: title",
                correlationId: correlationId
            )
            throw ReceiptBackedError(message: "Missing required field: title", receipt: receipt)
        }

        let notes = args["notes"] as? String

        var dueDate: Date?
        if let dueDateRaw = args["due_date"] as? String, !dueDateRaw.isEmpty {
            guard let parsed = parseDateTime(dueDateRaw) else {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "todo_task",
                    source: source,
                    status: .failed,
                    message: "Invalid due_date format: \(dueDateRaw)",
                    correlationId: correlationId
                )
                throw ReceiptBackedError(message: "Invalid due_date format: \(dueDateRaw)", receipt: receipt)
            }
            dueDate = parsed
        }

        let rawPriority = args["priority"] as? Int ?? Int(args["priority"] as? String ?? "0") ?? 0
        let clampedPriority = min(max(rawPriority, 0), 3)
        let priority = TodoTask.Priority(rawValue: clampedPriority) ?? .none

        let createIfMissing = args["create_if_missing"] as? Bool ?? true
        let requestedColor = (args["color"] as? String).flatMap { Self.validThemeColors.contains($0) ? $0 : nil } ?? "blue"

        let themeTarget: ResolvedThemeTarget
        do {
            themeTarget = try resolveThemeTarget(
                themeId: args["theme_id"] as? String,
                themeName: args["theme_name"] as? String,
                createIfMissing: createIfMissing,
                color: requestedColor
            )
        } catch {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme",
                source: source,
                status: .failed,
                message: error.localizedDescription,
                correlationId: correlationId
            )
            throw ReceiptBackedError(message: error.localizedDescription, receipt: receipt)
        }

        if let createdTheme = themeTarget.createdTheme {
            _ = OperationLogService.shared.record(
                operation: .created,
                entityType: "theme",
                entityId: createdTheme.id,
                source: source,
                status: .success,
                message: "Created theme '\(createdTheme.name)'",
                payload: ["color": createdTheme.color],
                correlationId: correlationId
            )
        }

        let task = TodoTask(title: title, notes: notes, dueDate: dueDate, priority: priority)
        do {
            try Database.shared.createTask(task)
        } catch {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "todo_task",
                source: source,
                status: .failed,
                message: "Failed to create todo task '\(title)': \(error.localizedDescription)",
                correlationId: correlationId
            )
            throw ReceiptBackedError(message: "Failed to create todo task '\(title)': \(error.localizedDescription)", receipt: receipt)
        }

        await ThemeService.shared.assignTask(task.id, toThemeId: themeTarget.themeId)
        _ = OperationLogService.shared.record(
            operation: .assigned,
            entityType: "todo_task",
            entityId: task.id,
            source: source,
            status: .success,
            message: "Assigned todo task '\(title)' to \(themeTarget.themeName)",
            payload: ["theme_name": themeTarget.themeName, "theme_id": themeTarget.themeId ?? ""],
            correlationId: correlationId
        )

        let createdReceipt = OperationLogService.shared.record(
            operation: .created,
            entityType: "todo_task",
            entityId: task.id,
            source: source,
            status: .success,
            message: "Created todo task '\(title)'",
            payload: ["theme_name": themeTarget.themeName, "theme_id": themeTarget.themeId ?? ""],
            correlationId: correlationId
        )
        return TodoCreationResult(task: task, themeTarget: themeTarget, receipt: createdReceipt)
    }

    func resolveThemeTarget(
        themeId: String?,
        themeName: String?,
        createIfMissing: Bool,
        color: String
    ) throws -> ResolvedThemeTarget {
        if let themeId = themeId?.trimmingCharacters(in: .whitespacesAndNewlines), !themeId.isEmpty {
            guard let theme = (try? Database.shared.getTheme(id: themeId)) ?? nil else {
                throw toolError("Theme not found: \(themeId)")
            }
            return ResolvedThemeTarget(themeId: theme.id, themeName: theme.name, createdTheme: nil)
        }

        if let rawThemeName = themeName {
            let trimmed = rawThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.caseInsensitiveCompare("loose") == .orderedSame {
                return ResolvedThemeTarget(themeId: nil, themeName: "Loose", createdTheme: nil)
            }

            let existingThemes = (try? Database.shared.getThemes(includeArchived: false)) ?? []
            if let existing = existingThemes.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return ResolvedThemeTarget(themeId: existing.id, themeName: existing.name, createdTheme: nil)
            }

            guard createIfMissing else {
                throw toolError("Theme '\(trimmed)' not found and create_if_missing=false.")
            }

            let newTheme = Theme(name: trimmed, color: color, objective: "High-level objective for \(trimmed)")
            do {
                try Database.shared.createTheme(newTheme)
                return ResolvedThemeTarget(themeId: newTheme.id, themeName: newTheme.name, createdTheme: newTheme)
            } catch {
                throw toolError("Failed to create theme '\(trimmed)': \(error.localizedDescription)")
            }
        }

        return ResolvedThemeTarget(themeId: nil, themeName: "Loose", createdTheme: nil)
    }

    func parseDate(_ string: String) -> Date? {
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        if let date = dateOnly.date(from: string) {
            return date
        }
        return SharedDateFormatters.iso8601.date(from: string)
    }

    func parseDateTime(_ string: String) -> Date? {
        if let date = SharedDateFormatters.databaseDate.date(from: string) {
            return date
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }
        if let date = SharedDateFormatters.iso8601.date(from: string) {
            return date
        }
        return nil
    }

    func isoDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    func withReceipt(_ receipt: OperationReceipt, extra: [String: Any] = [:]) -> [String: Any] {
        var payload = receipt.dictionary
        for (key, value) in extra {
            payload[key] = value
        }
        return payload
    }

    func operationEventDict(from event: OperationEvent) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return [
            "id": event.id,
            "correlation_id": event.correlationId,
            "operation": event.operation.rawValue,
            "entity_type": event.entityType,
            "entity_id": event.entityId ?? NSNull(),
            "source": event.source,
            "status": event.status.rawValue,
            "message": event.message,
            "payload": event.payload,
            "created_at": iso.string(from: event.createdAt)
        ]
    }

    func toolError(_ message: String) -> NSError {
        NSError(domain: "MCPToolHandlers", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func mcpSuccess(_ text: String, data: [String: Any] = [:]) -> [String: Any] {
        var response: [String: Any] = [
            "content": [
                ["type": "text", "text": text]
            ],
            "isError": false
        ]
        for (key, value) in data {
            response[key] = value
        }
        return response
    }

    func mcpError(_ message: String, data: [String: Any] = [:]) -> [String: Any] {
        var response: [String: Any] = [
            "content": [
                ["type": "text", "text": message]
            ],
            "isError": true
        ]
        for (key, value) in data {
            response[key] = value
        }
        return response
    }
}
