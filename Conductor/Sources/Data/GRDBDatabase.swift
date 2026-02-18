import Foundation
import GRDB
import os

final class GRDBDatabase: Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        var migrator = DatabaseMigrator()
        InitialSchema.register(in: &migrator)
        try migrator.migrate(dbQueue)
    }

    /// Production initializer — opens or creates the database at the standard path.
    convenience init() throws {
        let dbPath = Self.databasePath()
        var config = Configuration()
        config.prepareDatabase { db in
            // WAL mode for concurrent readers
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
        try self.init(dbQueue: dbQueue)
        Log.database.info("GRDB database initialized at: \(dbPath, privacy: .public)")
    }

    /// Test initializer — in-memory database.
    convenience init(inMemory: Bool) throws {
        precondition(inMemory)
        let dbQueue = try DatabaseQueue(configuration: Configuration())
        try self.init(dbQueue: dbQueue)
    }

    // MARK: - Path

    static func databasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let conductorDir = appSupport.appendingPathComponent("Conductor", isDirectory: true)
        try? FileManager.default.createDirectory(at: conductorDir, withIntermediateDirectories: true)
        return conductorDir.appendingPathComponent("conductor.db").path
    }

    // MARK: - Convenience

    func read<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func write<T>(_ block: (GRDB.Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }
}
