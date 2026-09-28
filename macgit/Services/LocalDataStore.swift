// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

/// Only credential-routing metadata stays resident for synchronous callers.
/// Other data is read on demand; SQLite I/O is isolated to LocalSQLiteDatabase.
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
    private let residentCollections: Set<String> = ["providerAccounts", "providerPreferences", "sshPaths"]
    private var records: [String: [String: Data]] = [:]
    var residentCollectionNames: Set<String> { Set(records.keys) }
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
            try await database.prepare(importing: legacy)
            records = try await database.read(collections: residentCollections)
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
        guard residentCollections.contains(collection) else { throw LocalDataError.collectionNotLoaded(collection) }
        return try records[collection]?[id].map { try JSONDecoder().decode(type, from: $0) }
    }

    func values<T: Decodable>(_ type: T.Type, in collection: String) throws -> [String: T] {
        guard isReady else { throw LocalDataError.notReady }
        guard residentCollections.contains(collection) else { throw LocalDataError.collectionNotLoaded(collection) }
        return try (records[collection] ?? [:]).mapValues { try JSONDecoder().decode(type, from: $0) }
    }

    func readValue<T: Decodable>(_ type: T.Type, in collection: String, id: String) async throws -> T? {
        await writer?.value
        try await prepare()
        let data = try await database.value(in: collection, id: id)
        return try data.map { try JSONDecoder().decode(type, from: $0) }
    }

    func readValues<T: Decodable>(_ type: T.Type, in collection: String) async throws -> [String: T] {
        let snapshot = try await snapshot(collections: [collection])
        return try snapshot.values(type, in: collection)
    }

    func snapshot(collections: Set<String>) async throws -> LocalDataTransaction {
        await writer?.value
        try await prepare()
        return LocalDataTransaction(records: try await database.read(collections: collections))
    }

    func transaction<T>(reading collections: Set<String> = [], _ update: @escaping (inout LocalDataTransaction) throws -> T) async throws -> T {
        let previous = writer
        let task = Task { @MainActor in
            await previous?.value
            try await prepare()
            var transaction = LocalDataTransaction(records: try await database.read(collections: collections))
            let result = try update(&transaction)
            try await database.commit(transaction.changes)
            for (collection, id, data) in transaction.changes where residentCollections.contains(collection) {
                records[collection, default: [:]][id] = data
            }
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

