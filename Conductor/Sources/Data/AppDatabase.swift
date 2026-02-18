import Foundation
import GRDB

final class AppDatabase: Sendable {
    let dbQueue: DatabaseQueue

    static let shared: AppDatabase = {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let conductorDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)
            try FileManager.default.createDirectory(at: conductorDir, withIntermediateDirectories: true)
            let dbPath = conductorDir.appendingPathComponent("conductor-v2.db").path
            Log.database.info("Database path: \(dbPath, privacy: .public)")
            return try AppDatabase(path: dbPath)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }()

    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            db.trace { Log.database.debug("\($0, privacy: .public)") }
        }

        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try migrate()
    }

    /// In-memory database for testing
    init() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "projects") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("color", .text).notNull().defaults(to: "#007AFF")
                t.column("description", .text)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "todos") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("dueDate", .datetime)
                t.column("completed", .boolean).notNull().defaults(to: false)
                t.column("completedAt", .datetime)
                t.column("projectId", .integer).references("projects", onDelete: .setNull)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "deliverables") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("filePath", .text)
                t.column("url", .text)
                t.column("verified", .boolean).notNull().defaults(to: false)
                t.column("verifiedAt", .datetime)
                t.column("projectId", .integer).references("projects", onDelete: .setNull)
                t.column("todoId", .integer).references("todos", onDelete: .setNull)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "blink_logs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("decision", .text).notNull()
                t.column("contextSummary", .text).notNull()
                t.column("notificationTitle", .text)
                t.column("notificationBody", .text)
                t.column("agentTodoId", .integer)
                t.column("agentPrompt", .text)
                t.column("costUsd", .double)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "agent_runs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("todoId", .integer).references("todos", onDelete: .setNull)
                t.column("prompt", .text).notNull()
                t.column("status", .text).notNull()
                t.column("output", .text)
                t.column("costUsd", .double)
                t.column("startedAt", .datetime).notNull()
                t.column("completedAt", .datetime)
            }

            try db.create(table: "messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("sessionId", .text)
                t.column("costUsd", .double)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "preferences") { t in
                t.column("key", .text).notNull().primaryKey()
                t.column("value", .text).notNull()
            }
        }

        try migrator.migrate(dbQueue)
    }
}
