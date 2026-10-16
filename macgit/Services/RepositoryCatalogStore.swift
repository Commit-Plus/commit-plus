// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

/// One local catalog owner. Writes are serialized with bootstrap and committed atomically.
@MainActor
final class RepositoryCatalogStore: ObservableObject {
    static let shared = RepositoryCatalogStore()
    @Published private(set) var snapshot = RepositoryCatalogSnapshot() {
        didSet { recordsByPath = Dictionary(uniqueKeysWithValues: snapshot.repositories.map { ($0.path, $0) }) }
    }
    private(set) var recordsByPath: [String: RepositoryCatalogSnapshot.Repository] = [:]
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    private let dataStore: LocalDataStore
    private static let collections: Set<String> = ["repositoryCatalog", "repositoryScanRoots", "repositoryRootMemberships", "repositoryRecents", "repositoryCatalogMigrations"]
    private var writer: Task<Void, Never>?

    init(dataStore injectedStore: LocalDataStore? = nil, defaults: UserDefaults = .standard) {
        let dataStore = injectedStore ?? .shared
        self.dataStore = dataStore
        let legacyRecents = defaults.data(forKey: "dev.thanhtran.macgit.recentRepositories")
        let decodedRecents = legacyRecents.flatMap { try? JSONDecoder().decode([RecentRepository].self, from: $0) }
        let invalidRecents = defaults.object(forKey: "dev.thanhtran.macgit.recentRepositories") != nil && decodedRecents == nil
        let legacyRoots = defaults.stringArray(forKey: "dev.thanhtran.macgit.yourRepositoryFolders") ?? []
        let invalidRoots = defaults.object(forKey: "dev.thanhtran.macgit.yourRepositoryFolders") != nil
            && defaults.stringArray(forKey: "dev.thanhtran.macgit.yourRepositoryFolders") == nil
        var seed = RepositoryCatalogSnapshot()
        if let recents = decodedRecents {
            for recent in recents.sorted(by: { $0.lastOpened < $1.lastOpened }) {
                let index = seed.ensureRepository(recent.url)
                seed.repositories[index].name = recent.name
                seed.repositories[index].lastOpened = recent.lastOpened
            }
        }
        for path in legacyRoots {
            let canonical = RepositoryCatalogSnapshot.path(URL(fileURLWithPath: path))
            if !seed.roots.contains(where: { $0.path == canonical }) {
                seed.roots.append(.init(path: canonical))
            }
        }
        writer = Task { [weak self, seed] in
            guard let self else { return }
            defer { isReady = true }
            do {
                let loaded = try await dataStore.transaction(reading: Self.collections) { transaction in
                    if try transaction.value(Bool.self, in: "repositoryCatalogMigrations", id: "user-defaults-v1") == true {
                        return (snapshot: try Self.readSnapshot(transaction), skippedLegacyData: false)
                    }
                    try Self.persist(seed, previous: .init(), in: &transaction)
                    // Verify the encoded import before committing the marker in the same transaction.
                    let verified = try Self.readSnapshot(transaction)
                    guard verified.repositories.sorted(by: { $0.id.uuidString < $1.id.uuidString }) == seed.repositories.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
                          verified.roots.sorted(by: { $0.path < $1.path }) == seed.roots.sorted(by: { $0.path < $1.path }) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try transaction.set(true, in: "repositoryCatalogMigrations", id: "user-defaults-v1")
                    return (snapshot: verified, skippedLegacyData: invalidRoots || invalidRecents)
                }
                if snapshot != loaded.snapshot { snapshot = loaded.snapshot }
                if loaded.skippedLegacyData {
                    errorMessage = "Some legacy repository data could not be imported. The original data has been kept for recovery."
                }
            } catch {
                snapshot = seed
                errorMessage = error.localizedDescription
            }
        }
    }

    func ready() async { await writer?.value }

    func record(for url: URL) -> RepositoryCatalogSnapshot.Repository? { recordsByPath[RepositoryCatalogSnapshot.path(url)] }

    func open(_ url: URL) {
        update { state in
            let index = state.ensureRepository(url)
            state.repositories[index].lastOpened = .now
            let recentIDs = Set(state.repositories.filter { $0.lastOpened != nil }
                .sorted { $0.lastOpened! > $1.lastOpened! }.prefix(20).map(\.id))
            for index in state.repositories.indices where !recentIDs.contains(state.repositories[index].id) {
                state.repositories[index].lastOpened = nil
            }
        }
    }

    func removeRecent(_ paths: Set<String>) {
        update { state in
            for index in state.repositories.indices where paths.contains(state.repositories[index].path) {
                state.repositories[index].lastOpened = nil
            }
        }
    }

    func addRoots(_ urls: [URL]) {
        update { state in
            for url in urls {
                let path = RepositoryCatalogSnapshot.path(url)
                if !state.roots.contains(where: { $0.path == path }) { state.roots.append(.init(path: path)) }
            }
        }
    }

    func removeRoot(_ url: URL) {
        update { state in
            let ids = Set(state.roots.filter { $0.path == RepositoryCatalogSnapshot.path(url) }.map(\.id))
            state.roots.removeAll { ids.contains($0.id) }
            state.memberships.removeAll { ids.contains($0.rootID) }
        }
    }

    /// Called only after the existing folder validation succeeds.
    func relink(_ oldURL: URL, to newURL: URL) {
        update { state in
            guard let original = state.repositories.first(where: { $0.path == RepositoryCatalogSnapshot.path(oldURL) }) else { return }
            let newPath = RepositoryCatalogSnapshot.path(newURL)
            if let duplicate = state.repositories.first(where: { $0.path == newPath && $0.id != original.id }) {
                state.repositories.removeAll { $0.id == duplicate.id }
                for index in state.memberships.indices where state.memberships[index].repositoryID == duplicate.id {
                    state.memberships[index].repositoryID = original.id
                }
                var seen: Set<String> = []
                state.memberships.removeAll { !seen.insert($0.rootID.uuidString + $0.repositoryID.uuidString).inserted }
            }
            guard let oldIndex = state.repositories.firstIndex(where: { $0.id == original.id }) else { return }
            state.repositories[oldIndex].path = newPath
            state.repositories[oldIndex].name = newURL.lastPathComponent
            state.repositories[oldIndex].lastOpened = .now
            let id = state.repositories[oldIndex].id
            state.memberships.removeAll { membership in
                guard membership.repositoryID == id else { return false }
                guard let root = state.roots.first(where: { $0.id == membership.rootID }) else { return true }
                return newPath != root.path && !newPath.hasPrefix(root.path + "/")
            }
        }
    }

    func reconcile(root url: URL, repositories: [URL], error: String?) async {
        update { state in
            guard let rootIndex = state.roots.firstIndex(where: { $0.path == RepositoryCatalogSnapshot.path(url) }) else { return }
            state.roots[rootIndex].error = error
            let rootID = state.roots[rootIndex].id
            if error == nil {
                state.roots[rootIndex].scannedAt = .now
                state.memberships.removeAll { $0.rootID == rootID }
            }
            for url in repositories {
                let index = state.ensureRepository(url)
                state.repositories[index].lastSeen = .now
                let membership = RepositoryCatalogSnapshot.Membership(rootID: rootID, repositoryID: state.repositories[index].id)
                if !state.memberships.contains(membership) { state.memberships.append(membership) }
            }
        }
        await ready()
    }

    func setProvider(_ provider: String, bookmarkKey: String?, for url: URL) {
        if let record = snapshot.repositories.first(where: { $0.path == RepositoryCatalogSnapshot.path(url) }), record.provider == provider, record.bookmarkKey == bookmarkKey { return }
        update { state in
            let index = state.ensureRepository(url)
            state.repositories[index].provider = provider
            state.repositories[index].bookmarkKey = bookmarkKey
        }
    }

    private func update(_ mutation: @escaping (inout RepositoryCatalogSnapshot) -> Void) {
        let previous = writer
        writer = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let result = try await dataStore.transaction(reading: Self.collections) { transaction in
                    guard try transaction.value(Bool.self, in: "repositoryCatalogMigrations", id: "user-defaults-v1") == true else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    var state = try Self.readSnapshot(transaction)
                    let old = state
                    mutation(&state)
                    let recentIDs = Set(state.repositories.filter { $0.lastOpened != nil }
                        .sorted { $0.lastOpened! > $1.lastOpened! }.prefix(20).map(\.id))
                    for index in state.repositories.indices where !recentIDs.contains(state.repositories[index].id) {
                        state.repositories[index].lastOpened = nil
                    }
                    if state != old { try Self.persist(state, previous: old, in: &transaction) }
                    return try Self.readSnapshot(transaction)
                }
                if snapshot != result { snapshot = result }
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private static func readSnapshot(_ transaction: LocalDataTransaction) throws -> RepositoryCatalogSnapshot {
        let recents = try transaction.values(Date.self, in: "repositoryRecents")
        let repositories = try transaction.values(RepositoryCatalogSnapshot.Repository.self, in: "repositoryCatalog").values
            .map { record in
                var record = record
                record.lastOpened = recents[record.id.uuidString]
                return record
            }.sorted { $0.id.uuidString < $1.id.uuidString }
        let roots = try transaction.values(RepositoryCatalogSnapshot.Root.self, in: "repositoryScanRoots").values.sorted { $0.path < $1.path }
        let memberships = try transaction.values(RepositoryCatalogSnapshot.Membership.self, in: "repositoryRootMemberships").values
            .sorted { $0.rootID.uuidString + $0.repositoryID.uuidString < $1.rootID.uuidString + $1.repositoryID.uuidString }
        return .init(repositories: repositories, roots: roots, memberships: memberships)
    }

    private static func persist(_ state: RepositoryCatalogSnapshot, previous: RepositoryCatalogSnapshot, in transaction: inout LocalDataTransaction) throws {
        for removed in previous.repositories where !state.repositories.contains(where: { $0.id == removed.id }) {
            transaction.remove(in: "repositoryCatalog", id: removed.id.uuidString)
            transaction.remove(in: "repositoryRecents", id: removed.id.uuidString)
        }
        for record in state.repositories {
            var metadata = record
            metadata.lastOpened = nil
            var old = previous.repositories.first { $0.id == record.id }
            let lastOpened = old?.lastOpened
            old?.lastOpened = nil
            if metadata != old { try transaction.set(metadata, in: "repositoryCatalog", id: record.id.uuidString) }
            if lastOpened != record.lastOpened {
                if let date = record.lastOpened { try transaction.set(date, in: "repositoryRecents", id: record.id.uuidString) }
                else { transaction.remove(in: "repositoryRecents", id: record.id.uuidString) }
            }
        }
        for root in state.roots where previous.roots.first(where: { $0.id == root.id }) != root {
            try transaction.set(root, in: "repositoryScanRoots", id: root.id.uuidString)
        }
        for root in previous.roots where !state.roots.contains(where: { $0.id == root.id }) {
            transaction.remove(in: "repositoryScanRoots", id: root.id.uuidString)
        }
        for membership in state.memberships where !previous.memberships.contains(membership) {
            try transaction.set(membership, in: "repositoryRootMemberships", id: membership.rootID.uuidString + "/" + membership.repositoryID.uuidString)
        }
        for membership in previous.memberships where !state.memberships.contains(membership) {
            transaction.remove(in: "repositoryRootMemberships", id: membership.rootID.uuidString + "/" + membership.repositoryID.uuidString)
        }
    }
}
