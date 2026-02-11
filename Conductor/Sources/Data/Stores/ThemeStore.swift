import Foundation
import SQLite

struct ThemeStore: DatabaseStore {
    let database: Database

    // MARK: - Table Definitions

    private static let themes = Table("themes")
    private static let themeItems = Table("theme_items")
    private static let eventThemeKeywords = Table("event_theme_keywords")

    // themes columns
    private static let id = Expression<String>("id")
    private static let name = Expression<String>("name")
    private static let color = Expression<String>("color")
    private static let description = Expression<String?>("description")
    private static let isArchived = Expression<Bool>("is_archived")
    private static let sortOrder = Expression<Int>("sort_order")
    private static let createdAt = Expression<Double>("created_at")

    // theme_items columns
    private static let itemId = Expression<String>("id")
    private static let themeId = Expression<String>("theme_id")
    private static let itemType = Expression<String>("item_type")
    private static let linkedItemId = Expression<String>("item_id")
    private static let itemCreatedAt = Expression<Double>("created_at")

    // event_theme_keywords columns
    private static let keywordId = Expression<String>("id")
    private static let keywordThemeId = Expression<String>("theme_id")
    private static let keyword = Expression<String>("keyword")

    // MARK: - Table Creation

    static func createTables(in db: Connection) throws {
        try db.run(themes.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(name)
            t.column(color, defaultValue: "blue")
            t.column(description)
            t.column(isArchived, defaultValue: false)
            t.column(sortOrder, defaultValue: 0)
            t.column(createdAt)
        })

        try db.run(themeItems.create(ifNotExists: true) { t in
            t.column(itemId, primaryKey: true)
            t.column(themeId)
            t.column(itemType)
            t.column(linkedItemId)
            t.column(itemCreatedAt)
            t.unique(themeId, itemType, linkedItemId)
        })

        try db.run(eventThemeKeywords.create(ifNotExists: true) { t in
            t.column(keywordId, primaryKey: true)
            t.column(keywordThemeId)
            t.column(keyword)
        })
    }

    // MARK: - Theme CRUD

    func createTheme(_ theme: Theme) throws {
        try perform { db in
            try db.run(Self.themes.insert(or: .replace,
                Self.id <- theme.id,
                Self.name <- theme.name,
                Self.color <- theme.color,
                Self.description <- theme.themeDescription,
                Self.isArchived <- theme.isArchived,
                Self.sortOrder <- theme.sortOrder,
                Self.createdAt <- theme.createdAt.timeIntervalSince1970
            ))
        }
    }

    func getThemes(includeArchived: Bool = false) throws -> [Theme] {
        try perform { db in
            var query = Self.themes.order(Self.sortOrder, Self.name)
            if !includeArchived {
                query = query.filter(Self.isArchived == false)
            }
            return try db.prepare(query).map(parseTheme)
        }
    }

    func getTheme(id themeId: String) throws -> Theme? {
        try perform { db in
            guard let row = try db.pluck(Self.themes.filter(Self.id == themeId)) else {
                return nil
            }
            return parseTheme(from: row)
        }
    }

    func updateTheme(_ theme: Theme) throws {
        try perform { db in
            try db.run(Self.themes.filter(Self.id == theme.id).update(
                Self.name <- theme.name,
                Self.color <- theme.color,
                Self.description <- theme.themeDescription,
                Self.isArchived <- theme.isArchived,
                Self.sortOrder <- theme.sortOrder
            ))
        }
    }

    func archiveTheme(id themeId: String) throws {
        try perform { db in
            try db.run(Self.themes.filter(Self.id == themeId).update(Self.isArchived <- true))
        }
    }

    func deleteTheme(id themeId: String) throws {
        try perform { db in
            try db.run(Self.themes.filter(Self.id == themeId).delete())
            try db.run(Self.themeItems.filter(Self.themeId == themeId).delete())
            try db.run(Self.eventThemeKeywords.filter(Self.keywordThemeId == themeId).delete())
        }
    }

    // MARK: - Theme Items

    func addItemToTheme(themeId: String, itemType: ThemeItemType, itemId: String) throws {
        try perform { db in
            try db.run(Self.themeItems.insert(or: .ignore,
                Self.itemId <- UUID().uuidString,
                Self.themeId <- themeId,
                Self.itemType <- itemType.rawValue,
                Self.linkedItemId <- itemId,
                Self.itemCreatedAt <- Date().timeIntervalSince1970
            ))
        }
    }

    func removeItemFromTheme(themeId: String, itemType: ThemeItemType, itemId: String) throws {
        try perform { db in
            try db.run(Self.themeItems
                .filter(Self.themeId == themeId && Self.itemType == itemType.rawValue && Self.linkedItemId == itemId)
                .delete()
            )
        }
    }

    func getItemsForTheme(id themeId: String, type: ThemeItemType? = nil) throws -> [ThemeItem] {
        try perform { db in
            var query = Self.themeItems.filter(Self.themeId == themeId)
            if let type {
                query = query.filter(Self.itemType == type.rawValue)
            }
            return try db.prepare(query.order(Self.itemCreatedAt.desc)).map { row in
                ThemeItem(
                    id: row[Self.itemId],
                    themeId: row[Self.themeId],
                    itemType: ThemeItemType(rawValue: row[Self.itemType]) ?? .task,
                    itemId: row[Self.linkedItemId],
                    createdAt: Date(timeIntervalSince1970: row[Self.itemCreatedAt])
                )
            }
        }
    }

    func getThemesForItem(itemType: ThemeItemType, itemId: String) throws -> [Theme] {
        try perform { db in
            let themeIds = try db.prepare(
                Self.themeItems
                    .filter(Self.itemType == itemType.rawValue && Self.linkedItemId == itemId)
                    .select(Self.themeId)
            ).map { $0[Self.themeId] }

            guard !themeIds.isEmpty else { return [] }

            return try db.prepare(
                Self.themes.filter(themeIds.contains(Self.id))
            ).map(parseTheme)
        }
    }

    func getTaskCountForTheme(id themeId: String) throws -> Int {
        try perform { db in
            try db.scalar(
                Self.themeItems
                    .filter(Self.themeId == themeId && Self.itemType == ThemeItemType.task.rawValue)
                    .count
            )
        }
    }

    // MARK: - Event Theme Keywords

    func addKeyword(_ keywordText: String, toTheme themeId: String) throws {
        try perform { db in
            try db.run(Self.eventThemeKeywords.insert(or: .ignore,
                Self.keywordId <- UUID().uuidString,
                Self.keywordThemeId <- themeId,
                Self.keyword <- keywordText.lowercased()
            ))
        }
    }

    func getKeywords(forTheme themeId: String) throws -> [String] {
        try perform { db in
            try db.prepare(
                Self.eventThemeKeywords.filter(Self.keywordThemeId == themeId)
            ).map { $0[Self.keyword] }
        }
    }

    func removeKeyword(_ keywordText: String, fromTheme themeId: String) throws {
        try perform { db in
            try db.run(Self.eventThemeKeywords
                .filter(Self.keywordThemeId == themeId && Self.keyword == keywordText.lowercased())
                .delete()
            )
        }
    }

    // MARK: - Parsing

    private func parseTheme(from row: Row) -> Theme {
        Theme(
            id: row[Self.id],
            name: row[Self.name],
            color: row[Self.color],
            themeDescription: row[Self.description],
            isArchived: row[Self.isArchived],
            sortOrder: row[Self.sortOrder],
            createdAt: Date(timeIntervalSince1970: row[Self.createdAt])
        )
    }
}

// MARK: - Models

struct Theme: Identifiable {
    let id: String
    var name: String
    var color: String
    var themeDescription: String?
    var isArchived: Bool
    var sortOrder: Int
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        color: String = "blue",
        themeDescription: String? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.themeDescription = themeDescription
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var swiftUIColor: SwiftUI.Color {
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

import SwiftUI

enum ThemeItemType: String, Codable {
    case task
    case note
    case goal
}

struct ThemeItem: Identifiable {
    let id: String
    let themeId: String
    let itemType: ThemeItemType
    let itemId: String
    let createdAt: Date
}
