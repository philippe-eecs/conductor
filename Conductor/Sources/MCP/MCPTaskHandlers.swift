import Foundation

// MARK: - TODO Tasks & Agent Tasks

extension MCPToolHandlers {

    func handleCreateTodoTask(_ args: [String: Any]) async -> [String: Any] {
        let correlationId = (args["correlation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let source = "mcp:conductor_create_todo_task"

        do {
            let result = try await createCanonicalTodoTask(
                args: args,
                defaultTitle: nil,
                correlationId: correlationId,
                source: source
            )

            var text = "Todo task created: \"\(result.task.title)\" (ID: \(result.task.id))"
            text += "\nTheme: \(result.themeTarget.themeName)"
            if let dueDate = result.task.dueDate {
                text += "\nDue: \(SharedDateFormatters.fullDate.string(from: dueDate))"
            }

            var payload: [String: Any] = [
                "task_id": result.task.id,
                "theme_name": result.themeTarget.themeName
            ]
            if let themeId = result.themeTarget.themeId {
                payload["theme_id"] = themeId
            }

            return mcpSuccess(text, data: withReceipt(result.receipt, extra: payload))
        } catch let error as ReceiptBackedError {
            return mcpError(error.message, data: withReceipt(error.receipt))
        } catch {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "todo_task",
                source: source,
                status: .failed,
                message: "Failed to create todo task: \(error.localizedDescription)",
                correlationId: correlationId
            )
            return mcpError("Failed to create todo task: \(error.localizedDescription)", data: withReceipt(receipt))
        }
    }

    func handleCreateAgentTask(_ args: [String: Any]) async -> [String: Any] {
        guard let name = args["name"] as? String,
              let prompt = args["prompt"] as? String,
              let triggerTypeStr = args["trigger_type"] as? String,
              let triggerType = AgentTask.TriggerType(rawValue: triggerTypeStr) else {
            return mcpError("Missing required fields: name, prompt, trigger_type")
        }
        let correlationId = (args["correlation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let source = "mcp:conductor_create_agent_task"

        let todoResult: TodoCreationResult
        do {
            todoResult = try await createCanonicalTodoTask(
                args: args,
                defaultTitle: (args["todo_title"] as? String) ?? name,
                correlationId: correlationId,
                source: source
            )
        } catch let error as ReceiptBackedError {
            return mcpError(error.message, data: withReceipt(error.receipt))
        } catch {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "agent_task",
                source: source,
                status: .failed,
                message: "Failed before creating agent task: \(error.localizedDescription)",
                correlationId: correlationId
            )
            return mcpError("Failed before creating agent task: \(error.localizedDescription)", data: withReceipt(receipt))
        }

        var triggerConfig = TriggerConfig()

        if let fireAtStr = args["fire_at"] as? String {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: fireAtStr) {
                triggerConfig.fireAt = date
            } else if let date = SharedDateFormatters.databaseDate.date(from: fireAtStr) {
                triggerConfig.fireAt = date
            }
        }

        if let interval = args["interval_minutes"] as? Int {
            triggerConfig.intervalMinutes = interval
        }
        if let cronHour = args["cron_hour"] as? Int {
            triggerConfig.cronHour = cronHour
        }
        if let cronMinute = args["cron_minute"] as? Int {
            triggerConfig.cronMinute = cronMinute
        }
        if let phase = args["checkin_phase"] as? String {
            triggerConfig.checkinPhase = phase
        }

        let contextNeedStrings = args["context_needs"] as? [String] ?? []
        let contextNeeds = contextNeedStrings.compactMap(AgentContextNeed.init(rawValue:))

        let maxRuns = args["max_runs"] as? Int

        var nextRun: Date?
        switch triggerType {
        case .time:
            nextRun = triggerConfig.fireAt
        case .recurring:
            if let interval = triggerConfig.intervalMinutes {
                nextRun = Date().addingTimeInterval(Double(interval) * 60)
            } else if let hour = triggerConfig.cronHour {
                let minute = triggerConfig.cronMinute ?? 0
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = hour
                components.minute = minute
                if let todayRun = calendar.date(from: components), todayRun > Date() {
                    nextRun = todayRun
                } else if let todayRun = calendar.date(from: components) {
                    nextRun = calendar.date(byAdding: .day, value: 1, to: todayRun)
                }
            }
        case .checkin, .event, .manual:
            nextRun = nil
        }

        let task = AgentTask(
            name: name,
            prompt: prompt,
            triggerType: triggerType,
            triggerConfig: triggerConfig,
            contextNeeds: contextNeeds,
            createdBy: .chat,
            nextRun: nextRun,
            maxRuns: maxRuns,
            linkedTodoTaskId: todoResult.task.id
        )

        do {
            try Database.shared.createAgentTask(task)
            try? Database.shared.recordBehaviorEvent(
                type: .agentTaskCreated,
                entityId: task.id,
                metadata: ["linked_todo_task_id": todoResult.task.id]
            )
            _ = OperationLogService.shared.record(
                operation: .linked,
                entityType: "agent_task",
                entityId: task.id,
                source: source,
                status: .success,
                message: "Linked agent task '\(name)' to todo '\(todoResult.task.title)'",
                payload: ["linked_todo_task_id": todoResult.task.id],
                correlationId: correlationId
            )
            let receipt = OperationLogService.shared.record(
                operation: .created,
                entityType: "agent_task",
                entityId: task.id,
                source: source,
                status: .success,
                message: "Created agent task '\(name)'",
                payload: ["linked_todo_task_id": todoResult.task.id],
                correlationId: correlationId
            )

            var text = "Agent task created: \"\(name)\" (ID: \(task.id))\n"
            text += "Linked TODO: \(todoResult.task.title) (ID: \(todoResult.task.id))\n"
            text += "Trigger: \(triggerTypeStr)"
            if let nextRun {
                text += "\nNext run: \(SharedDateFormatters.fullDateTime.string(from: nextRun))"
            }
            if triggerType == .checkin, let phase = triggerConfig.checkinPhase {
                text += "\nPhase: \(phase)"
            }

            return mcpSuccess(
                text,
                data: withReceipt(
                    receipt,
                    extra: [
                        "agent_task_id": task.id,
                        "linked_todo_task_id": todoResult.task.id,
                        "todo_task_id": todoResult.task.id
                    ]
                )
            )
        } catch {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "agent_task",
                source: source,
                status: .partialSuccess,
                message: "Agent task creation failed but TODO was created (TODO ID: \(todoResult.task.id))",
                payload: [
                    "linked_todo_task_id": todoResult.task.id,
                    "error": error.localizedDescription
                ],
                correlationId: correlationId
            )
            return mcpError(
                "Failed to create agent task after creating linked TODO \(todoResult.task.id): \(error.localizedDescription)",
                data: withReceipt(
                    receipt,
                    extra: [
                        "partial_success": true,
                        "linked_todo_task_id": todoResult.task.id,
                        "todo_task_id": todoResult.task.id
                    ]
                )
            )
        }
    }

    func handleListAgentTasks(_ args: [String: Any]) async -> [String: Any] {
        let statusFilter = args["status"] as? String ?? "active"

        do {
            let tasks: [AgentTask]
            if statusFilter == "all" {
                tasks = try Database.shared.getAllAgentTasks()
            } else {
                tasks = try Database.shared.getActiveAgentTasks()
            }

            guard !tasks.isEmpty else {
                return mcpSuccess("No \(statusFilter) agent tasks found.")
            }

            let lines = tasks.map { task -> String in
                var line = "- [\(task.status.rawValue)] \(task.name) (ID: \(task.id))"
                line += "\n  Trigger: \(task.triggerType.rawValue)"
                if let nextRun = task.nextRun {
                    line += " | Next: \(SharedDateFormatters.fullDateTime.string(from: nextRun))"
                }
                if task.runCount > 0 {
                    line += " | Runs: \(task.runCount)"
                    if let maxRuns = task.maxRuns {
                        line += "/\(maxRuns)"
                    }
                }
                if let linkedTodoTaskId = task.linkedTodoTaskId, !linkedTodoTaskId.isEmpty {
                    line += " | Linked TODO: \(linkedTodoTaskId)"
                }
                return line
            }

            return mcpSuccess("Agent tasks (\(tasks.count)):\n" + lines.joined(separator: "\n"))
        } catch {
            return mcpError("Failed to list agent tasks: \(error.localizedDescription)")
        }
    }

    func handleCancelAgentTask(_ args: [String: Any]) async -> [String: Any] {
        guard let taskId = args["task_id"] as? String,
              let action = args["action"] as? String else {
            return mcpError("Missing required fields: task_id, action")
        }
        let correlationId = (args["correlation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let source = "mcp:conductor_cancel_agent_task"

        do {
            guard var task = try Database.shared.getAgentTask(id: taskId) else {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "agent_task",
                    entityId: taskId,
                    source: source,
                    status: .failed,
                    message: "Agent task not found: \(taskId)",
                    correlationId: correlationId
                )
                return mcpError("Agent task not found: \(taskId)", data: withReceipt(receipt))
            }

            let message: String
            let operation: OperationKind
            switch action {
            case "cancel":
                task.status = .completed
                try Database.shared.updateAgentTask(task)
                operation = .deleted
                message = "Agent task cancelled: \"\(task.name)\""
            case "pause":
                task.status = .paused
                try Database.shared.updateAgentTask(task)
                operation = .updated
                message = "Agent task paused: \"\(task.name)\""
            case "resume":
                task.status = .active
                try Database.shared.updateAgentTask(task)
                operation = .updated
                message = "Agent task resumed: \"\(task.name)\""
            default:
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "agent_task",
                    entityId: taskId,
                    source: source,
                    status: .failed,
                    message: "Invalid action '\(action)' for agent task \(taskId)",
                    correlationId: correlationId
                )
                return mcpError("Invalid action: \(action). Use 'cancel', 'pause', or 'resume'.", data: withReceipt(receipt))
            }

            let receipt = OperationLogService.shared.record(
                operation: operation,
                entityType: "agent_task",
                entityId: task.id,
                source: source,
                status: .success,
                message: message,
                payload: ["action": action],
                correlationId: correlationId
            )
            return mcpSuccess(message, data: withReceipt(receipt, extra: ["agent_task_id": task.id]))
        } catch {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "agent_task",
                entityId: taskId,
                source: source,
                status: .failed,
                message: "Failed to \(action) agent task \(taskId): \(error.localizedDescription)",
                correlationId: correlationId
            )
            return mcpError("Failed to \(action) agent task: \(error.localizedDescription)", data: withReceipt(receipt))
        }
    }

    func handleAssignTaskTheme(_ args: [String: Any]) async -> [String: Any] {
        let correlationId = (args["correlation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let source = "mcp:conductor_assign_task_theme"
        let suppliedTaskId = (args["task_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suppliedAgentTaskId = (args["agent_task_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (suppliedTaskId?.isEmpty == false) || (suppliedAgentTaskId?.isEmpty == false) else {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "todo_task",
                source: source,
                status: .failed,
                message: "Missing required field: task_id or agent_task_id",
                correlationId: correlationId
            )
            return mcpError("Missing required field: task_id or agent_task_id", data: withReceipt(receipt))
        }

        var taskId = suppliedTaskId
        var resolvedAgentTaskId: String?

        if let candidateTaskId = suppliedTaskId, !candidateTaskId.isEmpty {
            if ((try? Database.shared.getTask(id: candidateTaskId)) ?? nil) == nil {
                taskId = nil
            }
        }

        if taskId == nil, let agentTaskId = suppliedAgentTaskId, !agentTaskId.isEmpty {
            guard let agentTask = (try? Database.shared.getAgentTask(id: agentTaskId)) ?? nil else {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "agent_task",
                    entityId: agentTaskId,
                    source: source,
                    status: .failed,
                    message: "Agent task not found: \(agentTaskId)",
                    correlationId: correlationId
                )
                return mcpError("Agent task not found: \(agentTaskId)", data: withReceipt(receipt))
            }
            guard let linkedTodoTaskId = agentTask.linkedTodoTaskId, !linkedTodoTaskId.isEmpty else {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "agent_task",
                    entityId: agentTaskId,
                    source: source,
                    status: .failed,
                    message: "Agent task \(agentTaskId) has no linked TODO. Create one with conductor_create_todo_task and re-link.",
                    correlationId: correlationId
                )
                return mcpError("Agent task \(agentTaskId) has no linked TODO. Create one with conductor_create_todo_task and re-link.", data: withReceipt(receipt))
            }
            guard ((try? Database.shared.getTask(id: linkedTodoTaskId)) ?? nil) != nil else {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "todo_task",
                    entityId: linkedTodoTaskId,
                    source: source,
                    status: .failed,
                    message: "Linked TODO not found for agent task \(agentTaskId): \(linkedTodoTaskId)",
                    correlationId: correlationId
                )
                return mcpError("Linked TODO not found for agent task \(agentTaskId): \(linkedTodoTaskId)", data: withReceipt(receipt))
            }
            taskId = linkedTodoTaskId
            resolvedAgentTaskId = agentTaskId
        }

        guard let taskId, !taskId.isEmpty else {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "todo_task",
                entityId: suppliedTaskId,
                source: source,
                status: .failed,
                message: "Task not found: \(suppliedTaskId ?? "unknown")",
                correlationId: correlationId
            )
            return mcpError("Task not found: \(suppliedTaskId ?? "unknown")", data: withReceipt(receipt))
        }

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
            return mcpError(error.localizedDescription, data: withReceipt(receipt))
        }

        if let createdTheme = themeTarget.createdTheme {
            _ = OperationLogService.shared.record(
                operation: .created,
                entityType: "theme",
                entityId: createdTheme.id,
                source: source,
                status: .success,
                message: "Created theme '\(createdTheme.name)'",
                correlationId: correlationId
            )
        }

        await ThemeService.shared.assignTask(taskId, toThemeId: themeTarget.themeId)

        let receipt = OperationLogService.shared.record(
            operation: .assigned,
            entityType: "todo_task",
            entityId: taskId,
            source: source,
            status: .success,
            message: "Task \(taskId) assigned to theme: \(themeTarget.themeName).",
            payload: [
                "theme_id": themeTarget.themeId ?? "",
                "theme_name": themeTarget.themeName,
                "agent_task_id": resolvedAgentTaskId ?? ""
            ],
            correlationId: correlationId
        )

        var extra: [String: Any] = [
            "task_id": taskId,
            "theme_name": themeTarget.themeName
        ]
        if let themeId = themeTarget.themeId {
            extra["theme_id"] = themeId
        }
        if let resolvedAgentTaskId {
            extra["agent_task_id"] = resolvedAgentTaskId
        }
        return mcpSuccess("Task \(taskId) assigned to theme: \(themeTarget.themeName).", data: withReceipt(receipt, extra: extra))
    }
}
