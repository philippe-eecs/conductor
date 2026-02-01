import SQLite

protocol DatabaseStore {
    var database: Database { get }
}

extension DatabaseStore {
    @discardableResult
    func perform<T>(_ body: (Connection) throws -> T) throws -> T {
        try database.perform(body)
    }
}

