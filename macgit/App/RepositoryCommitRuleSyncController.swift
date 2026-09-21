// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Combine

@MainActor
final class RepositoryCommitRuleSyncController: ObservableObject {
    private let defaults: UserDefaults
    private let localStore: RepoSettingsStore
    private let resolver: any RepositoryRemoteIdentityResolving
    private let pendingKey = "dev.thanhtran.macgit.repositoryCommitRules.pending"
    private var sessionID = UUID()
    private var activeUID: String?
    private var activePath: String?
    private var runningSessions: Set<UUID> = []

    init(defaults: UserDefaults = .standard, localStore: RepoSettingsStore = .shared,
         resolver: any RepositoryRemoteIdentityResolving = RepositoryRemoteIdentityResolver()) {
        self.defaults = defaults
        self.localStore = localStore
        self.resolver = resolver
    }

    func setSession(uid: String?, repositoryURL: URL) {
        guard activeUID != uid || activePath != repositoryURL.path else { return }
        activeUID = uid
        activePath = repositoryURL.path
        sessionID = UUID()
    }

    func markChanged(_ value: Bool, uid: String?, repositoryURL: URL) {
        guard let uid else { return }
        var pending = pendingValues
        pending[key(uid: uid, path: repositoryURL.path)] = value
        defaults.set(pending, forKey: pendingKey)
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
            let initial = localValue(repositoryURL)
            let remote = try await cloud.load(identity: identity, uid: uid)
            guard session == sessionID else { return nil }
            // Edits made while offline or while loading always win over an older download.
            if pendingValues[pendingID] == nil, let remote {
                if localValue(repositoryURL) == initial {
                    var settings = localStore.settings(for: repositoryURL.path, currentBranch: nil, remotes: [])
                    settings.skipProtectedBranchCommitWarnings = remote
                    localStore.update(for: repositoryURL.path, settings: settings)
                    onApplied(remote)
                }
            } else if pendingValues[pendingID] == nil {
                markChanged(initial, uid: uid, repositoryURL: repositoryURL)
            }
            while session == sessionID, let value = pendingValues[pendingID] {
                try await cloud.save(value, identity: identity, uid: uid)
                guard session == sessionID else { return nil }
                var pending = pendingValues
                if pending[pendingID] == value {
                    pending.removeValue(forKey: pendingID)
                    defaults.set(pending, forKey: pendingKey)
                }
            }
            return nil
        } catch {
            guard session == sessionID else { return nil }
            return "Commit warning preferences are saved locally, but could not sync: \(error.localizedDescription)"
        }
    }

    private var pendingValues: [String: Bool] {
        defaults.dictionary(forKey: pendingKey) as? [String: Bool] ?? [:]
    }

    private func key(uid: String, path: String) -> String { "\(uid)|\(path)" }
    private func localValue(_ url: URL) -> Bool {
        localStore.settings(for: url.path, currentBranch: nil, remotes: []).skipProtectedBranchCommitWarnings
    }
}
