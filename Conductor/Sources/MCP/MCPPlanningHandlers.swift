import Foundation

// MARK: - Day/Week Planning & Theme Blocks

extension MCPToolHandlers {

    func handlePlanDay(_ args: [String: Any]) async -> [String: Any] {
        let date = (args["date"] as? String).flatMap(parseDate) ?? Date()
        let draft = await PlanningDraftService.shared.planDay(for: date)

        guard !draft.proposals.isEmpty else {
            return mcpSuccess(
                "No draft blocks suggested for \(SharedDateFormatters.fullDate.string(from: date)).",
                data: [
                    "draft_id": draft.id,
                    "date_iso": isoDateTime(draft.date),
                    "proposals": [[String: Any]]()
                ]
            )
        }

        var lines: [String] = []
        lines.append("Draft day plan created.")
        lines.append("draft_id: \(draft.id)")
        lines.append("date: \(SharedDateFormatters.fullDate.string(from: draft.date))")
        lines.append("proposals:")
        for proposal in draft.proposals {
            let start = SharedDateFormatters.time12Hour.string(from: proposal.startTime)
            let end = SharedDateFormatters.time12Hour.string(from: proposal.endTime)
            lines.append("- \(proposal.theme.name): \(start)-\(end) (\(proposal.taskIds.count) task refs)")
            lines.append("  proposal_id: \(proposal.id)")
            lines.append("  start_iso: \(isoDateTime(proposal.startTime))")
            lines.append("  end_iso: \(isoDateTime(proposal.endTime))")
        }
        lines.append("Use conductor_apply_plan_blocks with draft_id to save blocks. Set publish=true to also add them to the calendar.")
        let proposalData: [[String: Any]] = draft.proposals.map { proposal in
            [
                "proposal_id": proposal.id,
                "theme_id": proposal.theme.id,
                "theme_name": proposal.theme.name,
                "start_iso": isoDateTime(proposal.startTime),
                "end_iso": isoDateTime(proposal.endTime),
                "task_ids": proposal.taskIds,
                "rationale": proposal.rationale
            ]
        }

        return mcpSuccess(
            lines.joined(separator: "\n"),
            data: [
                "draft_id": draft.id,
                "date_iso": isoDateTime(draft.date),
                "proposals": proposalData
            ]
        )
    }

    func handlePlanWeek(_ args: [String: Any]) async -> [String: Any] {
        let startDate = (args["start_date"] as? String).flatMap(parseDate) ?? Date()
        let weekDraft = await PlanningDraftService.shared.planWeek(startingOn: startDate)

        var lines: [String] = []
        lines.append("Draft week plan created.")
        lines.append("week_id: \(weekDraft.id)")
        lines.append("start_date: \(SharedDateFormatters.fullDate.string(from: weekDraft.startDate))")
        lines.append("daily drafts:")

        var totalProposals = 0
        for daily in weekDraft.dailyDrafts {
            totalProposals += daily.proposals.count
            lines.append("- \(SharedDateFormatters.fullDate.string(from: daily.date)): draft_id=\(daily.id), proposals=\(daily.proposals.count)")
        }
        lines.append("total proposals: \(totalProposals)")
        lines.append("Use conductor_apply_plan_blocks with any draft_id to save blocks.")

        return mcpSuccess(lines.joined(separator: "\n"))
    }

    func handleApplyPlanBlocks(_ args: [String: Any]) async -> [String: Any] {
        guard let draftId = args["draft_id"] as? String, !draftId.isEmpty else {
            return mcpError("Missing required field: draft_id")
        }
        let correlationId = (args["correlation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let source = "mcp:conductor_apply_plan_blocks"

        let status = (args["status"] as? String).flatMap(ThemeBlock.Status.init(rawValue:)) ?? .planned
        let themeName = (args["theme_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let providedStartTime = args["start_time"] as? String
        let providedEndTime = args["end_time"] as? String

        var overrides: [String: (Date, Date)] = [:]

        if providedStartTime != nil || providedEndTime != nil {
            guard let startRaw = providedStartTime, let endRaw = providedEndTime else {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme_block",
                    source: source,
                    status: .failed,
                    message: "Both start_time and end_time are required when overriding block time.",
                    correlationId: correlationId
                )
                return mcpError("Both start_time and end_time are required when overriding block time.", data: withReceipt(receipt))
            }

            guard let start = parseDateTime(startRaw), let end = parseDateTime(endRaw), end > start else {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme_block",
                    source: source,
                    status: .failed,
                    message: "Invalid start_time/end_time. Use ISO 8601 datetimes with end_time after start_time.",
                    correlationId: correlationId
                )
                return mcpError(
                    "Invalid start_time/end_time. Use ISO 8601 datetimes with end_time after start_time.",
                    data: withReceipt(receipt)
                )
            }

            let now = Date()
            let calendar = Calendar.current
            let minimumStart = TemporalContext.roundedMinimumStart(from: now)
            if start < now {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme_block",
                    source: source,
                    status: .failed,
                    message: "Cannot apply override in the past. start_time=\(startRaw)",
                    correlationId: correlationId
                )
                return mcpError("Cannot apply override in the past. Choose a future start_time.", data: withReceipt(receipt))
            }
            if calendar.isDateInToday(start), start < minimumStart {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme_block",
                    source: source,
                    status: .failed,
                    message: "Override start_time \(startRaw) is earlier than the minimum schedulable start.",
                    correlationId: correlationId
                )
                return mcpError(
                    "start_time is too soon for same-day scheduling. Choose a time at least 15 minutes from now.",
                    data: withReceipt(receipt)
                )
            }

            guard let draft = await PlanningDraftService.shared.getDraft(id: draftId) else {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme_block",
                    source: source,
                    status: .failed,
                    message: "No draft found for id: \(draftId)",
                    correlationId: correlationId
                )
                return mcpError("No draft found for id: \(draftId)", data: withReceipt(receipt))
            }

            let targetProposal: ThemeBlockProposal?
            if let themeName, !themeName.isEmpty {
                targetProposal = draft.proposals.first { $0.theme.name.caseInsensitiveCompare(themeName) == .orderedSame }
            } else if draft.proposals.count == 1 {
                targetProposal = draft.proposals.first
            } else {
                targetProposal = nil
            }

            guard let targetProposal else {
                let guidance = draft.proposals.isEmpty
                    ? "Draft has no proposals."
                    : "Provide theme_name when a draft has multiple proposals."
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme_block",
                    source: source,
                    status: .failed,
                    message: "Unable to resolve block override target. \(guidance)",
                    correlationId: correlationId
                )
                return mcpError("Unable to resolve override target. \(guidance)", data: withReceipt(receipt))
            }

            overrides[targetProposal.id] = (start, end)
        }

        do {
            let blocks = try await PlanningDraftService.shared.applyDraft(
                id: draftId,
                status: status,
                overrides: overrides
            )
            guard !blocks.isEmpty else {
                let receipt = OperationLogService.shared.record(
                    operation: .failed,
                    entityType: "theme_block",
                    source: source,
                    status: .failed,
                    message: "No draft found for id: \(draftId)",
                    correlationId: correlationId
                )
                return mcpError("No draft found for id: \(draftId)", data: withReceipt(receipt))
            }

            let ids = blocks.map(\.id).joined(separator: ", ")
            let publish = args["publish"] as? Bool ?? false

            var publishInfo = ""
            var extraData: [String: Any] = ["block_ids": blocks.map(\.id)]

            if publish {
                let publishResult = await PlanningDraftService.shared.publishThemeBlocks(blocks.map(\.id))
                publishInfo = "\nPublished \(publishResult.publishedBlockIds.count) block(s) to calendar."
                if !publishResult.failedBlockIds.isEmpty {
                    publishInfo += " \(publishResult.failedBlockIds.count) failed to publish."
                }
                extraData["published_ids"] = publishResult.publishedBlockIds
                extraData["failed_publish_ids"] = publishResult.failedBlockIds
            }

            let receipt = OperationLogService.shared.record(
                operation: .created,
                entityType: "theme_block",
                source: source,
                status: .success,
                message: "Applied \(blocks.count) block(s) from draft \(draftId)" + (overrides.isEmpty ? "" : " with custom time override") + (publish ? " and published" : ""),
                payload: ["status": status.rawValue, "block_ids": ids],
                correlationId: correlationId
            )
            return mcpSuccess(
                "Applied \(blocks.count) block(s) from draft \(draftId) with status=\(status.rawValue).\nblock_ids: \(ids)" + publishInfo,
                data: withReceipt(receipt, extra: extraData)
            )
        } catch {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme_block",
                source: source,
                status: .failed,
                message: "Failed to apply draft \(draftId): \(error.localizedDescription)",
                correlationId: correlationId
            )
            return mcpError("Failed to apply draft \(draftId): \(error.localizedDescription)", data: withReceipt(receipt))
        }
    }

    func handleCreateThemeBlock(_ args: [String: Any]) async -> [String: Any] {
        let correlationId = (args["correlation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let source = "mcp:conductor_create_theme_block"

        guard let themeId = args["theme_id"] as? String, !themeId.isEmpty else {
            return mcpError("Missing required field: theme_id")
        }
        guard let startRaw = args["start_time"] as? String, !startRaw.isEmpty else {
            return mcpError("Missing required field: start_time")
        }
        guard let endRaw = args["end_time"] as? String, !endRaw.isEmpty else {
            return mcpError("Missing required field: end_time")
        }
        let publish = args["publish"] as? Bool ?? false

        guard let theme = try? Database.shared.getTheme(id: themeId) else {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme_block",
                source: source,
                status: .failed,
                message: "Theme not found: \(themeId)",
                correlationId: correlationId
            )
            return mcpError("Theme not found: \(themeId)", data: withReceipt(receipt))
        }

        guard let start = parseDateTime(startRaw), let end = parseDateTime(endRaw), end > start else {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme_block",
                source: source,
                status: .failed,
                message: "Invalid start_time/end_time. Use ISO 8601 datetimes with end_time after start_time.",
                correlationId: correlationId
            )
            return mcpError("Invalid start_time/end_time. Use ISO 8601 datetimes with end_time after start_time.", data: withReceipt(receipt))
        }

        let now = Date()
        let calendar = Calendar.current
        if start < now {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme_block",
                source: source,
                status: .failed,
                message: "Cannot create block in the past. start_time=\(startRaw)",
                correlationId: correlationId
            )
            return mcpError("Cannot create block in the past. Choose a future start_time.", data: withReceipt(receipt))
        }
        let minimumStart = TemporalContext.roundedMinimumStart(from: now)
        if calendar.isDateInToday(start), start < minimumStart {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme_block",
                source: source,
                status: .failed,
                message: "start_time \(startRaw) is earlier than the minimum schedulable start.",
                correlationId: correlationId
            )
            return mcpError("start_time is too soon for same-day scheduling. Choose a time at least 15 minutes from now.", data: withReceipt(receipt))
        }

        let blockStatus: ThemeBlock.Status = publish ? .published : .planned
        var block = ThemeBlock(
            themeId: themeId,
            startTime: start,
            endTime: end,
            status: blockStatus
        )

        do {
            try Database.shared.createThemeBlock(block)
        } catch {
            let receipt = OperationLogService.shared.record(
                operation: .failed,
                entityType: "theme_block",
                source: source,
                status: .failed,
                message: "Failed to create block: \(error.localizedDescription)",
                correlationId: correlationId
            )
            return mcpError("Failed to create block: \(error.localizedDescription)", data: withReceipt(receipt))
        }

        var calendarEventId: String?
        if publish {
            do {
                let eventId = try await EventKitManager.shared.createCalendarEvent(
                    title: "Focus: \(theme.name)",
                    startDate: start,
                    endDate: end,
                    notes: theme.objective
                )
                block.calendarEventId = eventId
                block.status = .published
                block.updatedAt = Date()
                try Database.shared.updateThemeBlock(block)
                calendarEventId = eventId
            } catch {
                block.status = .planned
                block.updatedAt = Date()
                try? Database.shared.updateThemeBlock(block)

                let receipt = OperationLogService.shared.record(
                    operation: .created,
                    entityType: "theme_block",
                    entityId: block.id,
                    source: source,
                    status: .partialSuccess,
                    message: "Block created but calendar publish failed: \(error.localizedDescription)",
                    correlationId: correlationId
                )
                return mcpSuccess(
                    "Block created (id: \(block.id)) but calendar publish failed: \(error.localizedDescription). Block status set to planned.",
                    data: withReceipt(receipt, extra: ["block_id": block.id])
                )
            }
        }

        var resultLines = ["Created theme block."]
        resultLines.append("block_id: \(block.id)")
        resultLines.append("theme: \(theme.name)")
        resultLines.append("start: \(isoDateTime(start))")
        resultLines.append("end: \(isoDateTime(end))")
        resultLines.append("status: \(block.status.rawValue)")
        if let calendarEventId {
            resultLines.append("calendar_event_id: \(calendarEventId)")
        }

        let receipt = OperationLogService.shared.record(
            operation: .created,
            entityType: "theme_block",
            entityId: block.id,
            source: source,
            status: .success,
            message: "Created block for \(theme.name) (\(isoDateTime(start)) – \(isoDateTime(end)))" + (publish ? " and published to calendar" : ""),
            correlationId: correlationId
        )

        var extraData: [String: Any] = ["block_id": block.id]
        if let calendarEventId {
            extraData["calendar_event_id"] = calendarEventId
        }

        return mcpSuccess(
            resultLines.joined(separator: "\n"),
            data: withReceipt(receipt, extra: extraData)
        )
    }

    func handlePublishPlanBlocks(_ args: [String: Any]) async -> [String: Any] {
        let correlationId = (args["correlation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let source = "mcp:conductor_publish_plan_blocks"
        let providedBlockIds = args["block_ids"] as? [String]
        let blockIds: [String]

        if let providedBlockIds, !providedBlockIds.isEmpty {
            blockIds = providedBlockIds
        } else {
            blockIds = (((try? Database.shared.getThemeBlocksForDay(Date())) ?? [])
                .filter { $0.status == .planned }
                .map(\.id))
        }

        guard !blockIds.isEmpty else {
            return mcpSuccess("No planned blocks to publish.")
        }

        let result = await PlanningDraftService.shared.publishThemeBlocks(blockIds)
        var lines: [String] = []
        lines.append("Publish result:")
        lines.append("- published: \(result.publishedBlockIds.count)")
        lines.append("- failed: \(result.failedBlockIds.count)")
        if !result.publishedBlockIds.isEmpty {
            lines.append("- published_ids: \(result.publishedBlockIds.joined(separator: ", "))")
        }
        if !result.failedBlockIds.isEmpty {
            lines.append("- failed_ids: \(result.failedBlockIds.joined(separator: ", "))")
        }

        let opStatus: OperationStatus = result.failedBlockIds.isEmpty ? .success : .partialSuccess
        let receipt = OperationLogService.shared.record(
            operation: .published,
            entityType: "theme_block",
            source: source,
            status: opStatus,
            message: "Published \(result.publishedBlockIds.count) block(s); failed \(result.failedBlockIds.count).",
            payload: [
                "published_ids": result.publishedBlockIds.joined(separator: ","),
                "failed_ids": result.failedBlockIds.joined(separator: ",")
            ],
            correlationId: correlationId
        )
        return mcpSuccess(
            lines.joined(separator: "\n"),
            data: withReceipt(
                receipt,
                extra: [
                    "published_ids": result.publishedBlockIds,
                    "failed_ids": result.failedBlockIds
                ]
            )
        )
    }
}
