import Foundation

enum ChatButtonStyle: String, Codable, Equatable {
    case primary
    case secondary
    case destructive
}

enum ChatButtonAction: Equatable {
    case refreshNowContext
    case generateDaySlots
    case selectSlot(slotId: String)
    case approveScheduleDraft
    case rejectScheduleDraft
    case organizeTodayDraft
    case openDayReview
    case viewThemeInSidebar(themeId: String)
    case completeTask(taskId: String)
    case confirmProposal(draftId: String, proposalId: String)
    case skipProposal(draftId: String, proposalId: String)
    case editProposalTime(draftId: String, proposalId: String, newStartISO: String, newEndISO: String)
    case updateProposalNotes(draftId: String, proposalId: String, notes: String)
    case confirmAllProposals(draftId: String)
    case openProposalPopover(draftId: String)
    case selectCalendarBlock(proposalId: String)
}

extension ChatButtonAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case slotId = "slot_id"
        case themeId = "theme_id"
        case taskId = "task_id"
        case draftId = "draft_id"
        case proposalId = "proposal_id"
        case newStartISO = "new_start_iso"
        case newEndISO = "new_end_iso"
        case notes
    }

    private enum ActionType: String, Codable {
        case refreshNowContext = "refresh_now_context"
        case generateDaySlots = "generate_day_slots"
        case selectSlot = "select_slot"
        case approveScheduleDraft = "approve_schedule_draft"
        case rejectScheduleDraft = "reject_schedule_draft"
        case organizeTodayDraft = "organize_today_draft"
        case openDayReview = "open_day_review"
        case viewThemeInSidebar = "view_theme_in_sidebar"
        case completeTask = "complete_task"
        case confirmProposal = "confirm_proposal"
        case skipProposal = "skip_proposal"
        case editProposalTime = "edit_proposal_time"
        case updateProposalNotes = "update_proposal_notes"
        case confirmAllProposals = "confirm_all_proposals"
        case openProposalPopover = "open_proposal_popover"
        case selectCalendarBlock = "select_calendar_block"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .refreshNowContext:
            try container.encode(ActionType.refreshNowContext, forKey: .type)
        case .generateDaySlots:
            try container.encode(ActionType.generateDaySlots, forKey: .type)
        case .selectSlot(let slotId):
            try container.encode(ActionType.selectSlot, forKey: .type)
            try container.encode(slotId, forKey: .slotId)
        case .approveScheduleDraft:
            try container.encode(ActionType.approveScheduleDraft, forKey: .type)
        case .rejectScheduleDraft:
            try container.encode(ActionType.rejectScheduleDraft, forKey: .type)
        case .organizeTodayDraft:
            try container.encode(ActionType.organizeTodayDraft, forKey: .type)
        case .openDayReview:
            try container.encode(ActionType.openDayReview, forKey: .type)
        case .viewThemeInSidebar(let themeId):
            try container.encode(ActionType.viewThemeInSidebar, forKey: .type)
            try container.encode(themeId, forKey: .themeId)
        case .completeTask(let taskId):
            try container.encode(ActionType.completeTask, forKey: .type)
            try container.encode(taskId, forKey: .taskId)
        case .confirmProposal(let draftId, let proposalId):
            try container.encode(ActionType.confirmProposal, forKey: .type)
            try container.encode(draftId, forKey: .draftId)
            try container.encode(proposalId, forKey: .proposalId)
        case .skipProposal(let draftId, let proposalId):
            try container.encode(ActionType.skipProposal, forKey: .type)
            try container.encode(draftId, forKey: .draftId)
            try container.encode(proposalId, forKey: .proposalId)
        case .editProposalTime(let draftId, let proposalId, let newStartISO, let newEndISO):
            try container.encode(ActionType.editProposalTime, forKey: .type)
            try container.encode(draftId, forKey: .draftId)
            try container.encode(proposalId, forKey: .proposalId)
            try container.encode(newStartISO, forKey: .newStartISO)
            try container.encode(newEndISO, forKey: .newEndISO)
        case .updateProposalNotes(let draftId, let proposalId, let notes):
            try container.encode(ActionType.updateProposalNotes, forKey: .type)
            try container.encode(draftId, forKey: .draftId)
            try container.encode(proposalId, forKey: .proposalId)
            try container.encode(notes, forKey: .notes)
        case .confirmAllProposals(let draftId):
            try container.encode(ActionType.confirmAllProposals, forKey: .type)
            try container.encode(draftId, forKey: .draftId)
        case .openProposalPopover(let draftId):
            try container.encode(ActionType.openProposalPopover, forKey: .type)
            try container.encode(draftId, forKey: .draftId)
        case .selectCalendarBlock(let proposalId):
            try container.encode(ActionType.selectCalendarBlock, forKey: .type)
            try container.encode(proposalId, forKey: .proposalId)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        switch type {
        case .refreshNowContext:
            self = .refreshNowContext
        case .generateDaySlots:
            self = .generateDaySlots
        case .selectSlot:
            let slotId = try container.decode(String.self, forKey: .slotId)
            self = .selectSlot(slotId: slotId)
        case .approveScheduleDraft:
            self = .approveScheduleDraft
        case .rejectScheduleDraft:
            self = .rejectScheduleDraft
        case .organizeTodayDraft:
            self = .organizeTodayDraft
        case .openDayReview:
            self = .openDayReview
        case .viewThemeInSidebar:
            let themeId = try container.decode(String.self, forKey: .themeId)
            self = .viewThemeInSidebar(themeId: themeId)
        case .completeTask:
            let taskId = try container.decode(String.self, forKey: .taskId)
            self = .completeTask(taskId: taskId)
        case .confirmProposal:
            let draftId = try container.decode(String.self, forKey: .draftId)
            let proposalId = try container.decode(String.self, forKey: .proposalId)
            self = .confirmProposal(draftId: draftId, proposalId: proposalId)
        case .skipProposal:
            let draftId = try container.decode(String.self, forKey: .draftId)
            let proposalId = try container.decode(String.self, forKey: .proposalId)
            self = .skipProposal(draftId: draftId, proposalId: proposalId)
        case .editProposalTime:
            let draftId = try container.decode(String.self, forKey: .draftId)
            let proposalId = try container.decode(String.self, forKey: .proposalId)
            let newStartISO = try container.decode(String.self, forKey: .newStartISO)
            let newEndISO = try container.decode(String.self, forKey: .newEndISO)
            self = .editProposalTime(draftId: draftId, proposalId: proposalId, newStartISO: newStartISO, newEndISO: newEndISO)
        case .updateProposalNotes:
            let draftId = try container.decode(String.self, forKey: .draftId)
            let proposalId = try container.decode(String.self, forKey: .proposalId)
            let notes = try container.decode(String.self, forKey: .notes)
            self = .updateProposalNotes(draftId: draftId, proposalId: proposalId, notes: notes)
        case .confirmAllProposals:
            let draftId = try container.decode(String.self, forKey: .draftId)
            self = .confirmAllProposals(draftId: draftId)
        case .openProposalPopover:
            let draftId = try container.decode(String.self, forKey: .draftId)
            self = .openProposalPopover(draftId: draftId)
        case .selectCalendarBlock:
            let proposalId = try container.decode(String.self, forKey: .proposalId)
            self = .selectCalendarBlock(proposalId: proposalId)
        }
    }
}

struct ChatActionButton: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let style: ChatButtonStyle
    let action: ChatButtonAction
    let isDisabled: Bool
    let hint: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        style: ChatButtonStyle = .secondary,
        action: ChatButtonAction,
        isDisabled: Bool = false,
        hint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.style = style
        self.action = action
        self.isDisabled = isDisabled
        self.hint = hint
    }
}

struct NowContextCardData: Codable, Equatable {
    let dateLabel: String
    let timeLabel: String
    let timezoneLabel: String
    let earliestStartLabel: String
    let buttons: [ChatActionButton]
}

struct DaySnapshotCardData: Codable, Equatable {
    struct EventLine: Codable, Equatable, Identifiable {
        let id: String
        let time: String
        let title: String
        let duration: String
    }

    let title: String
    let activeThemeName: String?
    let activeThemeObjective: String?
    let openThemeTaskCount: Int
    let looseTaskCount: Int
    let events: [EventLine]
    let buttons: [ChatActionButton]
}

struct SlotPickerCardData: Codable, Equatable {
    struct SlotViewData: Codable, Equatable, Identifiable {
        let id: String
        let startISO: String
        let endISO: String
        let label: String
        let reason: String
        let isSelected: Bool
        let isDisabled: Bool
    }

    let title: String
    let subtitle: String
    let connectionHint: String?
    let slots: [SlotViewData]
    let buttons: [ChatActionButton]
}

struct OperationReceiptCardData: Codable, Equatable {
    let operationId: String
    let correlationId: String
    let entityType: String
    let entityId: String?
    let status: OperationStatus
    let message: String
    let timestampLabel: String
}

struct ThemeDetailCardData: Codable, Equatable {
    let themeId: String
    let themeName: String
    let themeColor: String
    let objective: String?
    let tasks: [TaskLine]
    let upcomingBlocks: [BlockLine]
    let openTaskCount: Int
    let completedTaskCount: Int

    struct TaskLine: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let priority: Int
        let dueLabel: String?
        let isCompleted: Bool
    }

    struct BlockLine: Codable, Equatable, Identifiable {
        let id: String
        let label: String
        let isRecurring: Bool
    }
}

struct WeekSummaryCardData: Codable, Equatable {
    struct SummaryItem: Codable, Equatable, Identifiable {
        let id: String
        let themeName: String
        let openCount: Int
        let highPriorityCount: Int
    }

    let title: String
    let items: [SummaryItem]
}

struct BlockProposalCardData: Codable, Equatable {
    let draftId: String
    let dateLabel: String
    let rationale: String
    var proposals: [ProposalViewData]
    let buttons: [ChatActionButton]

    struct ProposalViewData: Codable, Equatable, Identifiable {
        let id: String
        let themeId: String
        let themeName: String
        let themeColor: String
        var startISO: String
        var endISO: String
        var startLabel: String
        var endLabel: String
        let durationMinutes: Int
        let taskTitles: [String]
        let rationale: String
        var status: ProposalStatus
        var notes: String?
    }

    enum ProposalStatus: String, Codable, Equatable {
        case pending, confirmed, skipped, edited
    }
}

struct CompactWeekCalendarData: Codable, Equatable {
    let weekStartISO: String
    let draftId: String?
    let days: [DayColumn]

    struct DayColumn: Codable, Equatable, Identifiable {
        let id: String
        let dayLabel: String
        let isToday: Bool
        let events: [EventSlot]
        let proposedBlocks: [ProposedBlockSlot]
    }

    struct EventSlot: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let startMinuteOfDay: Int
        let durationMinutes: Int
    }

    struct ProposedBlockSlot: Codable, Equatable, Identifiable {
        let id: String
        let themeName: String
        let themeColor: String
        let startMinuteOfDay: Int
        let durationMinutes: Int
        let status: BlockProposalCardData.ProposalStatus
    }
}

struct TimeOverride: Codable, Equatable {
    let startISO: String
    let endISO: String
}

struct ChatInteractionState: Codable, Equatable {
    var selectedSlotId: String?
    var pendingCorrelationId: String?
    var statusLabel: String?
    var timeOverrides: [String: TimeOverride]?
    var highlightedProposalId: String?
}

enum ChatUIElement: Equatable {
    case nowContext(NowContextCardData)
    case daySnapshot(DaySnapshotCardData)
    case slotPicker(SlotPickerCardData)
    case operationReceipt(OperationReceiptCardData)
    case weekSummary(WeekSummaryCardData)
    case themeDetail(ThemeDetailCardData)
    case blockProposal(BlockProposalCardData)
    case compactWeekCalendar(CompactWeekCalendarData)
}

extension ChatUIElement: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case nowContext
        case daySnapshot
        case slotPicker
        case operationReceipt
        case weekSummary
        case themeDetail
        case blockProposal
        case compactWeekCalendar
    }

    private enum ElementType: String, Codable {
        case nowContext
        case daySnapshot
        case slotPicker
        case operationReceipt
        case weekSummary
        case themeDetail
        case blockProposal
        case compactWeekCalendar
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .nowContext(let data):
            try container.encode(ElementType.nowContext, forKey: .type)
            try container.encode(data, forKey: .nowContext)
        case .daySnapshot(let data):
            try container.encode(ElementType.daySnapshot, forKey: .type)
            try container.encode(data, forKey: .daySnapshot)
        case .slotPicker(let data):
            try container.encode(ElementType.slotPicker, forKey: .type)
            try container.encode(data, forKey: .slotPicker)
        case .operationReceipt(let data):
            try container.encode(ElementType.operationReceipt, forKey: .type)
            try container.encode(data, forKey: .operationReceipt)
        case .weekSummary(let data):
            try container.encode(ElementType.weekSummary, forKey: .type)
            try container.encode(data, forKey: .weekSummary)
        case .themeDetail(let data):
            try container.encode(ElementType.themeDetail, forKey: .type)
            try container.encode(data, forKey: .themeDetail)
        case .blockProposal(let data):
            try container.encode(ElementType.blockProposal, forKey: .type)
            try container.encode(data, forKey: .blockProposal)
        case .compactWeekCalendar(let data):
            try container.encode(ElementType.compactWeekCalendar, forKey: .type)
            try container.encode(data, forKey: .compactWeekCalendar)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ElementType.self, forKey: .type)
        switch type {
        case .nowContext:
            self = .nowContext(try container.decode(NowContextCardData.self, forKey: .nowContext))
        case .daySnapshot:
            self = .daySnapshot(try container.decode(DaySnapshotCardData.self, forKey: .daySnapshot))
        case .slotPicker:
            self = .slotPicker(try container.decode(SlotPickerCardData.self, forKey: .slotPicker))
        case .operationReceipt:
            self = .operationReceipt(try container.decode(OperationReceiptCardData.self, forKey: .operationReceipt))
        case .weekSummary:
            self = .weekSummary(try container.decode(WeekSummaryCardData.self, forKey: .weekSummary))
        case .themeDetail:
            self = .themeDetail(try container.decode(ThemeDetailCardData.self, forKey: .themeDetail))
        case .blockProposal:
            self = .blockProposal(try container.decode(BlockProposalCardData.self, forKey: .blockProposal))
        case .compactWeekCalendar:
            self = .compactWeekCalendar(try container.decode(CompactWeekCalendarData.self, forKey: .compactWeekCalendar))
        }
    }
}
