// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SQLite3

/// One row per entity, with atomic changes across collections. Payloads preserve
/// the existing Codable schemas; preferences and credentials are not stored here.
actor LocalSQLiteDatabase {
    private let url: URL
    init(url: URL) { self.url = url }

    func needsLegacyImport() throws -> Bool {
        try withDatabase { db in try !hasImported(db) }
    }

    func load(importing legacy: [String: [String: Data]]?) throws -> [String: [String: Data]] {
        try withDatabase { db in
            if let legacy {
                try transaction(db) {
                    if try !hasImported(db) {
                        for (collection, values) in legacy {
                            for (id, payload) in values {
                                try put(db, collection, id, payload)
                            }
                        }
                        // Read back every imported row before marking the import complete.
                        let imported = try read(db)
                        for (collection, values) in legacy {
                            for (id, payload) in values where imported[collection]?[id] != payload {
                                throw failure("Local data migration verification failed.")
                            }
                        }
                        try query(db, "INSERT INTO migrations (id) VALUES ('user-defaults-v1')")
                    }
                }
            }
            return try read(db)
        }
    }

    func commit(_ changes: [(String, String, Data?)]) throws {
        guard !changes.isEmpty else { return }
        try withDatabase { db in
            try transaction(db) {
                for (collection, id, payload) in changes {
                    if let payload { try put(db, collection, id, payload) }
                    else { try query(db, "DELETE FROM records WHERE collection = ? AND id = ?", [collection, id]) }
                }
            }
        }
    }

    private func hasImported(_ db: OpaquePointer) throws -> Bool {
        var found = false
        try query(db, "SELECT id FROM migrations WHERE id = 'user-defaults-v1'") { _ in found = true }
        return found
    }

    private func put(_ db: OpaquePointer, _ collection: String, _ id: String, _ payload: Data) throws {
        try query(db, "INSERT INTO records (collection, id, payload) VALUES (?, ?, ?) ON CONFLICT(collection, id) DO UPDATE SET payload = excluded.payload",
                  [collection, id, String(decoding: payload, as: UTF8.self)])
    }

    private func read(_ db: OpaquePointer) throws -> [String: [String: Data]] {
        var result: [String: [String: Data]] = [:]
        try query(db, "SELECT collection, id, payload FROM records ORDER BY collection, id") { row in
            result[column(row, 0), default: [:]][column(row, 1)] = Data(column(row, 2).utf8)
        }
        return result
    }

    private func transaction(_ db: OpaquePointer, _ operation: () throws -> Void) throws {
        try query(db, "BEGIN IMMEDIATE")
        do {
            try operation()
            try query(db, "COMMIT")
        } catch {
            try? query(db, "ROLLBACK")
            throw error
        }
    }

    private func withDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        let status = sqlite3_open(url.path, &connection)
        guard let db = connection else { throw failure("Could not open the local database.") }
        defer { sqlite3_close(db) }
        guard status == SQLITE_OK else { throw failure(String(cString: sqlite3_errmsg(db))) }
        sqlite3_busy_timeout(db, 3_000)
        var version: Int32 = 0
        try query(db, "PRAGMA user_version") { version = sqlite3_column_int($0, 0) }
        guard version <= 1 else { throw failure("This local database requires a newer version of Commit+.") }
        if version == 0 {
            try transaction(db) {
                try query(db, "CREATE TABLE IF NOT EXISTS records (collection TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY (collection, id))")
                try query(db, "CREATE TABLE IF NOT EXISTS migrations (id TEXT PRIMARY KEY)")
                try query(db, "PRAGMA user_version = 1")
            }
        }
        return try operation(db)
    }

    private func query(_ db: OpaquePointer, _ sql: String, _ values: [String] = [],
                       row: (OpaquePointer) throws -> Void = { _ in }) throws {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK, let statement = prepared else {
            throw failure(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let bytes = value.utf8CString
            let status = bytes.withUnsafeBufferPointer {
                sqlite3_bind_text(statement, Int32(index + 1), $0.baseAddress, Int32($0.count - 1), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard status == SQLITE_OK else { throw failure(String(cString: sqlite3_errmsg(db))) }
        }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            try row(statement)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure(String(cString: sqlite3_errmsg(db))) }
    }

    private func column(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: value, count: Int(sqlite3_column_bytes(statement, index))), as: UTF8.self)
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "LocalSQLiteDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
