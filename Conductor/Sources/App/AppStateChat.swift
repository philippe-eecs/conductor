import SwiftUI

// MARK: - Conversation & Message Management

extension AppState {

    func loadConversationHistory() {
        Task {
            let sessionId = self.currentSessionId
            let loadedMessages = await Task.detached(priority: .userInitiated) {
                (try? Database.shared.loadRecentMessages(limit: 50, forSession: sessionId)) ?? []
            }.value
            self.messages = loadedMessages
        }
    }

    func loadSessions() {
        Task {
            let loadedSessions = await Task.detached(priority: .userInitiated) {
                (try? Database.shared.getRecentSessions(limit: 20)) ?? []
            }.value
            self.sessions = loadedSessions
        }
    }

    /// Sends a message to Claude. Context is fetched on-demand via MCP tools.
    func sendMessage(_ content: String) async {
        let detectedIntent = chatCardsV1Enabled ? ChatIntentRouter.detect(content) : .general
        let userMessage = ChatMessage(role: .user, content: content)
        messages.append(userMessage)
        isLoading = true

        // Save user message in background
        let sessionId = currentSessionId
        Task.detached(priority: .utility) {
            try? Database.shared.saveMessage(userMessage, forSession: sessionId)
        }

        // Ensure MCP server is running
        if !MCPServer.shared.isRunning {
            MCPServer.shared.startWithRetry()
        }

        do {
            let chatModel = await Task.detached(priority: .utility) {
                (((try? Database.shared.getPreference(key: "claude_chat_model")) ?? nil) ?? "opus")
            }.value

            let permissionMode = await Task.detached(priority: .utility) {
                (((try? Database.shared.getPreference(key: "claude_permission_mode")) ?? nil) ?? "plan")
            }.value

            let turnResult = try await conversationCore.runTurn(
                content: content,
                history: messages,
                toolsEnabled: toolsEnabled,
                chatModel: chatModel,
                permissionMode: permissionMode
            )

            var assistantMessage = turnResult.assistantMessage
            if chatCardsV1Enabled {
                assistantMessage = await enrichAssistantMessage(
                    assistantMessage,
                    userInput: content,
                    intent: detectedIntent
                )
            }

            messages.append(assistantMessage)

            // Handle parsed actions
            if !turnResult.parsedActions.isEmpty {
                for action in turnResult.parsedActions {
                    let isSafe = ActionExecutor.safeActionTypes.contains(action.type)
                        && !action.requiresUserApproval
                    if isSafe {
                        Task {
                            let _ = await ActionExecutor.shared.execute(action)
                        }
                    } else {
                        pendingActions.append(action)
                        pendingApprovalCount += 1
                    }
                }
            }

            isLoading = false

            // Speak response if voice is enabled
            SpeechManager.shared.speak(assistantMessage.content)

            // Update session ID if we got one
            if let newSessionId = turnResult.sessionId {
                currentSessionId = newSessionId
            }

            // Log tool calls to activity
            if let toolCalls = assistantMessage.toolCalls {
                for tool in toolCalls {
                    var toolMeta: [String: String] = ["Tool": tool.displayName]
                    if let input = tool.input { toolMeta["Input"] = String(input.prefix(200)) }
                    logActivity(.context, "Tool called: \(tool.displayName)", metadata: toolMeta)
                }
            }

            // Persist session metadata and cost
            let sessionToPersist = currentSessionId
            let title = turnResult.title
            let costToLog = turnResult.totalCost
            await Task.detached(priority: .utility) {
                if let sid = sessionToPersist {
                    try? Database.shared.saveSession(id: sid, title: title)
                    try? Database.shared.associateOrphanedMessages(withSession: sid)
                }
                if let cost = costToLog {
                    try? Database.shared.logCost(amount: cost, sessionId: sessionToPersist)
                }
            }.value

            loadCostData()
            loadSessions()

            // Log the interaction
            var logMetadata: [String: String] = [:]
            if let cost = costToLog {
                logMetadata["Cost"] = String(format: "$%.4f", cost)
            }
            if let model = turnResult.model {
                logMetadata["Model"] = model
            }
            logActivity(.ai, "Response generated", metadata: logMetadata)

            // Save assistant message in background
            let finalSessionId = currentSessionId
            Task.detached(priority: .utility) {
                try? Database.shared.saveMessage(assistantMessage, forSession: finalSessionId)
            }

        } catch {
            let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
            messages.append(errorMessage)
            isLoading = false
            logActivity(.error, "Request failed: \(error.localizedDescription)")
        }
    }

    func handleChatButtonAction(messageId: UUID, action: ChatButtonAction) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        var message = messages[index]

        switch action {
        case .refreshNowContext:
            upsertNowContext(on: &message)
            messages[index] = message
            persistMessage(message)

        case .generateDaySlots:
            let element = await buildSlotPickerElement(for: Date(), selectedSlotId: message.interactionState?.selectedSlotId)
            upsert(element: element, on: &message)
            messages[index] = message
            persistMessage(message)

        case .selectSlot(let slotId):
            guard let slot = findSlot(in: message, slotId: slotId) else { return }
            let correlationId = UUID().uuidString

            var payload: [String: String] = [
                "title": "Focus Block",
                "start_date": slot.startISO,
                "end_date": slot.endISO,
                "correlation_id": correlationId
            ]
            if let activeTheme = ThemeService.shared.activeTheme() {
                payload["theme_id"] = activeTheme.id
                payload["theme_name"] = activeTheme.name
                payload["title"] = "Focus: \(activeTheme.name)"
            }

            let actionRequest = AssistantActionRequest(
                type: .createCalendarEvent,
                title: "Schedule \(slot.label)",
                requiresUserApproval: true,
                payload: payload
            )

            pendingActions.append(actionRequest)
            pendingApprovalCount += 1

            message.interactionState = ChatInteractionState(
                selectedSlotId: slotId,
                pendingCorrelationId: correlationId,
                statusLabel: "Pending approval"
            )
            updateSelectedSlot(slotId: slotId, on: &message)
            messages[index] = message
            persistMessage(message)

        case .approveScheduleDraft:
            guard let correlationId = message.interactionState?.pendingCorrelationId,
                  let pending = pendingActions.first(where: { $0.payload?["correlation_id"] == correlationId }) else {
                return
            }
            approveAction(pending)

        case .rejectScheduleDraft:
            guard let correlationId = message.interactionState?.pendingCorrelationId,
                  let pending = pendingActions.first(where: { $0.payload?["correlation_id"] == correlationId }) else {
                return
            }
            rejectAction(pending)

        case .organizeTodayDraft:
            let element = await buildSlotPickerElement(for: Date(), selectedSlotId: nil)
            let response = ChatMessage(
                role: .assistant,
                content: "Here are some suggested time slots for today.",
                uiElements: [element]
            )
            messages.append(response)
            persistMessage(response)
            SpeechManager.shared.speak(response.content)

        case .openDayReview:
            NotificationCenter.default.post(name: .showDayReview, object: nil)

        case .viewThemeInSidebar(let themeId):
            NotificationCenter.default.post(
                name: .showThemeInTasks,
                object: nil,
                userInfo: ["themeId": themeId]
            )

        case .completeTask(let taskId):
            Task.detached(priority: .utility) {
                try? Database.shared.toggleTaskCompleted(id: taskId)
            }

        case .confirmProposal(let draftId, let proposalId):
            await handleConfirmProposal(messageIndex: index, message: &message, draftId: draftId, proposalId: proposalId)
            messages[index] = message
            persistMessage(message)

        case .skipProposal(let draftId, let proposalId):
            updateProposalStatus(on: &message, draftId: draftId, proposalId: proposalId, status: .skipped)
            messages[index] = message
            persistMessage(message)

        case .editProposalTime(let draftId, let proposalId, let newStartISO, let newEndISO):
            updateProposalTime(on: &message, draftId: draftId, proposalId: proposalId, startISO: newStartISO, endISO: newEndISO)
            messages[index] = message
            persistMessage(message)

        case .updateProposalNotes(let draftId, let proposalId, let notes):
            updateProposalNotes(on: &message, draftId: draftId, proposalId: proposalId, notes: notes)
            messages[index] = message
            persistMessage(message)

        case .confirmAllProposals(let draftId):
            await handleConfirmAllProposals(messageIndex: index, message: &message, draftId: draftId)
            messages[index] = message
            persistMessage(message)

        case .openProposalPopover(let draftId):
            showProposalPopoverDraftId = draftId

        case .selectCalendarBlock(let proposalId):
            message.interactionState = message.interactionState ?? ChatInteractionState()
            message.interactionState?.highlightedProposalId = proposalId
            messages[index] = message
        }
    }

    func clearHistory() {
        messages = []
        Task {
            await conversationCore.startNewConversation()
        }
        let sessionId = currentSessionId
        currentSessionId = nil
        Task.detached(priority: .utility) {
            try? Database.shared.clearMessages(forSession: sessionId)
        }
        logActivity(.system, "History cleared")
    }

    func startNewConversation() {
        messages = []
        Task {
            await conversationCore.startNewConversation()
        }
        currentSessionId = nil
        logActivity(.system, "New conversation started")
    }

    func resumeSession(_ session: Session) {
        currentSessionId = session.id
        Task {
            await conversationCore.resumeSession(session.id)
        }
        loadConversationHistory()
        logActivity(.system, "Resumed session: \(session.title)")
    }

    func deleteSession(_ session: Session) {
        let sessionId = session.id
        Task.detached(priority: .utility) {
            try? Database.shared.deleteSession(id: sessionId)
        }
        loadSessions()

        if currentSessionId == session.id {
            startNewConversation()
        }
    }

    // MARK: - Chat UI Enrichment

    func enrichAssistantMessage(
        _ message: ChatMessage,
        userInput: String,
        intent: ChatIntentRouter.Intent
    ) async -> ChatMessage {
        var updated = message
        var elements: [ChatUIElement] = [buildNowContextElement()]

        switch intent {
        case .dayReview:
            let snapshot = await DayReviewService.shared.buildSnapshot()
            elements.append(.daySnapshot(buildDaySnapshotData(snapshot)))
            elements.append(.weekSummary(buildWeekSummaryData(snapshot)))
        case .scheduleExactTime:
            elements.append(await buildSlotPickerElement(for: Date(), selectedSlotId: nil))
        case .organizeToday:
            let snapshot = await DayReviewService.shared.buildSnapshot()
            elements.append(.daySnapshot(buildDaySnapshotData(snapshot)))
            elements.append(await buildSlotPickerElement(for: Date(), selectedSlotId: nil))
        case .planDay:
            let draft = await PlanningDraftService.shared.planDay(for: Date())
            if !draft.proposals.isEmpty {
                elements.append(await buildCompactWeekCalendarElement(for: Date(), proposals: draft.proposals, draftId: draft.id))
                elements.append(await buildBlockProposalElement(from: draft))
            }
        case .themeAssignment:
            if userInput.lowercased().contains("theme") {
                let snapshot = await DayReviewService.shared.buildSnapshot()
                elements.append(.daySnapshot(buildDaySnapshotData(snapshot)))
            }
        case .general:
            break
        }

        // Scan for theme mentions and add detail cards
        let themeCards = await buildThemeDetailCards(from: message.content)
        elements.append(contentsOf: themeCards)

        updated.uiElements = elements
        return updated
    }

    func buildThemeDetailCards(from text: String) async -> [ChatUIElement] {
        let themes = await Task.detached(priority: .utility) {
            (try? Database.shared.getThemes()) ?? []
        }.value

        var cards: [ChatUIElement] = []
        for theme in themes where theme.name.count > 2 && !theme.isLooseBucket {
            guard text.localizedCaseInsensitiveContains(theme.name) else { continue }

            let tasks = ThemeService.shared.tasksForTheme(theme.id, includeCompleted: true)
            let blocks = await Task.detached(priority: .utility) {
                (try? Database.shared.getThemeBlocksForTheme(id: theme.id)) ?? []
            }.value

            let openTasks = tasks.filter { !$0.isCompleted }
            let completedTasks = tasks.filter { $0.isCompleted }

            let taskLines = openTasks.prefix(5).map { task in
                ThemeDetailCardData.TaskLine(
                    id: task.id,
                    title: task.title,
                    priority: task.priority.rawValue,
                    dueLabel: task.dueDateLabel,
                    isCompleted: task.isCompleted
                )
            }

            let blockLines = blocks.prefix(3).map { block in
                let formatter = SharedDateFormatters.time12Hour
                let label = "\(SharedDateFormatters.shortDayDate.string(from: block.startTime)) \(formatter.string(from: block.startTime))–\(formatter.string(from: block.endTime))"
                return ThemeDetailCardData.BlockLine(
                    id: block.id,
                    label: label,
                    isRecurring: block.isRecurring
                )
            }

            let card = ThemeDetailCardData(
                themeId: theme.id,
                themeName: theme.name,
                themeColor: theme.color,
                objective: theme.objective,
                tasks: taskLines,
                upcomingBlocks: blockLines,
                openTaskCount: openTasks.count,
                completedTaskCount: completedTasks.count
            )
            cards.append(.themeDetail(card))

            if cards.count >= 3 { break }
        }
        return cards
    }

    func buildNowContextElement() -> ChatUIElement {
        let temporal = TemporalContext.current()
        let dateLabel = SharedDateFormatters.fullDateNoYear.string(from: temporal.now)
        let timeLabel = SharedDateFormatters.time12Hour.string(from: temporal.now)
        let earliest = SharedDateFormatters.time12Hour.string(from: temporal.minimumSchedulableStart)
        let timezoneLabel = "\(temporal.timezoneId) (\(temporal.timezoneAbbrev))"

        return .nowContext(
            NowContextCardData(
                dateLabel: dateLabel,
                timeLabel: timeLabel,
                timezoneLabel: timezoneLabel,
                earliestStartLabel: earliest,
                buttons: [
                    ChatActionButton(title: "Refresh", style: .secondary, action: .refreshNowContext),
                    ChatActionButton(title: "Find Slots", style: .primary, action: .generateDaySlots, isDisabled: !isCalendarConnected),
                    ChatActionButton(title: "Day Review", style: .secondary, action: .openDayReview)
                ]
            )
        )
    }

    func buildDaySnapshotData(_ snapshot: DayReviewSnapshot) -> DaySnapshotCardData {
        DaySnapshotCardData(
            title: "Day Snapshot",
            activeThemeName: snapshot.activeTheme?.name,
            activeThemeObjective: snapshot.activeTheme?.objective,
            openThemeTaskCount: snapshot.todayThemeBuckets.reduce(0) { $0 + $1.tasks.count },
            looseTaskCount: snapshot.looseTasks.count,
            events: snapshot.todayEvents.prefix(5).map { event in
                DaySnapshotCardData.EventLine(
                    id: event.id,
                    time: event.time,
                    title: event.title,
                    duration: event.duration
                )
            },
            buttons: [
                ChatActionButton(title: "Organize Today", style: .primary, action: .organizeTodayDraft),
                ChatActionButton(title: "Open Day Review", style: .secondary, action: .openDayReview)
            ]
        )
    }

    func buildWeekSummaryData(_ snapshot: DayReviewSnapshot) -> WeekSummaryCardData {
        WeekSummaryCardData(
            title: "This Week",
            items: snapshot.weekSummaries.map { summary in
                WeekSummaryCardData.SummaryItem(
                    id: summary.id,
                    themeName: summary.themeName,
                    openCount: summary.openCount,
                    highPriorityCount: summary.highPriorityCount
                )
            }
        )
    }

    func buildSlotPickerElement(
        for date: Date,
        selectedSlotId: String?
    ) async -> ChatUIElement {
        let slots = await SlotSuggestionService.shared.suggestSlots(
            for: date,
            durationMinutes: 30,
            maxCount: 5,
            themeId: ThemeService.shared.activeTheme()?.id
        )

        let slotViews = slots.map { slot in
            SlotPickerCardData.SlotViewData(
                id: slot.id,
                startISO: SharedDateFormatters.iso8601DateTime.string(from: slot.start),
                endISO: SharedDateFormatters.iso8601DateTime.string(from: slot.end),
                label: "\(SharedDateFormatters.time12Hour.string(from: slot.start))-\(SharedDateFormatters.time12Hour.string(from: slot.end))",
                reason: slot.reason,
                isSelected: slot.id == selectedSlotId,
                isDisabled: !isCalendarConnected
            )
        }

        let hint: String?
        if !isCalendarConnected {
            hint = "Calendar is disconnected. Connect Calendar Full Access and enable read in Settings."
        } else if slotViews.isEmpty {
            hint = "No open slots found in the rest of today."
        } else {
            hint = nil
        }

        let data = SlotPickerCardData(
            title: "Suggested Time Slots",
            subtitle: "All options are future-valid and at least 15 minutes from now.",
            connectionHint: hint,
            slots: slotViews,
            buttons: [
                ChatActionButton(title: "Refresh Slots", style: .secondary, action: .generateDaySlots),
                ChatActionButton(title: "Day Review", style: .secondary, action: .openDayReview)
            ]
        )
        return .slotPicker(data)
    }

    // MARK: - Message UI Helpers

    func upsertNowContext(on message: inout ChatMessage) {
        upsert(element: buildNowContextElement(), on: &message)
    }

    func upsert(element: ChatUIElement, on message: inout ChatMessage) {
        func sameKind(_ lhs: ChatUIElement, _ rhs: ChatUIElement) -> Bool {
            switch (lhs, rhs) {
            case (.nowContext, .nowContext),
                 (.daySnapshot, .daySnapshot),
                 (.slotPicker, .slotPicker),
                 (.operationReceipt, .operationReceipt),
                 (.weekSummary, .weekSummary),
                 (.themeDetail, .themeDetail),
                 (.blockProposal, .blockProposal),
                 (.compactWeekCalendar, .compactWeekCalendar):
                return true
            default:
                return false
            }
        }

        if let idx = message.uiElements.firstIndex(where: { sameKind($0, element) }) {
            message.uiElements[idx] = element
        } else {
            message.uiElements.append(element)
        }
    }

    func updateSelectedSlot(slotId: String, on message: inout ChatMessage) {
        message.uiElements = message.uiElements.map { element in
            guard case .slotPicker(let data) = element else { return element }
            let updatedSlots = data.slots.map { slot in
                SlotPickerCardData.SlotViewData(
                    id: slot.id,
                    startISO: slot.startISO,
                    endISO: slot.endISO,
                    label: slot.label,
                    reason: slot.reason,
                    isSelected: slot.id == slotId,
                    isDisabled: slot.isDisabled
                )
            }
            return .slotPicker(
                SlotPickerCardData(
                    title: data.title,
                    subtitle: data.subtitle,
                    connectionHint: data.connectionHint,
                    slots: updatedSlots,
                    buttons: data.buttons
                )
            )
        }
    }

    func findSlot(in message: ChatMessage, slotId: String) -> SlotPickerCardData.SlotViewData? {
        for element in message.uiElements {
            guard case .slotPicker(let data) = element else { continue }
            if let slot = data.slots.first(where: { $0.id == slotId }) {
                return slot
            }
        }
        return nil
    }

    func persistMessage(_ message: ChatMessage) {
        let sessionId = currentSessionId
        Task.detached(priority: .utility) {
            try? Database.shared.saveMessage(message, forSession: sessionId)
        }
    }

    func appendOperationReceiptMessage(
        correlationId: String,
        fallbackStatus: OperationStatus,
        fallbackMessage: String
    ) async {
        let event = await Task.detached(priority: .utility) {
            (try? Database.shared.getOperationEvents(limit: 1, status: nil, correlationId: correlationId).first) ?? nil
        }.value

        let card: OperationReceiptCardData
        if let event {
            card = OperationReceiptCardData(
                operationId: event.id,
                correlationId: event.correlationId,
                entityType: event.entityType,
                entityId: event.entityId,
                status: event.status,
                message: event.message,
                timestampLabel: SharedDateFormatters.shortTime.string(from: event.createdAt)
            )
        } else {
            card = OperationReceiptCardData(
                operationId: UUID().uuidString,
                correlationId: correlationId,
                entityType: "action",
                entityId: nil,
                status: fallbackStatus,
                message: fallbackMessage,
                timestampLabel: SharedDateFormatters.shortTime.string(from: Date())
            )
        }

        let message = ChatMessage(
            role: .assistant,
            content: "",
            uiElements: [.operationReceipt(card)]
        )
        messages.append(message)
        persistMessage(message)
    }

    // MARK: - Block Proposal Builders

    func buildBlockProposalElement(from draft: PlanningDraft) async -> ChatUIElement {
        let dateLabel = SharedDateFormatters.fullDateNoYear.string(from: draft.date)

        var proposalViews: [BlockProposalCardData.ProposalViewData] = []
        for proposal in draft.proposals {
            let tasks = ThemeService.shared.tasksForTheme(proposal.theme.id)
            let matchingTasks = tasks.filter { proposal.taskIds.contains($0.id) }
            let taskTitles = Array(matchingTasks.prefix(3).map(\.title))

            proposalViews.append(BlockProposalCardData.ProposalViewData(
                id: proposal.id,
                themeId: proposal.theme.id,
                themeName: proposal.theme.name,
                themeColor: proposal.theme.color,
                startISO: SharedDateFormatters.iso8601DateTime.string(from: proposal.startTime),
                endISO: SharedDateFormatters.iso8601DateTime.string(from: proposal.endTime),
                startLabel: SharedDateFormatters.time12Hour.string(from: proposal.startTime),
                endLabel: SharedDateFormatters.time12Hour.string(from: proposal.endTime),
                durationMinutes: Int(proposal.endTime.timeIntervalSince(proposal.startTime) / 60),
                taskTitles: taskTitles,
                rationale: proposal.rationale,
                status: .pending
            ))
        }

        let data = BlockProposalCardData(
            draftId: draft.id,
            dateLabel: dateLabel,
            rationale: draft.rationale,
            proposals: proposalViews,
            buttons: [
                ChatActionButton(title: "Confirm All", style: .primary, action: .confirmAllProposals(draftId: draft.id)),
                ChatActionButton(title: "Open Full View", style: .secondary, action: .openProposalPopover(draftId: draft.id))
            ]
        )
        return .blockProposal(data)
    }

    func buildCompactWeekCalendarElement(
        for date: Date,
        proposals: [ThemeBlockProposal],
        draftId: String
    ) async -> ChatUIElement {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return .compactWeekCalendar(CompactWeekCalendarData(
                weekStartISO: SharedDateFormatters.iso8601DateTime.string(from: date),
                draftId: draftId,
                days: []
            ))
        }

        let weekEvents = await EventKitManager.shared.getEvents(from: weekInterval.start, to: weekInterval.end)

        var dayColumns: [CompactWeekCalendarData.DayColumn] = []
        for offset in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) else { continue }
            let dayStart = calendar.startOfDay(for: dayDate)
            let dayISO = SharedDateFormatters.databaseDate.string(from: dayDate)

            let dayEvents = weekEvents.filter { calendar.isDate($0.startDate, inSameDayAs: dayDate) }
            let eventSlots = dayEvents.map { event in
                let startMinute = calendar.component(.hour, from: event.startDate) * 60 + calendar.component(.minute, from: event.startDate)
                let duration = max(15, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
                return CompactWeekCalendarData.EventSlot(
                    id: event.id,
                    title: event.title,
                    startMinuteOfDay: startMinute,
                    durationMinutes: duration
                )
            }

            let dayProposals = proposals.filter { calendar.isDate($0.startTime, inSameDayAs: dayDate) }
            let proposedSlots = dayProposals.map { proposal in
                let startMinute = calendar.component(.hour, from: proposal.startTime) * 60 + calendar.component(.minute, from: proposal.startTime)
                let duration = Int(proposal.endTime.timeIntervalSince(proposal.startTime) / 60)
                return CompactWeekCalendarData.ProposedBlockSlot(
                    id: proposal.id,
                    themeName: proposal.theme.name,
                    themeColor: proposal.theme.color,
                    startMinuteOfDay: startMinute,
                    durationMinutes: duration,
                    status: .pending
                )
            }

            let dayLabel = "\(SharedDateFormatters.shortDayOfWeek.string(from: dayDate)) \(SharedDateFormatters.dayNumber.string(from: dayDate))"

            dayColumns.append(CompactWeekCalendarData.DayColumn(
                id: dayISO,
                dayLabel: dayLabel,
                isToday: calendar.isDateInToday(dayDate),
                events: eventSlots,
                proposedBlocks: proposedSlots
            ))
        }

        let data = CompactWeekCalendarData(
            weekStartISO: SharedDateFormatters.iso8601DateTime.string(from: weekInterval.start),
            draftId: draftId,
            days: dayColumns
        )
        return .compactWeekCalendar(data)
    }

    // MARK: - Block Proposal Action Handlers

    private func handleConfirmProposal(
        messageIndex: Int,
        message: inout ChatMessage,
        draftId: String,
        proposalId: String
    ) async {
        updateProposalStatus(on: &message, draftId: draftId, proposalId: proposalId, status: .confirmed)

        // Find proposal data and create ThemeBlock
        if let draft = PlanningDraftService.shared.getDraft(id: draftId),
           let proposal = draft.proposals.first(where: { $0.id == proposalId }) {
            let overrides = message.interactionState?.timeOverrides?[proposalId]
            var startTime = proposal.startTime
            var endTime = proposal.endTime
            if let overrides {
                startTime = SharedDateFormatters.iso8601DateTime.date(from: overrides.startISO) ?? startTime
                endTime = SharedDateFormatters.iso8601DateTime.date(from: overrides.endISO) ?? endTime
            }
            let block = ThemeBlock(themeId: proposal.theme.id, startTime: startTime, endTime: endTime, status: .planned)
            try? Database.shared.createThemeBlock(block)
        }
    }

    private func handleConfirmAllProposals(
        messageIndex: Int,
        message: inout ChatMessage,
        draftId: String
    ) async {
        guard let draft = PlanningDraftService.shared.getDraft(id: draftId) else { return }

        var overrides: [String: (Date, Date)] = [:]
        if let timeOverrides = message.interactionState?.timeOverrides {
            for (proposalId, override) in timeOverrides {
                if let start = SharedDateFormatters.iso8601DateTime.date(from: override.startISO),
                   let end = SharedDateFormatters.iso8601DateTime.date(from: override.endISO) {
                    overrides[proposalId] = (start, end)
                }
            }
        }

        // Apply only non-skipped proposals
        let skippedIds = findSkippedProposalIds(in: message, draftId: draftId)
        let filteredDraft = PlanningDraft(
            id: draft.id,
            date: draft.date,
            proposals: draft.proposals.filter { !skippedIds.contains($0.id) },
            createdAt: draft.createdAt,
            rationale: draft.rationale
        )

        let _ = try? PlanningDraftService.shared.applyDraft(filteredDraft, status: .planned, overrides: overrides)

        // Mark all non-skipped as confirmed
        message.uiElements = message.uiElements.map { element in
            guard case .blockProposal(var data) = element, data.draftId == draftId else { return element }
            data.proposals = data.proposals.map { proposal in
                var p = proposal
                if p.status != .skipped {
                    p.status = .confirmed
                }
                return p
            }
            return .blockProposal(data)
        }

        // Update calendar visual too
        updateCalendarVisualStatuses(on: &message, draftId: draftId)
    }

    private func updateProposalStatus(
        on message: inout ChatMessage,
        draftId: String,
        proposalId: String,
        status: BlockProposalCardData.ProposalStatus
    ) {
        message.uiElements = message.uiElements.map { element in
            guard case .blockProposal(var data) = element, data.draftId == draftId else { return element }
            data.proposals = data.proposals.map { proposal in
                var p = proposal
                if p.id == proposalId { p.status = status }
                return p
            }
            return .blockProposal(data)
        }
        updateCalendarVisualStatuses(on: &message, draftId: draftId)
    }

    private func updateProposalTime(
        on message: inout ChatMessage,
        draftId: String,
        proposalId: String,
        startISO: String,
        endISO: String
    ) {
        // Store override in interaction state
        var state = message.interactionState ?? ChatInteractionState()
        var overrides = state.timeOverrides ?? [:]
        overrides[proposalId] = TimeOverride(startISO: startISO, endISO: endISO)
        state.timeOverrides = overrides
        message.interactionState = state

        // Update the visual labels
        let startLabel = SharedDateFormatters.iso8601DateTime.date(from: startISO)
            .map { SharedDateFormatters.time12Hour.string(from: $0) } ?? startISO
        let endLabel = SharedDateFormatters.iso8601DateTime.date(from: endISO)
            .map { SharedDateFormatters.time12Hour.string(from: $0) } ?? endISO

        message.uiElements = message.uiElements.map { element in
            guard case .blockProposal(var data) = element, data.draftId == draftId else { return element }
            data.proposals = data.proposals.map { proposal in
                var p = proposal
                if p.id == proposalId {
                    p.startISO = startISO
                    p.endISO = endISO
                    p.startLabel = startLabel
                    p.endLabel = endLabel
                    p.status = .edited
                }
                return p
            }
            return .blockProposal(data)
        }

        // Update calendar visual positions
        updateCalendarVisualForEditedProposal(on: &message, draftId: draftId, proposalId: proposalId, startISO: startISO, endISO: endISO)
    }

    private func updateProposalNotes(
        on message: inout ChatMessage,
        draftId: String,
        proposalId: String,
        notes: String
    ) {
        message.uiElements = message.uiElements.map { element in
            guard case .blockProposal(var data) = element, data.draftId == draftId else { return element }
            data.proposals = data.proposals.map { proposal in
                var p = proposal
                if p.id == proposalId { p.notes = notes }
                return p
            }
            return .blockProposal(data)
        }
    }

    private func updateCalendarVisualStatuses(on message: inout ChatMessage, draftId: String) {
        // Find current proposal statuses
        var statusMap: [String: BlockProposalCardData.ProposalStatus] = [:]
        for element in message.uiElements {
            guard case .blockProposal(let data) = element, data.draftId == draftId else { continue }
            for proposal in data.proposals {
                statusMap[proposal.id] = proposal.status
            }
        }

        message.uiElements = message.uiElements.map { element in
            guard case .compactWeekCalendar(var calData) = element, calData.draftId == draftId else { return element }
            calData = CompactWeekCalendarData(
                weekStartISO: calData.weekStartISO,
                draftId: calData.draftId,
                days: calData.days.map { day in
                    CompactWeekCalendarData.DayColumn(
                        id: day.id,
                        dayLabel: day.dayLabel,
                        isToday: day.isToday,
                        events: day.events,
                        proposedBlocks: day.proposedBlocks.map { block in
                            CompactWeekCalendarData.ProposedBlockSlot(
                                id: block.id,
                                themeName: block.themeName,
                                themeColor: block.themeColor,
                                startMinuteOfDay: block.startMinuteOfDay,
                                durationMinutes: block.durationMinutes,
                                status: statusMap[block.id] ?? block.status
                            )
                        }
                    )
                }
            )
            return .compactWeekCalendar(calData)
        }
    }

    private func updateCalendarVisualForEditedProposal(
        on message: inout ChatMessage,
        draftId: String,
        proposalId: String,
        startISO: String,
        endISO: String
    ) {
        guard let startDate = SharedDateFormatters.iso8601DateTime.date(from: startISO),
              let endDate = SharedDateFormatters.iso8601DateTime.date(from: endISO) else { return }
        let calendar = Calendar.current
        let newStartMinute = calendar.component(.hour, from: startDate) * 60 + calendar.component(.minute, from: startDate)
        let newDuration = Int(endDate.timeIntervalSince(startDate) / 60)

        message.uiElements = message.uiElements.map { element in
            guard case .compactWeekCalendar(var calData) = element, calData.draftId == draftId else { return element }
            calData = CompactWeekCalendarData(
                weekStartISO: calData.weekStartISO,
                draftId: calData.draftId,
                days: calData.days.map { day in
                    CompactWeekCalendarData.DayColumn(
                        id: day.id,
                        dayLabel: day.dayLabel,
                        isToday: day.isToday,
                        events: day.events,
                        proposedBlocks: day.proposedBlocks.map { block in
                            guard block.id == proposalId else { return block }
                            return CompactWeekCalendarData.ProposedBlockSlot(
                                id: block.id,
                                themeName: block.themeName,
                                themeColor: block.themeColor,
                                startMinuteOfDay: newStartMinute,
                                durationMinutes: newDuration,
                                status: .edited
                            )
                        }
                    )
                }
            )
            return .compactWeekCalendar(calData)
        }
    }

    private func findSkippedProposalIds(in message: ChatMessage, draftId: String) -> Set<String> {
        var skipped: Set<String> = []
        for element in message.uiElements {
            guard case .blockProposal(let data) = element, data.draftId == draftId else { continue }
            for proposal in data.proposals where proposal.status == .skipped {
                skipped.insert(proposal.id)
            }
        }
        return skipped
    }
}
