import Foundation
import SQLite

/// A user-curated item stored in the context library
struct ContextLibraryItem: Identifiable, Codable {
    let id: String
    var title: String
    var content: String
    var type: ItemType
    var createdAt: Date
    var autoInclude: Bool

    enum ItemType: String, Codable, CaseIterable {
        case note
        case link
        case document
        case calendarSnapshot
        case custom

        var icon: String {
            switch self {
            case .note: return "note.text"
            case .link: return "link"
            case .document: return "doc"
            case .calendarSnapshot: return "calendar"
            case .custom: return "square.and.pencil"
            }
        }

        var displayName: String {
            switch self {
            case .note: return "Note"
            case .link: return "Link"
            case .document: return "Document"
            case .calendarSnapshot: return "Calendar Snapshot"
            case .custom: return "Custom"
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        content: String,
        type: ItemType = .note,
        createdAt: Date = Date(),
        autoInclude: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.type = type
        self.createdAt = createdAt
        self.autoInclude = autoInclude
    }
}

/// Store for persistent context library items
struct ContextLibraryStore: DatabaseStore {
    let database: Database

    private let table = Table("context_library")
    private let id = Expression<String>("id")
    private let title = Expression<String>("title")
    private let content = Expression<String>("content")
    private let type = Expression<String>("type")
    private let createdAt = Expression<Double>("created_at")
    private let autoInclude = Expression<Bool>("auto_include")

    static func createTables(in db: Connection) throws {
        let table = Table("context_library")
        let id = Expression<String>("id")
        let title = Expression<String>("title")
        let content = Expression<String>("content")
        let type = Expression<String>("type")
        let createdAt = Expression<Double>("created_at")
        let autoInclude = Expression<Bool>("auto_include")

        try db.run(table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(title)
            t.column(content)
            t.column(type)
            t.column(createdAt)
            t.column(autoInclude)
        })
        try db.run(table.createIndex(createdAt, ifNotExists: true))
        try db.run(table.createIndex(autoInclude, ifNotExists: true))
    }

    /// Save a new context library item
    func save(item: ContextLibraryItem) throws {
        try perform { db in
            let insert = table.insert(or: .replace,
                id <- item.id,
                title <- item.title,
                content <- item.content,
                type <- item.type.rawValue,
                createdAt <- item.createdAt.timeIntervalSince1970,
                autoInclude <- item.autoInclude
            )
            try db.run(insert)
        }
    }

    /// Update an existing item
    func update(id itemId: String, title newTitle: String? = nil, content newContent: String? = nil, autoInclude newAutoInclude: Bool? = nil) throws {
        try perform { db in
            let item = table.filter(id == itemId)
            var setters: [Setter] = []

            if let newTitle { setters.append(title <- newTitle) }
            if let newContent { setters.append(content <- newContent) }
            if let newAutoInclude { setters.append(autoInclude <- newAutoInclude) }

            guard !setters.isEmpty else { return }
            try db.run(item.update(setters))
        }
    }

    /// Get all context library items
    func getAll() throws -> [ContextLibraryItem] {
        try perform { db in
            let query = table.order(createdAt.desc)
            return try db.prepare(query).map { row in
                ContextLibraryItem(
                    id: row[id],
                    title: row[title],
                    content: row[content],
                    type: ContextLibraryItem.ItemType(rawValue: row[type]) ?? .note,
                    createdAt: Date(timeIntervalSince1970: row[createdAt]),
                    autoInclude: row[autoInclude]
                )
            }
        }
    }

    /// Get items that should be auto-included in context
    func getAutoIncludeItems() throws -> [ContextLibraryItem] {
        try perform { db in
            let query = table.filter(autoInclude == true).order(createdAt.desc)
            return try db.prepare(query).map { row in
                ContextLibraryItem(
                    id: row[id],
                    title: row[title],
                    content: row[content],
                    type: ContextLibraryItem.ItemType(rawValue: row[type]) ?? .note,
                    createdAt: Date(timeIntervalSince1970: row[createdAt]),
                    autoInclude: row[autoInclude]
                )
            }
        }
    }

    /// Get a single item by ID
    func get(id itemId: String) throws -> ContextLibraryItem? {
        try perform { db in
            let query = table.filter(id == itemId)
            guard let row = try db.pluck(query) else { return nil }
            return ContextLibraryItem(
                id: row[id],
                title: row[title],
                content: row[content],
                type: ContextLibraryItem.ItemType(rawValue: row[type]) ?? .note,
                createdAt: Date(timeIntervalSince1970: row[createdAt]),
                autoInclude: row[autoInclude]
            )
        }
    }

    /// Delete an item by ID
    func delete(id itemId: String) throws {
        try perform { db in
            try db.run(table.filter(id == itemId).delete())
        }
    }

    /// Get count of items
    func count() throws -> Int {
        try perform { db in
            try db.scalar(table.count)
        }
    }
}
