import Foundation
import SQLite
import SwiftUI

struct FocusGroupStore: DatabaseStore {
    let database: Database

    // MARK: - Table Definitions

    private static let focusGroups = Table("focus_groups")
    private static let focusBlocks = Table("focus_blocks")
    private static let focusGroupItems = Table("focus_group_items")
    private static let eventFocusKeywords = Table("event_focus_keywords")

    // focus_groups columns
    private static let id = Expression<String>("id")
    private static let name = Expression<String>("name")
    private static let color = Expression<String>("color")
    private static let description = Expression<String?>("description")
    private static let isArchived = Expression<Bool>("is_archived")
    private static let sortOrder = Expression<Int>("sort_order")
    private static let createdAt = Expression<Double>("created_at")
    private static let defaultStartTime = Expression<String?>("default_start_time")
    private static let defaultDurationMinutes = Expression<Int>("default_duration_minutes")
    private static let contextFilter = Expression<String?>("context_filter")
    private static let autoRemindLeftover = Expression<Bool>("auto_remind_leftover")
    private static let leftoverRemindTime = Expression<String?>("leftover_remind_time")

    // focus_blocks columns
    private static let blockId = Expression<String>("id")
    private static let groupId = Expression<String>("group_id")
    private static let startTime = Expression<String>("start_time")
    private static let endTime = Expression<String>("end_time")
    private static let isRecurring = Expression<Bool>("is_recurring")
    private static let recurrenceRule = Expression<String?>("recurrence_rule")
    private static let blockCreatedAt = Expression<Double>("created_at")

    // focus_group_items columns
    private static let itemId = Expression<String>("id")
    private static let itemGroupId = Expression<String>("group_id")
    private static let itemType = Expression<String>("item_type")
    private static let linkedItemId = Expression<String>("item_id")
    private static let itemCreatedAt = Expression<Double>("created_at")

    // event_focus_keywords columns
    private static let keywordId = Expression<String>("id")
    private static let keywordGroupId = Expression<String>("group_id")
    private static let keyword = Expression<String>("keyword")

    // MARK: - Table Creation

    static func createTables(in db: Connection) throws {
        try db.run(focusGroups.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(name)
            t.column(color, defaultValue: "blue")
            t.column(description)
            t.column(isArchived, defaultValue: false)
            t.column(sortOrder, defaultValue: 0)
            t.column(createdAt)
            t.column(defaultStartTime)
            t.column(defaultDurationMinutes, defaultValue: 60)
            t.column(contextFilter)
            t.column(autoRemindLeftover, defaultValue: false)
            t.column(leftoverRemindTime)
        })

        try db.run(focusBlocks.create(ifNotExists: true) { t in
            t.column(blockId, primaryKey: true)
            t.column(groupId)
            t.column(startTime)
            t.column(endTime)
            t.column(isRecurring, defaultValue: false)
            t.column(recurrenceRule)
            t.column(blockCreatedAt)
        })

        try db.run(focusGroupItems.create(ifNotExists: true) { t in
            t.column(itemId, primaryKey: true)
            t.column(itemGroupId)
            t.column(itemType)
            t.column(linkedItemId)
            t.column(itemCreatedAt)
            t.unique(itemGroupId, itemType, linkedItemId)
        })

        try db.run(eventFocusKeywords.create(ifNotExists: true) { t in
            t.column(keywordId, primaryKey: true)
            t.column(keywordGroupId)
            t.column(keyword)
        })
    }

    // MARK: - Focus Group CRUD

    func createFocusGroup(_ group: FocusGroup) throws {
        try perform { db in
            let filterJSON: String?
            if let filter = group.contextFilter {
                filterJSON = try? String(data: JSONEncoder().encode(filter), encoding: .utf8)
            } else {
                filterJSON = nil
            }

            try db.run(Self.focusGroups.insert(or: .replace,
                Self.id <- group.id,
                Self.name <- group.name,
                Self.color <- group.color,
                Self.description <- group.description,
                Self.isArchived <- group.isArchived,
                Self.sortOrder <- group.sortOrder,
                Self.createdAt <- group.createdAt.timeIntervalSince1970,
                Self.defaultStartTime <- group.defaultStartTime,
                Self.defaultDurationMinutes <- group.defaultDurationMinutes,
                Self.contextFilter <- filterJSON,
                Self.autoRemindLeftover <- group.autoRemindLeftover,
                Self.leftoverRemindTime <- group.leftoverRemindTime
            ))
        }
    }

    func getFocusGroups(includeArchived: Bool = false) throws -> [FocusGroup] {
        try perform { db in
            var query = Self.focusGroups.order(Self.sortOrder, Self.name)
            if !includeArchived {
                query = query.filter(Self.isArchived == false)
            }
            return try db.prepare(query).map(parseFocusGroup)
        }
    }

    func getFocusGroup(id groupId: String) throws -> FocusGroup? {
        try perform { db in
            guard let row = try db.pluck(Self.focusGroups.filter(Self.id == groupId)) else {
                return nil
            }
            return parseFocusGroup(from: row)
        }
    }

    func updateFocusGroup(_ group: FocusGroup) throws {
        try perform { db in
            let filterJSON: String?
            if let filter = group.contextFilter {
                filterJSON = try? String(data: JSONEncoder().encode(filter), encoding: .utf8)
            } else {
                filterJSON = nil
            }

            try db.run(Self.focusGroups.filter(Self.id == group.id).update(
                Self.name <- group.name,
                Self.color <- group.color,
                Self.description <- group.description,
                Self.isArchived <- group.isArchived,
                Self.sortOrder <- group.sortOrder,
                Self.defaultStartTime <- group.defaultStartTime,
                Self.defaultDurationMinutes <- group.defaultDurationMinutes,
                Self.contextFilter <- filterJSON,
                Self.autoRemindLeftover <- group.autoRemindLeftover,
                Self.leftoverRemindTime <- group.leftoverRemindTime
            ))
        }
    }

    func archiveFocusGroup(id groupId: String) throws {
        try perform { db in
            try db.run(Self.focusGroups.filter(Self.id == groupId).update(Self.isArchived <- true))
        }
    }

    func deleteFocusGroup(id groupId: String) throws {
        try perform { db in
            try db.run(Self.focusGroups.filter(Self.id == groupId).delete())
            try db.run(Self.focusGroupItems.filter(Self.itemGroupId == groupId).delete())
            try db.run(Self.eventFocusKeywords.filter(Self.keywordGroupId == groupId).delete())
            try db.run(Self.focusBlocks.filter(Self.groupId == groupId).delete())
        }
    }

    // MARK: - Focus Blocks

    func createFocusBlock(_ block: FocusBlock) throws {
        try perform { db in
            try db.run(Self.focusBlocks.insert(or: .replace,
                Self.blockId <- block.id,
                Self.groupId <- block.groupId,
                Self.startTime <- ISO8601DateFormatter().string(from: block.startTime),
                Self.endTime <- ISO8601DateFormatter().string(from: block.endTime),
                Self.isRecurring <- block.isRecurring,
                Self.recurrenceRule <- block.recurrenceRule,
                Self.blockCreatedAt <- Date().timeIntervalSince1970
            ))
        }
    }

    func getFocusBlocksForGroup(id groupId: String) throws -> [FocusBlock] {
        try perform { db in
            try db.prepare(Self.focusBlocks.filter(Self.groupId == groupId)).map(parseFocusBlock)
        }
    }

    func getFocusBlocksForDay(_ date: Date) throws -> [FocusBlock] {
        try perform { db in
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

            let formatter = ISO8601DateFormatter()
            let startString = formatter.string(from: startOfDay)
            let endString = formatter.string(from: endOfDay)

            // Get non-recurring blocks for this day
            var blocks = try db.prepare(
                Self.focusBlocks
                    .filter(Self.startTime >= startString && Self.startTime < endString)
                    .filter(Self.isRecurring == false)
            ).map(parseFocusBlock)

            // Get recurring blocks that might apply
            let recurringBlocks = try db.prepare(
                Self.focusBlocks.filter(Self.isRecurring == true)
            ).map(parseFocusBlock)

            // Filter recurring blocks that apply to this day
            let weekday = calendar.component(.weekday, from: date)
            let weekdayMap = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

            for block in recurringBlocks {
                if let rule = block.recurrenceRule {
                    // Parse BYDAY from recurrence rule
                    if let byDayRange = rule.range(of: "BYDAY=") {
                        let byDayStart = byDayRange.upperBound
                        let remaining = String(rule[byDayStart...])
                        let days = remaining.components(separatedBy: ";").first?.components(separatedBy: ",") ?? []

                        for day in days {
                            if weekdayMap[day] == weekday {
                                // This recurring block applies to today
                                // Create a copy with adjusted times
                                let timeComponents = calendar.dateComponents([.hour, .minute], from: block.startTime)
                                if let adjustedStart = calendar.date(bySettingHour: timeComponents.hour ?? 9, minute: timeComponents.minute ?? 0, second: 0, of: date) {
                                    let duration = block.endTime.timeIntervalSince(block.startTime)
                                    var adjustedBlock = block
                                    adjustedBlock.startTime = adjustedStart
                                    adjustedBlock.endTime = adjustedStart.addingTimeInterval(duration)
                                    blocks.append(adjustedBlock)
                                }
                                break
                            }
                        }
                    }
                }
            }

            return blocks.sorted { $0.startTime < $1.startTime }
        }
    }

    func updateFocusBlock(_ block: FocusBlock) throws {
        try perform { db in
            try db.run(Self.focusBlocks.filter(Self.blockId == block.id).update(
                Self.startTime <- ISO8601DateFormatter().string(from: block.startTime),
                Self.endTime <- ISO8601DateFormatter().string(from: block.endTime),
                Self.isRecurring <- block.isRecurring,
                Self.recurrenceRule <- block.recurrenceRule
            ))
        }
    }

    func deleteFocusBlock(id blockId: String) throws {
        try perform { db in
            try db.run(Self.focusBlocks.filter(Self.blockId == blockId).delete())
        }
    }

    // MARK: - Focus Group Items

    func addItemToFocusGroup(groupId: String, itemType: FocusGroupItemType, itemId: String) throws {
        try perform { db in
            try db.run(Self.focusGroupItems.insert(or: .ignore,
                Self.itemId <- UUID().uuidString,
                Self.itemGroupId <- groupId,
                Self.itemType <- itemType.rawValue,
                Self.linkedItemId <- itemId,
                Self.itemCreatedAt <- Date().timeIntervalSince1970
            ))
        }
    }

    func removeItemFromFocusGroup(groupId: String, itemType: FocusGroupItemType, itemId: String) throws {
        try perform { db in
            try db.run(Self.focusGroupItems
                .filter(Self.itemGroupId == groupId && Self.itemType == itemType.rawValue && Self.linkedItemId == itemId)
                .delete()
            )
        }
    }

    func getItemsForFocusGroup(id groupId: String, type: FocusGroupItemType? = nil) throws -> [FocusGroupItem] {
        try perform { db in
            var query = Self.focusGroupItems.filter(Self.itemGroupId == groupId)
            if let type {
                query = query.filter(Self.itemType == type.rawValue)
            }
            return try db.prepare(query.order(Self.itemCreatedAt.desc)).map { row in
                FocusGroupItem(
                    id: row[Self.itemId],
                    groupId: row[Self.itemGroupId],
                    itemType: FocusGroupItemType(rawValue: row[Self.itemType]) ?? .task,
                    itemId: row[Self.linkedItemId],
                    createdAt: Date(timeIntervalSince1970: row[Self.itemCreatedAt])
                )
            }
        }
    }

    func getFocusGroupsForItem(itemType: FocusGroupItemType, itemId: String) throws -> [FocusGroup] {
        try perform { db in
            let groupIds = try db.prepare(
                Self.focusGroupItems
                    .filter(Self.itemType == itemType.rawValue && Self.linkedItemId == itemId)
                    .select(Self.itemGroupId)
            ).map { $0[Self.itemGroupId] }

            guard !groupIds.isEmpty else { return [] }

            return try db.prepare(
                Self.focusGroups.filter(groupIds.contains(Self.id))
            ).map(parseFocusGroup)
        }
    }

    func getTaskCountForFocusGroup(id groupId: String) throws -> Int {
        try perform { db in
            try db.scalar(
                Self.focusGroupItems
                    .filter(Self.itemGroupId == groupId && Self.itemType == FocusGroupItemType.task.rawValue)
                    .count
            )
        }
    }

    // MARK: - Event Focus Keywords

    func addKeyword(_ keywordText: String, toFocusGroup groupId: String) throws {
        try perform { db in
            try db.run(Self.eventFocusKeywords.insert(or: .ignore,
                Self.keywordId <- UUID().uuidString,
                Self.keywordGroupId <- groupId,
                Self.keyword <- keywordText.lowercased()
            ))
        }
    }

    func getKeywords(forFocusGroup groupId: String) throws -> [String] {
        try perform { db in
            try db.prepare(
                Self.eventFocusKeywords.filter(Self.keywordGroupId == groupId)
            ).map { $0[Self.keyword] }
        }
    }

    func removeKeyword(_ keywordText: String, fromFocusGroup groupId: String) throws {
        try perform { db in
            try db.run(Self.eventFocusKeywords
                .filter(Self.keywordGroupId == groupId && Self.keyword == keywordText.lowercased())
                .delete()
            )
        }
    }

    // MARK: - Active Focus Detection

    func getActiveFocusGroup(at date: Date = Date()) throws -> FocusGroup? {
        let blocks = try getFocusBlocksForDay(date)
        for block in blocks {
            if date >= block.startTime && date < block.endTime {
                return try getFocusGroup(id: block.groupId)
            }
        }
        return nil
    }

    // MARK: - Parsing

    private func parseFocusGroup(from row: Row) -> FocusGroup {
        var filter: ContextFilter?
        if let filterJSON = row[Self.contextFilter],
           let data = filterJSON.data(using: .utf8) {
            filter = try? JSONDecoder().decode(ContextFilter.self, from: data)
        }

        return FocusGroup(
            id: row[Self.id],
            name: row[Self.name],
            color: row[Self.color],
            description: row[Self.description],
            isArchived: row[Self.isArchived],
            sortOrder: row[Self.sortOrder],
            createdAt: Date(timeIntervalSince1970: row[Self.createdAt]),
            defaultStartTime: row[Self.defaultStartTime],
            defaultDurationMinutes: row[Self.defaultDurationMinutes],
            contextFilter: filter,
            autoRemindLeftover: row[Self.autoRemindLeftover],
            leftoverRemindTime: row[Self.leftoverRemindTime]
        )
    }

    private func parseFocusBlock(from row: Row) -> FocusBlock {
        let formatter = ISO8601DateFormatter()
        return FocusBlock(
            id: row[Self.blockId],
            groupId: row[Self.groupId],
            startTime: formatter.date(from: row[Self.startTime]) ?? Date(),
            endTime: formatter.date(from: row[Self.endTime]) ?? Date(),
            isRecurring: row[Self.isRecurring],
            recurrenceRule: row[Self.recurrenceRule]
        )
    }
}

// MARK: - Models

struct FocusGroup: Identifiable {
    let id: String
    var name: String
    var color: String
    var description: String?
    var isArchived: Bool
    var sortOrder: Int
    let createdAt: Date
    var defaultStartTime: String?
    var defaultDurationMinutes: Int
    var contextFilter: ContextFilter?
    var autoRemindLeftover: Bool
    var leftoverRemindTime: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        color: String = "blue",
        description: String? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        defaultStartTime: String? = "09:00",
        defaultDurationMinutes: Int = 60,
        contextFilter: ContextFilter? = nil,
        autoRemindLeftover: Bool = false,
        leftoverRemindTime: String? = "17:00"
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.description = description
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.defaultStartTime = defaultStartTime
        self.defaultDurationMinutes = defaultDurationMinutes
        self.contextFilter = contextFilter
        self.autoRemindLeftover = autoRemindLeftover
        self.leftoverRemindTime = leftoverRemindTime
    }

    var swiftUIColor: Color {
        switch color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        case "indigo": return .indigo
        case "teal": return .teal
        default: return .blue
        }
    }
}

struct ContextFilter: Codable, Equatable {
    var calendarKeywords: [String]
    var includeCalendar: Bool
    var includeReminders: Bool
    var includeEmails: Bool
    var includeTasks: Bool

    init(
        calendarKeywords: [String] = [],
        includeCalendar: Bool = true,
        includeReminders: Bool = true,
        includeEmails: Bool = false,
        includeTasks: Bool = true
    ) {
        self.calendarKeywords = calendarKeywords
        self.includeCalendar = includeCalendar
        self.includeReminders = includeReminders
        self.includeEmails = includeEmails
        self.includeTasks = includeTasks
    }
}

struct FocusBlock: Identifiable {
    let id: String
    let groupId: String
    var startTime: Date
    var endTime: Date
    var isRecurring: Bool
    var recurrenceRule: String?

    init(
        id: String = UUID().uuidString,
        groupId: String,
        startTime: Date,
        endTime: Date,
        isRecurring: Bool = false,
        recurrenceRule: String? = nil
    ) {
        self.id = id
        self.groupId = groupId
        self.startTime = startTime
        self.endTime = endTime
        self.isRecurring = isRecurring
        self.recurrenceRule = recurrenceRule
    }

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }
}

enum FocusGroupItemType: String, Codable {
    case task
    case note
    case goal
}

struct FocusGroupItem: Identifiable {
    let id: String
    let groupId: String
    let itemType: FocusGroupItemType
    let itemId: String
    let createdAt: Date
}
