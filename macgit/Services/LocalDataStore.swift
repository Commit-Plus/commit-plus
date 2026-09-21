// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

/// UI reads use this snapshot. SQLite I/O is isolated to LocalSQLiteDatabase.
/// All writers share one queue, including transactions spanning several stores.
@MainActor
final class LocalDataStore: ObservableObject {
    static let shared: LocalDataStore = {
        // XCTest hosts must never migrate or mutate the user's real database.
        if FirebaseBootstrap.isRunningUnitTests {
            let id = UUID().uuidString
            return LocalDataStore(
                databaseURL: FileManager.default.temporaryDirectory.appending(path: "CommitPlusTests-\(id)/store.sqlite"),
                userDefaults: UserDefaults(suiteName: "CommitPlusTests.\(id)")!
            )
        }
        return LocalDataStore()
    }()
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    private let database: LocalSQLiteDatabase
    private let defaults: UserDefaults
    private var records: [String: [String: Data]] = [:]
    private var loading: Task<Void, Error>?
    private var writer: Task<Void, Never>?

    init(databaseURL: URL = URL.applicationSupportDirectory.appending(path: "Commit+/LocalData/store.sqlite"),
         userDefaults: UserDefaults = .standard) {
        database = LocalSQLiteDatabase(url: databaseURL)
        defaults = userDefaults
    }

    func prepare() async throws {
        if isReady { return }
        if let loading { return try await loading.value }
        let task = Task { @MainActor in
            let needsImport = try await database.needsLegacyImport()
            let legacy = needsImport ? try LegacyLocalDataMigration.records(from: defaults) : nil
            records = try await database.load(importing: legacy)
            isReady = true
            errorMessage = nil
        }
        loading = task
        do {
            try await task.value
            loading = nil
        } catch {
            loading = nil
            errorMessage = "Could not open local data: \(error.localizedDescription)"
            throw error
        }
    }

    func value<T: Decodable>(_ type: T.Type, in collection: String, id: String) throws -> T? {
        guard isReady else { throw LocalDataError.notReady }
        return try records[collection]?[id].map { try JSONDecoder().decode(type, from: $0) }
    }

    func values<T: Decodable>(_ type: T.Type, in collection: String) throws -> [String: T] {
        guard isReady else { throw LocalDataError.notReady }
        return try (records[collection] ?? [:]).mapValues { try JSONDecoder().decode(type, from: $0) }
    }

    func transaction<T>(_ update: @escaping (inout LocalDataTransaction) throws -> T) async throws -> T {
        let previous = writer
        let task = Task { @MainActor in
            await previous?.value
            try await prepare()
            var transaction = LocalDataTransaction(records: records)
            let result = try update(&transaction)
            try await database.commit(transaction.changes)
            records = transaction.records
            return result
        }
        writer = Task { _ = try? await task.value }
        do { return try await task.value }
        catch {
            errorMessage = "Could not save local data: \(error.localizedDescription)"
            throw error
        }
    }
}

