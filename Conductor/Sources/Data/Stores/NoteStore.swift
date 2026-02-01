import Foundation
import SQLite

struct NoteStore: DatabaseStore {
    let database: Database

    private let table = Table("notes")
    private let id = Expression<String>("id")
    private let title = Expression<String>("title")
    private let content = Expression<String>("content")
    private let createdAt = Expression<Double>("created_at")
    private let updatedAt = Expression<Double>("updated_at")

    static func createTables(in db: Connection) throws {
        let table = Table("notes")
        let id = Expression<String>("id")
        let title = Expression<String>("title")
        let content = Expression<String>("content")
        let createdAt = Expression<Double>("created_at")
        let updatedAt = Expression<Double>("updated_at")

        try db.run(table.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(title)
            t.column(content)
            t.column(createdAt)
            t.column(updatedAt)
        })
        try db.run(table.createIndex(updatedAt, ifNotExists: true))
    }

    func saveNote(title: String, content: String) throws -> String {
        try perform { db in
            let noteId = UUID().uuidString
            let now = Date().timeIntervalSince1970

            let insert = table.insert(
                id <- noteId,
                self.title <- title,
                self.content <- content,
                createdAt <- now,
                updatedAt <- now
            )
            try db.run(insert)
            return noteId
        }
    }

    func updateNote(id: String, title: String? = nil, content: String? = nil) throws {
        try perform { db in
            let note = table.filter(self.id == id)
            var setters: [Setter] = [updatedAt <- Date().timeIntervalSince1970]

            if let title { setters.append(self.title <- title) }
            if let content { setters.append(self.content <- content) }

            try db.run(note.update(setters))
        }
    }

    func loadNotes(limit: Int = 20) throws -> [(id: String, title: String, content: String)] {
        try perform { db in
            let query = table.order(updatedAt.desc).limit(limit)
            var notes: [(id: String, title: String, content: String)] = []

            for row in try db.prepare(query) {
                notes.append((id: row[id], title: row[title], content: row[content]))
            }

            return notes
        }
    }

    func deleteNote(id: String) throws {
        try perform { db in
            try db.run(table.filter(self.id == id).delete())
        }
    }
}

