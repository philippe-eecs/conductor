import Foundation
import SQLite

final class Database {
    static let shared = Database()

    private var db: Connection?

    // Tables
    private let messagesTable = Table("messages")
    private let sessionsTable = Table("sessions")
    private let costLogTable = Table("cost_log")
    private let notesTable = Table("notes")
    private let preferencesTable = Table("preferences")

    // Messages columns
    private let id = Expression<String>("id")
    private let role = Expression<String>("role")
    private let content = Expression<String>("content")
    private let timestamp = Expression<Double>("timestamp")
    private let sessionId = Expression<String?>("session_id")

    // Sessions columns
    private let sessId = Expression<String>("id")
    private let sessCreatedAt = Expression<Double>("created_at")
    private let sessLastUsed = Expression<Double>("last_used")
    private let sessTitle = Expression<String>("title")

    // Cost log columns
    private let costTimestamp = Expression<Double>("timestamp")
    private let costAmount = Expression<Double>("amount_usd")
    private let costSessionId = Expression<String?>("session_id")

    // Notes columns
    private let noteId = Expression<String>("id")
    private let noteTitle = Expression<String>("title")
    private let noteContent = Expression<String>("content")
    private let noteCreatedAt = Expression<Double>("created_at")
    private let noteUpdatedAt = Expression<Double>("updated_at")

    // Preferences columns
    private let prefKey = Expression<String>("key")
    private let prefValue = Expression<String>("value")

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        do {
            let dbPath = getDatabasePath()
            db = try Connection(dbPath)

            // Create tables if they don't exist
            try createTables()

            print("Database initialized at: \(dbPath)")
        } catch {
            print("Database initialization failed: \(error)")
        }
    }

    private func getDatabasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let conductorDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: conductorDir, withIntermediateDirectories: true)

        return conductorDir.appendingPathComponent("conductor.db").path
    }

    private func createTables() throws {
        guard let db = db else { return }

        // Messages table
        try db.run(messagesTable.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(role)
            t.column(content)
            t.column(timestamp)
            t.column(sessionId)
        })
        try db.run(messagesTable.createIndex(timestamp, ifNotExists: true))
        // Composite index for session-scoped queries
        try db.run(messagesTable.createIndex(sessionId, timestamp, ifNotExists: true))

        // Sessions table
        try db.run(sessionsTable.create(ifNotExists: true) { t in
            t.column(sessId, primaryKey: true)
            t.column(sessCreatedAt)
            t.column(sessLastUsed)
            t.column(sessTitle)
        })
        try db.run(sessionsTable.createIndex(sessLastUsed, ifNotExists: true))

        // Cost log table
        try db.run(costLogTable.create(ifNotExists: true) { t in
            t.column(costTimestamp)
            t.column(costAmount)
            t.column(costSessionId)
        })
        try db.run(costLogTable.createIndex(costTimestamp, ifNotExists: true))

        // Notes table
        try db.run(notesTable.create(ifNotExists: true) { t in
            t.column(noteId, primaryKey: true)
            t.column(noteTitle)
            t.column(noteContent)
            t.column(noteCreatedAt)
            t.column(noteUpdatedAt)
        })
        try db.run(notesTable.createIndex(noteUpdatedAt, ifNotExists: true))

        // Preferences table
        try db.run(preferencesTable.create(ifNotExists: true) { t in
            t.column(prefKey, primaryKey: true)
            t.column(prefValue)
        })
    }

    // MARK: - Messages

    func saveMessage(_ message: ChatMessage, forSession session: String? = nil) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        let insert = messagesTable.insert(or: .replace,
            id <- message.id.uuidString,
            role <- message.role.rawValue,
            content <- message.content,
            timestamp <- message.timestamp.timeIntervalSince1970,
            sessionId <- session
        )

        try db.run(insert)
    }

    func loadRecentMessages(limit: Int = 50, forSession session: String? = nil) throws -> [ChatMessage] {
        guard let db = db else { throw DatabaseError.notInitialized }

        // Order by DESC to get newest first, then reverse to get chronological order
        // This ensures we get the N most recent messages, not the N oldest
        var query: Table
        if let session = session {
            query = messagesTable.filter(sessionId == session).order(timestamp.desc).limit(limit)
        } else {
            query = messagesTable.order(timestamp.desc).limit(limit)
        }

        var messages: [ChatMessage] = []

        for row in try db.prepare(query) {
            if let messageRole = ChatMessage.Role(rawValue: row[role]),
               let uuid = UUID(uuidString: row[id]) {
                let message = ChatMessage(
                    id: uuid,
                    role: messageRole,
                    content: row[content],
                    timestamp: Date(timeIntervalSince1970: row[timestamp])
                )
                messages.append(message)
            }
        }

        // Reverse to get chronological order (oldest first within the recent set)
        return messages.reversed()
    }

    func clearMessages(forSession session: String? = nil) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        if let session = session {
            try db.run(messagesTable.filter(sessionId == session).delete())
        } else {
            try db.run(messagesTable.delete())
        }
    }

    /// Updates messages with NULL session_id to associate them with a session.
    /// This is used when a session is created after the first message is saved.
    func associateOrphanedMessages(withSession session: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        // Find messages with no session that were created recently (within last minute)
        // and associate them with the new session
        let oneMinuteAgo = Date().addingTimeInterval(-60).timeIntervalSince1970
        let orphanedMessages = messagesTable
            .filter(sessionId == nil)
            .filter(timestamp >= oneMinuteAgo)

        try db.run(orphanedMessages.update(sessionId <- session))
    }

    // MARK: - Sessions

    func saveSession(id sessionIdValue: String, title: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        let now = Date().timeIntervalSince1970

        // Try to update existing session
        let existingSession = sessionsTable.filter(sessId == sessionIdValue)
        let updateCount = try db.run(existingSession.update(
            sessLastUsed <- now,
            sessTitle <- title
        ))

        // If no rows updated, insert new session
        if updateCount == 0 {
            let insert = sessionsTable.insert(
                sessId <- sessionIdValue,
                sessCreatedAt <- now,
                sessLastUsed <- now,
                sessTitle <- title
            )
            try db.run(insert)
        }
    }

    func getRecentSessions(limit: Int = 20) throws -> [Session] {
        guard let db = db else { throw DatabaseError.notInitialized }

        let query = sessionsTable.order(sessLastUsed.desc).limit(limit)

        var sessions: [Session] = []

        for row in try db.prepare(query) {
            sessions.append(Session(
                id: row[sessId],
                createdAt: Date(timeIntervalSince1970: row[sessCreatedAt]),
                lastUsed: Date(timeIntervalSince1970: row[sessLastUsed]),
                title: row[sessTitle]
            ))
        }

        return sessions
    }

    func deleteSession(id sessionIdValue: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        // Delete session
        try db.run(sessionsTable.filter(sessId == sessionIdValue).delete())

        // Delete associated messages
        try db.run(messagesTable.filter(sessionId == sessionIdValue).delete())

        // Delete associated cost logs
        try db.run(costLogTable.filter(costSessionId == sessionIdValue).delete())
    }

    // MARK: - Cost Tracking

    func logCost(amount: Double, sessionId session: String?) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        let insert = costLogTable.insert(
            costTimestamp <- Date().timeIntervalSince1970,
            costAmount <- amount,
            costSessionId <- session
        )

        try db.run(insert)
    }

    func getTotalCost(since date: Date) throws -> Double {
        guard let db = db else { throw DatabaseError.notInitialized }

        let query = costLogTable
            .filter(costTimestamp >= date.timeIntervalSince1970)
            .select(costAmount.sum)

        if let row = try db.pluck(query) {
            return row[costAmount.sum] ?? 0
        }

        return 0
    }

    func getDailyCost() throws -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return try getTotalCost(since: startOfDay)
    }

    func getWeeklyCost() throws -> Double {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return try getTotalCost(since: startOfWeek)
    }

    func getMonthlyCost() throws -> Double {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        return try getTotalCost(since: startOfMonth)
    }

    func getCostHistory(days: Int = 30) throws -> [(date: Date, amount: Double)] {
        guard let db = db else { throw DatabaseError.notInitialized }

        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!

        let query = costLogTable
            .filter(costTimestamp >= startDate.timeIntervalSince1970)
            .order(costTimestamp.asc)

        var history: [(date: Date, amount: Double)] = []

        for row in try db.prepare(query) {
            history.append((
                date: Date(timeIntervalSince1970: row[costTimestamp]),
                amount: row[costAmount]
            ))
        }

        return history
    }

    // MARK: - Notes

    func saveNote(title: String, content: String) throws -> String {
        guard let db = db else { throw DatabaseError.notInitialized }

        let noteIdValue = UUID().uuidString
        let now = Date().timeIntervalSince1970

        let insert = notesTable.insert(
            noteId <- noteIdValue,
            noteTitle <- title,
            noteContent <- content,
            noteCreatedAt <- now,
            noteUpdatedAt <- now
        )

        try db.run(insert)
        return noteIdValue
    }

    func updateNote(id: String, title: String? = nil, content: String? = nil) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        let note = notesTable.filter(noteId == id)
        var setters: [Setter] = [noteUpdatedAt <- Date().timeIntervalSince1970]

        if let title = title {
            setters.append(noteTitle <- title)
        }
        if let content = content {
            setters.append(noteContent <- content)
        }

        try db.run(note.update(setters))
    }

    func loadNotes(limit: Int = 20) throws -> [(id: String, title: String, content: String)] {
        guard let db = db else { throw DatabaseError.notInitialized }

        let query = notesTable
            .order(noteUpdatedAt.desc)
            .limit(limit)

        var notes: [(id: String, title: String, content: String)] = []

        for row in try db.prepare(query) {
            notes.append((
                id: row[noteId],
                title: row[noteTitle],
                content: row[noteContent]
            ))
        }

        return notes
    }

    func deleteNote(id: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        let note = notesTable.filter(noteId == id)
        try db.run(note.delete())
    }

    // MARK: - Preferences

    func setPreference(key: String, value: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }

        let insert = preferencesTable.insert(or: .replace,
            prefKey <- key,
            prefValue <- value
        )

        try db.run(insert)
    }

    func getPreference(key: String) throws -> String? {
        guard let db = db else { throw DatabaseError.notInitialized }

        let query = preferencesTable.filter(prefKey == key)

        if let row = try db.pluck(query) {
            return row[prefValue]
        }

        return nil
    }

    func deletePreference(key: String) throws {
        guard let db = db else { throw DatabaseError.notInitialized }
        let pref = preferencesTable.filter(prefKey == key)
        try db.run(pref.delete())
    }
}

// MARK: - Models

struct Session: Identifiable {
    let id: String
    let createdAt: Date
    let lastUsed: Date
    let title: String

    var formattedLastUsed: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUsed, relativeTo: Date())
    }
}

// MARK: - Errors

enum DatabaseError: LocalizedError {
    case notInitialized
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database not initialized"
        case .invalidData:
            return "Invalid data format"
        }
    }
}
