// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Combine

@MainActor
final class RepositoryCommitRuleSyncController: ObservableObject {
    private let dataStore: LocalDataStore
    private let localStore: RepoSettingsStore
    private let resolver: any RepositoryRemoteIdentityResolving
    private var sessionID = UUID()
    private var activeUID: String?
    private var activePath: String?
    private var runningSessions: Set<UUID> = []

    init(localStore: RepoSettingsStore = .shared,
         resolver: any RepositoryRemoteIdentityResolving = RepositoryRemoteIdentityResolver()) {
        self.dataStore = localStore.dataStore
        self.localStore = localStore
        self.resolver = resolver
    }

    func setSession(uid: String?, repositoryURL: URL) {
        guard activeUID != uid || activePath != repositoryURL.path else { return }
        activeUID = uid
        activePath = repositoryURL.path
        sessionID = UUID()
    }

    func markChanged(_ value: Bool, uid: String?, repositoryURL: URL) async throws {
        guard let uid else { return }
        let id = key(uid: uid, path: repositoryURL.path)
        try await dataStore.transaction { transaction in
            try transaction.set(value, in: "commitRulePending", id: id)
        }
    }

    func reconcile(repositoryURL: URL, uid: String?, cloud: any RepositoryCommitRuleCloudStore,
                   onApplied: (Bool) -> Void) async -> String? {
        setSession(uid: uid, repositoryURL: repositoryURL)
        guard let uid else { return nil }
        let session = sessionID
        guard runningSessions.insert(session).inserted else { return nil }
        defer { runningSessions.remove(session) }
        let pendingID = key(uid: uid, path: repositoryURL.path)
        guard let identity = await resolver.identity(in: repositoryURL), session == sessionID else { return nil }
        do {
            try await dataStore.prepare()
            guard session == sessionID else { return nil }
            let initial = localValue(repositoryURL)
            let remote = try await cloud.load(identity: identity, uid: uid)
            guard session == sessionID else { return nil }
            // Edits made while offline or while loading always win over an older download.
            if pendingValues[pendingID] == nil, let remote {
                let applied = try await dataStore.transaction { transaction in
                    guard session == self.sessionID,
                          try transaction.value(Bool.self, in: "commitRulePending", id: pendingID) == nil else { return false }
                    var settings = try transaction.value(RepoSettings.self, in: "repoSettings", id: repositoryURL.path)
                        ?? RepoSettings.defaults(currentBranch: nil, remotes: [])
                    guard settings.skipProtectedBranchCommitWarnings == initial else { return false }
                    settings.skipProtectedBranchCommitWarnings = remote
                    try transaction.set(settings, in: "repoSettings", id: repositoryURL.path)
                    return true
                }
                if applied, session == sessionID, pendingValues[pendingID] == nil, localValue(repositoryURL) == remote {
                    onApplied(remote)
                }
            } else if pendingValues[pendingID] == nil {
                try await markChanged(initial, uid: uid, repositoryURL: repositoryURL)
            }
            while session == sessionID, let value = pendingValues[pendingID] {
                try await cloud.save(value, identity: identity, uid: uid)
                guard session == sessionID else { return nil }
                try await dataStore.transaction { transaction in
                    guard session == self.sessionID,
                          try transaction.value(Bool.self, in: "commitRulePending", id: pendingID) == value else { return }
                    transaction.remove(in: "commitRulePending", id: pendingID)
                }
            }
            return nil
        } catch {
            guard session == sessionID else { return nil }
            return "Commit warning preferences are saved locally, but could not sync: \(error.localizedDescription)"
        }
    }

    private var pendingValues: [String: Bool] {
        (try? dataStore.values(Bool.self, in: "commitRulePending")) ?? [:]
    }

    private func key(uid: String, path: String) -> String { "\(uid)|\(path)" }
    private func localValue(_ url: URL) -> Bool {
        localStore.settings(for: url.path, currentBranch: nil, remotes: []).skipProtectedBranchCommitWarnings
    }
}
