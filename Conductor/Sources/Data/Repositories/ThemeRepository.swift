import Foundation
import GRDB

struct ThemeRepository: Sendable {
    let db: GRDBDatabase

    // MARK: - Themes

    func createTheme(_ theme: Theme) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO themes
                    (id, name, color, description, is_archived, sort_order, created_at,
                     objective, default_start_time, default_duration_minutes, context_filter,
                     auto_remind_leftover, leftover_remind_time, is_loose_bucket)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    theme.id, theme.name, theme.color, theme.themeDescription,
                    theme.isArchived, theme.sortOrder, theme.createdAt.timeIntervalSince1970,
                    theme.objective, theme.defaultStartTime, theme.defaultDurationMinutes,
                    Self.encodeJSON(theme.contextFilter),
                    theme.autoRemindLeftover, theme.leftoverRemindTime, theme.isLooseBucket,
                ]
            )
        }
    }

    func getThemes(includeArchived: Bool = false) throws -> [Theme] {
        try db.read { db in
            let sql = includeArchived
                ? "SELECT * FROM themes ORDER BY sort_order ASC"
                : "SELECT * FROM themes WHERE is_archived = 0 ORDER BY sort_order ASC"
            return try Row.fetchAll(db, sql: sql).map { Self.parseTheme(from: $0) }
        }
    }

    func getTheme(id: String) throws -> Theme? {
        try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM themes WHERE id = ?", arguments: [id])
            else { return nil }
            return Self.parseTheme(from: row)
        }
    }

    func getLooseTheme() throws -> Theme {
        try db.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM themes WHERE is_loose_bucket = 1 LIMIT 1") {
                return Self.parseTheme(from: row)
            }
            // Create the loose theme if it doesn't exist
            let id = UUID().uuidString
            let now = Date().timeIntervalSince1970
            try db.execute(
                sql: """
                    INSERT INTO themes
                    (id, name, color, description, is_archived, sort_order, created_at,
                     objective, default_start_time, default_duration_minutes, context_filter,
                     auto_remind_leftover, leftover_remind_time, is_loose_bucket)
                    VALUES (?, 'Loose', 'gray', 'Uncategorized tasks and items', 0, 999, ?,
                            NULL, NULL, 60, NULL, 0, NULL, 1)
                    """,
                arguments: [id, now]
            )
            return Theme(
                id: id, name: "Loose", color: "gray",
                themeDescription: "Uncategorized tasks and items",
                objective: nil, isArchived: false, sortOrder: 999,
                createdAt: Date(timeIntervalSince1970: now),
                defaultStartTime: nil, defaultDurationMinutes: 60,
                contextFilter: nil, autoRemindLeftover: false,
                leftoverRemindTime: nil, isLooseBucket: true
            )
        }
    }

    func updateTheme(_ theme: Theme) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE themes SET
                    name = ?, color = ?, description = ?, is_archived = ?, sort_order = ?,
                    objective = ?, default_start_time = ?, default_duration_minutes = ?,
                    context_filter = ?, auto_remind_leftover = ?, leftover_remind_time = ?,
                    is_loose_bucket = ?
                    WHERE id = ?
                    """,
                arguments: [
                    theme.name, theme.color, theme.themeDescription,
                    theme.isArchived, theme.sortOrder,
                    theme.objective, theme.defaultStartTime, theme.defaultDurationMinutes,
                    Self.encodeJSON(theme.contextFilter),
                    theme.autoRemindLeftover, theme.leftoverRemindTime, theme.isLooseBucket,
                    theme.id,
                ]
            )
        }
    }

    func archiveTheme(id: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE themes SET is_archived = 1 WHERE id = ?", arguments: [id])
        }
    }

    func deleteTheme(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM theme_items WHERE theme_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM event_theme_keywords WHERE theme_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM theme_blocks WHERE theme_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM themes WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Theme Items

    func addItemToTheme(themeId: String, itemType: ThemeItemType, itemId: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO theme_items (id, theme_id, item_type, item_id, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, themeId, itemType.rawValue, itemId, Date().timeIntervalSince1970]
            )
        }
    }

    func removeItemFromTheme(themeId: String, itemType: ThemeItemType, itemId: String) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM theme_items WHERE theme_id = ? AND item_type = ? AND item_id = ?",
                arguments: [themeId, itemType.rawValue, itemId]
            )
        }
    }

    func getItemsForTheme(id themeId: String, type: ThemeItemType? = nil) throws -> [ThemeItem] {
        try db.read { db in
            let sql: String
            let args: StatementArguments
            if let type {
                sql = "SELECT * FROM theme_items WHERE theme_id = ? AND item_type = ? ORDER BY created_at ASC"
                args = [themeId, type.rawValue]
            } else {
                sql = "SELECT * FROM theme_items WHERE theme_id = ? ORDER BY created_at ASC"
                args = [themeId]
            }
            return try Row.fetchAll(db, sql: sql, arguments: args).map { Self.parseThemeItem(from: $0) }
        }
    }

    func getThemesForItem(itemType: ThemeItemType, itemId: String) throws -> [Theme] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT t.* FROM themes t
                    JOIN theme_items ti ON t.id = ti.theme_id
                    WHERE ti.item_type = ? AND ti.item_id = ?
                    """,
                arguments: [itemType.rawValue, itemId]
            )
            return rows.map { Self.parseTheme(from: $0) }
        }
    }

    func getTaskCountForTheme(id themeId: String) throws -> Int {
        try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM theme_items WHERE theme_id = ? AND item_type = 'task'",
                arguments: [themeId]
            ) ?? 0
        }
    }

    func getTaskIdsForTheme(id themeId: String) throws -> [String] {
        try db.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT item_id FROM theme_items WHERE theme_id = ? AND item_type = 'task'",
                arguments: [themeId]
            )
        }
    }

    // MARK: - Keywords

    func addKeyword(_ keyword: String, toTheme themeId: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO event_theme_keywords (id, theme_id, keyword) VALUES (?, ?, ?)",
                arguments: [UUID().uuidString, themeId, keyword]
            )
        }
    }

    func getKeywords(forTheme themeId: String) throws -> [String] {
        try db.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT keyword FROM event_theme_keywords WHERE theme_id = ?",
                arguments: [themeId]
            )
        }
    }

    func removeKeyword(_ keyword: String, fromTheme themeId: String) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM event_theme_keywords WHERE theme_id = ? AND keyword = ?",
                arguments: [themeId, keyword]
            )
        }
    }

    // MARK: - Theme Blocks

    func createThemeBlock(_ block: ThemeBlock) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO theme_blocks
                    (id, theme_id, start_time, end_time, is_recurring, recurrence_rule,
                     status, calendar_event_id, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    block.id, block.themeId,
                    SharedDateFormatters.iso8601DateTime.string(from: block.startTime),
                    SharedDateFormatters.iso8601DateTime.string(from: block.endTime),
                    block.isRecurring, block.recurrenceRule,
                    block.status.rawValue, block.calendarEventId,
                    block.createdAt.timeIntervalSince1970,
                    block.updatedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func getThemeBlocksForTheme(id themeId: String) throws -> [ThemeBlock] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM theme_blocks WHERE theme_id = ? ORDER BY start_time ASC",
                arguments: [themeId]
            ).compactMap { Self.parseThemeBlock(from: $0) }
        }
    }

    func getThemeBlock(id blockId: String) throws -> ThemeBlock? {
        try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM theme_blocks WHERE id = ?", arguments: [blockId])
            else { return nil }
            return Self.parseThemeBlock(from: row)
        }
    }

    func getThemeBlocksForDay(_ date: Date) throws -> [ThemeBlock] {
        try db.read { db in
            let dayStr = SharedDateFormatters.databaseDate.string(from: date)
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM theme_blocks WHERE start_time LIKE ? ORDER BY start_time ASC",
                arguments: ["\(dayStr)%"]
            )
            return rows.compactMap { Self.parseThemeBlock(from: $0) }
        }
    }

    func updateThemeBlock(_ block: ThemeBlock) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE theme_blocks SET
                    theme_id = ?, start_time = ?, end_time = ?, is_recurring = ?,
                    recurrence_rule = ?, status = ?, calendar_event_id = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    block.themeId,
                    SharedDateFormatters.iso8601DateTime.string(from: block.startTime),
                    SharedDateFormatters.iso8601DateTime.string(from: block.endTime),
                    block.isRecurring, block.recurrenceRule,
                    block.status.rawValue, block.calendarEventId,
                    Date().timeIntervalSince1970,
                    block.id,
                ]
            )
        }
    }

    func deleteThemeBlock(id blockId: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM theme_blocks WHERE id = ?", arguments: [blockId])
        }
    }

    func getActiveTheme(at date: Date = Date()) throws -> Theme? {
        try db.read { db in
            let dateStr = SharedDateFormatters.iso8601DateTime.string(from: date)
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT t.* FROM themes t
                    JOIN theme_blocks tb ON t.id = tb.theme_id
                    WHERE tb.start_time <= ? AND tb.end_time >= ?
                    AND tb.status IN ('planned', 'published')
                    AND t.is_archived = 0
                    LIMIT 1
                    """,
                arguments: [dateStr, dateStr]
            ) else { return nil }
            return Self.parseTheme(from: row)
        }
    }

    // MARK: - Parsing

    static func parseTheme(from row: Row) -> Theme {
        var contextFilter: ContextFilter?
        if let cfJson: String = row["context_filter"] {
            contextFilter = Self.decodeJSON(ContextFilter.self, from: cfJson)
        }

        return Theme(
            id: row["id"],
            name: row["name"],
            color: row["color"],
            themeDescription: row["description"],
            objective: row["objective"],
            isArchived: row["is_archived"],
            sortOrder: row["sort_order"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            defaultStartTime: row["default_start_time"],
            defaultDurationMinutes: row["default_duration_minutes"],
            contextFilter: contextFilter,
            autoRemindLeftover: row["auto_remind_leftover"],
            leftoverRemindTime: row["leftover_remind_time"],
            isLooseBucket: row["is_loose_bucket"]
        )
    }

    private static func parseThemeItem(from row: Row) -> ThemeItem {
        ThemeItem(
            id: row["id"],
            themeId: row["theme_id"],
            itemType: ThemeItemType(rawValue: row["item_type"]) ?? .task,
            itemId: row["item_id"],
            createdAt: Date(timeIntervalSince1970: row["created_at"])
        )
    }

    private static func parseThemeBlock(from row: Row) -> ThemeBlock? {
        guard let startStr: String = row["start_time"],
              let endStr: String = row["end_time"],
              let startTime = SharedDateFormatters.iso8601DateTime.date(from: startStr),
              let endTime = SharedDateFormatters.iso8601DateTime.date(from: endStr)
        else { return nil }

        return ThemeBlock(
            id: row["id"],
            themeId: row["theme_id"],
            startTime: startTime,
            endTime: endTime,
            isRecurring: row["is_recurring"],
            recurrenceRule: row["recurrence_rule"],
            status: ThemeBlock.Status(rawValue: row["status"]) ?? .draft,
            calendarEventId: row["calendar_event_id"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"])
        )
    }

    private static func encodeJSON<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
