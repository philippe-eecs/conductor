import SQLite

struct PreferenceStore: DatabaseStore {
    let database: Database

    private let table = Table("preferences")
    private let key = Expression<String>("key")
    private let value = Expression<String>("value")

    static func createTables(in db: Connection) throws {
        let table = Table("preferences")
        let key = Expression<String>("key")
        let value = Expression<String>("value")

        try db.run(table.create(ifNotExists: true) { t in
            t.column(key, primaryKey: true)
            t.column(value)
        })
    }

    func setPreference(key: String, value: String) throws {
        try perform { db in
            let insert = table.insert(or: .replace,
                self.key <- key,
                self.value <- value
            )
            try db.run(insert)
        }
    }

    func getPreference(key: String) throws -> String? {
        try perform { db in
            let query = table.filter(self.key == key)
            if let row = try db.pluck(query) {
                return row[self.value]
            }
            return nil
        }
    }

    func deletePreference(key: String) throws {
        try perform { db in
            try db.run(table.filter(self.key == key).delete())
        }
    }
}

