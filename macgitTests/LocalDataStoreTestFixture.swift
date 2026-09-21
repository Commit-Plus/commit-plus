// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
@testable import macgit

@MainActor
final class LocalDataStoreTestFixture {
    let directory: URL
    let defaults: UserDefaults
    let suite: String
    let store: LocalDataStore
    var databaseURL: URL { directory.appendingPathComponent("store.sqlite") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("local-data-tests-\(UUID())")
        suite = "LocalDataStoreTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        store = LocalDataStore(databaseURL: directory.appendingPathComponent("store.sqlite"), userDefaults: defaults)
    }

    func reopen() async throws -> LocalDataStore {
        let reopened = LocalDataStore(databaseURL: databaseURL, userDefaults: defaults)
        try await reopened.prepare()
        return reopened
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
