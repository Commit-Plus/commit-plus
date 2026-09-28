// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import SQLite3

/// Disposable, bounded cache. Payloads are queried individually, never mirrored in RAM.
actor PullRequestDiskCache {
    static let shared: PullRequestDiskCache = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil {
            return PullRequestDiskCache(url: FileManager.default.temporaryDirectory
                .appending(path: "PRCacheTestSession-\(UUID().uuidString).sqlite"))
        }
        return PullRequestDiskCache()
    }()
    private let url: URL
    private let maximumBytes: Int
    private let maximumEntryBytes: Int
    private var epoch = UUID()

    init(url: URL = URL.cachesDirectory.appending(path: "dev.thanhtran.macgit/pull-requests-v1.sqlite"),
         maximumBytes: Int = 32 * 1024 * 1024, maximumEntryBytes: Int = 2 * 1024 * 1024) {
        self.url = url
        self.maximumBytes = maximumBytes
        self.maximumEntryBytes = maximumEntryBytes
    }

    func generation() -> UUID { epoch }

    func value<T: Decodable & Sendable>(_ type: T.Type, key: String, generation: UUID,
                                       now: Date = .now) -> T? {
        guard generation == epoch else { return nil }
        return try? database { db in
            var result: T?
            try query(db, "SELECT payload FROM entries WHERE key = ? AND expires > ?", [key, String(now.timeIntervalSince1970)]) { statement in
                let count = Int(sqlite3_column_bytes(statement, 0))
                guard count <= maximumEntryBytes, let bytes = sqlite3_column_blob(statement, 0) else { return }
                result = try? JSONDecoder().decode(type, from: Data(bytes: bytes, count: count))
            }
            if result != nil {
                try query(db, "UPDATE entries SET accessed = ? WHERE key = ?", [String(now.timeIntervalSince1970), key])
            } else {
                try query(db, "DELETE FROM entries WHERE key = ?", [key])
            }
            return result
        }
    }

    func save<T: Encodable & Sendable>(_ value: T, key: String, accountID: String,
                                      kind: String, number: Int = 0, ttl: TimeInterval,
                                      generation: UUID, now: Date = .now) {
        guard generation == epoch else { return }
        guard let data = try? JSONEncoder().encode(value),
              data.count <= min(maximumEntryBytes, maximumBytes) else {
            try? database { db in try query(db, "DELETE FROM entries WHERE key = ?", [key]) }
            return
        }
        try? database { db in
            try query(db, "BEGIN IMMEDIATE")
            do {
                try query(db, "DELETE FROM entries WHERE expires <= ?", [String(now.timeIntervalSince1970)])
                try query(db, "INSERT OR REPLACE INTO entries (key, account, kind, number, expires, accessed, payload) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    [key, accountID, kind, String(number), String(now.addingTimeInterval(ttl).timeIntervalSince1970),
                     String(now.timeIntervalSince1970), String(decoding: data, as: UTF8.self)])
                var size = 0
                var count = 0
                try query(db, "SELECT COALESCE(SUM(length(CAST(payload AS BLOB))), 0), COUNT(*) FROM entries") {
                    size = Int(sqlite3_column_int64($0, 0)); count = Int(sqlite3_column_int64($0, 1))
                }
                while size > maximumBytes || count > 300 {
                    var oldestKey: String?
                    var bytes = 0
                    try query(db, "SELECT key, length(CAST(payload AS BLOB)) FROM entries ORDER BY accessed, key LIMIT 1") {
                        oldestKey = String(cString: sqlite3_column_text($0, 0))
                        bytes = Int(sqlite3_column_int64($0, 1))
                    }
                    guard let oldestKey else { break }
                    try query(db, "DELETE FROM entries WHERE key = ?", [oldestKey])
                    size -= bytes; count -= 1
                }
                try query(db, "COMMIT")
            } catch {
                try? query(db, "ROLLBACK")
                throw error
            }
        }
    }

    /// Bumping the epoch also prevents already-running network requests from repopulating removed data.
    func remove(accountID: String? = nil, kind: String? = nil, number: Int? = nil) {
        epoch = UUID()
        do {
            try database { db in
                var clauses: [String] = []
                var values: [String] = []
                if let accountID { clauses.append("account = ?"); values.append(accountID) }
                if let kind { clauses.append("kind = ?"); values.append(kind) }
                if let number { clauses.append("number = ?"); values.append(String(number)) }
                try query(db, "DELETE FROM entries" + (clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")), values)
            }
        } catch {
            // A corrupt disposable cache must still be removable on logout/Clear Cache.
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-journal")
        }
    }

    private func database<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK, let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(db) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        sqlite3_busy_timeout(db, 500)
        try query(db, "PRAGMA auto_vacuum = FULL")
        try query(db, "PRAGMA max_page_count = 10240")
        var version = 0
        try query(db, "PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
        guard version <= 1 else { throw CocoaError(.fileReadCorruptFile) }
        try query(db, "CREATE TABLE IF NOT EXISTS entries (key TEXT PRIMARY KEY, account TEXT NOT NULL, kind TEXT NOT NULL, number INTEGER NOT NULL, expires REAL NOT NULL, accessed REAL NOT NULL, payload TEXT NOT NULL)")
        if version == 0 { try query(db, "PRAGMA user_version = 1") }
        return try operation(db)
    }

    private func query(_ db: OpaquePointer, _ sql: String, _ values: [String] = [],
                       row: (OpaquePointer) throws -> Void = { _ in }) throws {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK, let statement = prepared else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let status = value.withCString {
                sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard status == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW { try row(statement); status = sqlite3_step(statement) }
        guard status == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown) }
    }
}
