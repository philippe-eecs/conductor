import Foundation
import GRDB

struct PreferenceRepository {
    let db: AppDatabase

    func get(_ key: String) throws -> String? {
        try db.dbQueue.read { db in
            try Preference.fetchOne(db, key: key)?.value
        }
    }

    func set(_ key: String, value: String) throws {
        try db.dbQueue.write { db in
            try Preference(key: key, value: value).save(db)
        }
    }

    func delete(_ key: String) throws {
        try db.dbQueue.write { db in
            _ = try Preference.deleteOne(db, key: key)
        }
    }

    func getBool(_ key: String, default defaultValue: Bool = false) throws -> Bool {
        guard let value = try get(key) else { return defaultValue }
        return value == "true" || value == "1"
    }

    func setBool(_ key: String, value: Bool) throws {
        try set(key, value: value ? "true" : "false")
    }

    func getInt(_ key: String, default defaultValue: Int = 0) throws -> Int {
        guard let value = try get(key) else { return defaultValue }
        return Int(value) ?? defaultValue
    }

    func setInt(_ key: String, value: Int) throws {
        try set(key, value: String(value))
    }
}
