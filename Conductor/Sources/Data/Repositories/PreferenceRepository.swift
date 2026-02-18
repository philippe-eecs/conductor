import Foundation
import GRDB

struct PreferenceRepository: Sendable {
    let db: GRDBDatabase

    func set(key: String, value: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)",
                arguments: [key, value]
            )
        }
    }

    func get(key: String) throws -> String? {
        try db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM preferences WHERE key = ?", arguments: [key])
        }
    }

    func delete(key: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM preferences WHERE key = ?", arguments: [key])
        }
    }
}
