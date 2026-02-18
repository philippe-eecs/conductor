import Foundation

// MARK: - Theme CRUD & Day Review

extension MCPToolHandlers {

    func handleGetThemes(_ args: [String: Any]) async -> [String: Any] {
        let includeArchived = args["include_archived"] as? Bool ?? false

        do {
            let themes = try Database.shared.getThemes(includeArchived: includeArchived)

            guard !themes.isEmpty else {
                return mcpSuccess("No themes found. Create themes to group related tasks, goals, and notes.")
            }

            let lines = try themes.map { theme -> String in
                let taskCount = try Database.shared.getTaskCountForTheme(id: theme.id)
                let keywords = try Database.shared.getThemeKeywords(forTheme: theme.id)
                var line = "- \(theme.name) [\(theme.color)]"
                if taskCount > 0 {
                    line += " (\(taskCount) tasks)"
                }
                if let desc = theme.themeDescription {
                    line += " — \(desc)"
                }
                if !keywords.isEmpty {
                    line += "\n  Calendar keywords: \(keywords.joined(separator: ", "))"
                }
                if theme.isArchived {
                    line += " [archived]"
                }
                return line
            }

            return mcpSuccess("Themes (\(themes.count)):\n" + lines.joined(separator: "\n"))
        } catch {
            return mcpError("Failed to get themes: \(error.localizedDescription)")
        }
    }

    func handleCreateTheme(_ args: [String: Any]) async -> [String: Any] {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return mcpError("Missing required field: name")
        }
        let correlationId = (args["correlation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let source = "mcp:conductor_create_theme"

        let color = (args["color"] as? String).flatMap { Self.validThemeColors.contains($0) ? $0 : nil } ?? "blue"
        let description = args["description"] as? String
        let keywords = args["keywords"] as? [String] ?? []

        let theme = Theme(
            id: UUID().uuidString,
            name: name,
            color: color,
            themeDescription: description,
            isArchived: false,
            sortOrder: 0,
            createdAt: Date()
        )

        do {
            try Database.shared.createTheme(theme)

            for keyword in keywords {
                let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try Database.shared.addThemeKeyword(trimmed, toTheme: theme.id)
                }
            }

            var text = "Theme created: \"\(name)\" [\(color)] (ID: \(theme.id))"
            if let description { text += "\nDescription: \(description)" }
            if !keywords.isEmpty { text += "\nKeywords: \(keywords.joined(separator: ", "))" }
            let receipt = OperationLogService.shared.record(
                operation: .created,
                entityType: "theme",
                entityId: theme.id,
                source: source,
                status: .success,
                message: "Created theme '\(name)'",
                payload: ["color": color],
                correlationId: correlationId
            )
            return mcpSuccess(text, data: withReceipt(receipt, extra: ["theme_id": theme.id]))
        } catch {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme",
                source: source,
                status: .failed,
                message: "Failed to create theme '\(name)': \(error.localizedDescription)",
                correlationId: correlationId
            )
            return mcpError("Failed to create theme: \(error.localizedDescription)", data: withReceipt(receipt))
        }
    }

    func handleDeleteTheme(_ args: [String: Any]) async -> [String: Any] {
        let correlationId = (args["correlation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let source = "mcp:conductor_delete_theme"

        let explicitThemeId = (args["theme_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitThemeName = (args["theme_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (explicitThemeId?.isEmpty == false) || (explicitThemeName?.isEmpty == false) else {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme",
                source: source,
                status: .failed,
                message: "Missing required field: theme_id or theme_name",
                correlationId: correlationId
            )
            return mcpError("Missing required field: theme_id or theme_name", data: withReceipt(receipt))
        }

        let mode = (args["mode"] as? String)?.lowercased() ?? "archive"
        let force = args["force"] as? Bool ?? false

        let theme: Theme?
        if let explicitThemeId, !explicitThemeId.isEmpty {
            theme = (try? Database.shared.getTheme(id: explicitThemeId)) ?? nil
        } else if let explicitThemeName, !explicitThemeName.isEmpty {
            let allThemes = (try? Database.shared.getThemes(includeArchived: true)) ?? []
            theme = allThemes.first { $0.name.caseInsensitiveCompare(explicitThemeName) == .orderedSame }
        } else {
            theme = nil
        }

        guard let theme else {
            let requested = explicitThemeId ?? explicitThemeName ?? "unknown"
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme",
                entityId: requested,
                source: source,
                status: .failed,
                message: "Theme not found: \(requested)",
                correlationId: correlationId
            )
            return mcpError("Theme not found: \(requested)", data: withReceipt(receipt))
        }

        if theme.isLooseBucket {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme",
                entityId: theme.id,
                source: source,
                status: .failed,
                message: "Cannot remove the Loose theme.",
                correlationId: correlationId
            )
            return mcpError("Cannot remove the Loose theme.", data: withReceipt(receipt))
        }

        let taskCount = (try? Database.shared.getTaskCountForTheme(id: theme.id)) ?? 0

        switch mode {
        case "archive":
            do {
                try Database.shared.archiveTheme(id: theme.id)
                let receipt = OperationLogService.shared.record(
                    operation: .updated,
                    entityType: "theme",
                    entityId: theme.id,
                    source: source,
                    status: .success,
                    message: "Archived theme '\(theme.name)'",
                    payload: ["mode": mode, "task_count": String(taskCount)],
                    correlationId: correlationId
                )
                return mcpSuccess(
                    "Archived theme '\(theme.name)' (ID: \(theme.id)).",
                    data: withReceipt(receipt, extra: ["theme_id": theme.id, "theme_name": theme.name, "mode": mode])
                )
            } catch {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme",
                    entityId: theme.id,
                    source: source,
                    status: .failed,
                    message: "Failed to archive theme '\(theme.name)': \(error.localizedDescription)",
                    correlationId: correlationId
                )
                return mcpError("Failed to archive theme '\(theme.name)': \(error.localizedDescription)", data: withReceipt(receipt))
            }

        case "delete":
            if taskCount > 0 && !force {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme",
                    entityId: theme.id,
                    source: source,
                    status: .failed,
                    message: "Theme '\(theme.name)' still has \(taskCount) linked task(s). Re-run with force=true or use mode=archive.",
                    correlationId: correlationId
                )
                return mcpError(
                    "Theme '\(theme.name)' has \(taskCount) linked task(s). Use mode=archive or mode=delete with force=true.",
                    data: withReceipt(receipt, extra: ["task_count": taskCount])
                )
            }

            do {
                try Database.shared.deleteTheme(id: theme.id)
                let receipt = OperationLogService.shared.record(
                    operation: .deleted,
                    entityType: "theme",
                    entityId: theme.id,
                    source: source,
                    status: .success,
                    message: "Deleted theme '\(theme.name)'",
                    payload: ["mode": mode, "task_count": String(taskCount), "forced": force ? "true" : "false"],
                    correlationId: correlationId
                )
                return mcpSuccess(
                    "Deleted theme '\(theme.name)' (ID: \(theme.id)).",
                    data: withReceipt(receipt, extra: ["theme_id": theme.id, "theme_name": theme.name, "mode": mode, "forced": force])
                )
            } catch {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme",
                    entityId: theme.id,
                    source: source,
                    status: .failed,
                    message: "Failed to delete theme '\(theme.name)': \(error.localizedDescription)",
                    correlationId: correlationId
                )
                return mcpError("Failed to delete theme '\(theme.name)': \(error.localizedDescription)", data: withReceipt(receipt))
            }

        default:
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme",
                entityId: theme.id,
                source: source,
                status: .failed,
                message: "Invalid mode: \(mode). Use 'archive' or 'delete'.",
                correlationId: correlationId
            )
            return mcpError("Invalid mode: \(mode). Use 'archive' or 'delete'.", data: withReceipt(receipt))
        }
    }

    func handleGetDayReview(_ args: [String: Any]) async -> [String: Any] {
        let date = (args["date"] as? String).flatMap(parseDate) ?? Date()
        let snapshot = await DayReviewService.shared.buildSnapshot(for: date)

        var lines: [String] = []
        lines.append("Day review for \(SharedDateFormatters.fullDate.string(from: date))")
        lines.append("")

        lines.append("Today:")
        if snapshot.todayEvents.isEmpty {
            lines.append("- No calendar events")
        } else {
            for event in snapshot.todayEvents.prefix(6) {
                lines.append("- \(event.time): \(event.title) (\(event.duration))")
            }
        }

        if let activeTheme = snapshot.activeTheme {
            lines.append("- Active theme: \(activeTheme.name)")
            if let objective = activeTheme.objective, !objective.isEmpty {
                lines.append("  Objective: \(objective)")
            }
        }

        lines.append("")
        lines.append("Theme workload:")
        if snapshot.todayThemeBuckets.isEmpty {
            lines.append("- No theme-linked tasks due today")
        } else {
            for bucket in snapshot.todayThemeBuckets.prefix(5) {
                let topTasks = bucket.tasks.prefix(3).map(\.title).joined(separator: ", ")
                lines.append("- \(bucket.theme.name): \(bucket.tasks.count) task(s)" + (topTasks.isEmpty ? "" : " — \(topTasks)"))
            }
        }
        if !snapshot.looseTasks.isEmpty {
            lines.append("- Loose tasks: \(snapshot.looseTasks.count)")
        }

        lines.append("")
        lines.append("This week:")
        if snapshot.weekSummaries.isEmpty {
            lines.append("- No major due work identified")
        } else {
            for summary in snapshot.weekSummaries.prefix(6) {
                lines.append("- \(summary.themeName): \(summary.openCount) open, \(summary.highPriorityCount) high priority")
            }
        }

        lines.append("")
        lines.append("Important emails:")
        if snapshot.actionNeededEmails.isEmpty {
            lines.append("- No action-needed emails")
        } else {
            for email in snapshot.actionNeededEmails.prefix(5) {
                lines.append("- \(email.sender): \(email.subject)")
            }
        }

        let snapshotData: [String: Any] = [
            "date_iso": isoDateTime(snapshot.date),
            "today_events": snapshot.todayEvents.map { event in
                [
                    "id": event.id,
                    "title": event.title,
                    "time": event.time,
                    "duration": event.duration
                ]
            },
            "active_theme": snapshot.activeTheme.map { theme in
                [
                    "id": theme.id,
                    "name": theme.name,
                    "objective": theme.objective ?? ""
                ]
            } ?? NSNull(),
            "week_summaries": snapshot.weekSummaries.map { summary in
                [
                    "id": summary.id,
                    "theme_name": summary.themeName,
                    "open_count": summary.openCount,
                    "high_priority_count": summary.highPriorityCount
                ]
            },
            "loose_task_count": snapshot.looseTasks.count,
            "action_needed_emails": snapshot.actionNeededEmails.map { email in
                [
                    "id": email.id,
                    "sender": email.sender,
                    "subject": email.subject
                ]
            }
        ]

        return mcpSuccess(lines.joined(separator: "\n"), data: ["snapshot": snapshotData])
    }

    func handleGetOperationEvents(_ args: [String: Any]) async -> [String: Any] {
        let limit = min(max(args["limit"] as? Int ?? 25, 1), 100)
        let status = (args["status"] as? String).flatMap(OperationStatus.init(rawValue:))
        let correlationId = args["correlation_id"] as? String

        let events = (try? Database.shared.getOperationEvents(
            limit: limit,
            status: status,
            correlationId: correlationId
        )) ?? []

        guard !events.isEmpty else {
            return mcpSuccess("No operation events found.")
        }

        let lines = events.map { event in
            var line = "- [\(event.status.rawValue)] \(event.operation.rawValue) \(event.entityType)"
            if let entityId = event.entityId {
                line += " (\(entityId))"
            }
            line += " @ \(event.formattedTime)"
            return line
        }

        return mcpSuccess(
            "Operation events (\(events.count)):\n" + lines.joined(separator: "\n"),
            data: [
                "events": events.map(operationEventDict(from:))
            ]
        )
    }
}
