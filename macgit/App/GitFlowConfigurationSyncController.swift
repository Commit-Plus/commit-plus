//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Combine
import Foundation

struct GitFlowConfigurationSyncOutcome {
    var configuration: GitFlowConfiguration?
    var warningMessage: String?

    static let unchanged = GitFlowConfigurationSyncOutcome(
        configuration: nil,
        warningMessage: nil
    )
}

@MainActor
final class GitFlowConfigurationSyncController: ObservableObject {
    private let cloudStore: GitFlowConfigurationCloudStore?
    private let localStore: GitFlowConfigurationStore
    private let identityResolver: any RepositoryRemoteIdentityResolving
    private let dataStore: LocalDataStore
    private var operations: [URL: (UUID, Task<Void, Never>)] = [:]

    init(
        cloudStore: GitFlowConfigurationCloudStore?,
        localStore: GitFlowConfigurationStore = GitFlowConfigurationStore(),
        identityResolver: any RepositoryRemoteIdentityResolving = RepositoryRemoteIdentityResolver(),
        dataStore: LocalDataStore? = nil
    ) {
        self.cloudStore = cloudStore
        self.localStore = localStore
        self.identityResolver = identityResolver
        self.dataStore = dataStore ?? .shared
    }

    // File-backed configuration and its SQLite outbox cannot share a transaction.
    // Serialize their workflows per repository so a download cannot interleave a save.
    private func serialized<T>(in repositoryURL: URL, operation: @escaping () async throws -> T) async throws -> T {
        let previous = operations[repositoryURL]?.1
        let id = UUID()
        let task = Task {
            await previous?.value
            try await dataStore.prepare()
            return try await operation()
        }
        operations[repositoryURL] = (id, Task { _ = try? await task.value })
        defer { if operations[repositoryURL]?.0 == id { operations[repositoryURL] = nil } }
        return try await task.value
    }

    func reconcile(repositoryURL: URL, fallbackConfiguration: GitFlowConfiguration, uid: String?) async -> GitFlowConfigurationSyncOutcome {
        guard uid != nil, cloudStore != nil else { return .unchanged }
        do {
            return try await serialized(in: repositoryURL) {
                await self.reconcileNow(repositoryURL: repositoryURL, fallbackConfiguration: fallbackConfiguration, uid: uid)
            }
        } catch {
            return GitFlowConfigurationSyncOutcome(configuration: nil, warningMessage: error.localizedDescription)
        }
    }

    func save(_ configuration: GitFlowConfiguration, repositoryURL: URL, uid: String?) async throws -> String? {
        try await serialized(in: repositoryURL) {
            try await self.saveNow(configuration, repositoryURL: repositoryURL, uid: uid)
        }
    }

    private func reconcileNow(
        repositoryURL: URL,
        fallbackConfiguration: GitFlowConfiguration,
        uid: String?
    ) async -> GitFlowConfigurationSyncOutcome {
        guard let uid, let cloudStore else { return .unchanged }

        let localResult = await localStore.loadResult(in: repositoryURL)
        if case .invalid = localResult {
            return .unchanged
        }
        guard let identity = await identityResolver.identity(in: repositoryURL) else {
            return .unchanged
        }
        let uploadID = pendingUploadID(uid: uid, repositoryID: identity.documentID)

        do {
            if let pendingVersion = pendingVersion(uploadID) {
                if case .value(let localConfiguration) = localResult {
                    try await upload(
                        localConfiguration,
                        identity: identity,
                        uid: uid,
                        cloudStore: cloudStore
                    )
                    try await clearPendingUpload(uploadID, version: pendingVersion)
                    return .unchanged
                }
                try await clearPendingUpload(uploadID, version: pendingVersion)
            }

            if let cloudConfiguration = try await cloudStore.configuration(
                repositoryID: identity.documentID,
                uid: uid
            ) {
                let latestLocalResult = await localStore.loadResult(in: repositoryURL)
                let pendingVersion = pendingVersion(uploadID)
                if pendingVersion != nil || localConfigurationChanged(
                    from: localResult,
                    to: latestLocalResult
                ) {
                    if case .value(let latestLocalConfiguration) = latestLocalResult {
                        try await upload(
                            latestLocalConfiguration,
                            identity: identity,
                            uid: uid,
                            cloudStore: cloudStore
                        )
                        if let pendingVersion { try await clearPendingUpload(uploadID, version: pendingVersion) }
                    }
                    return .unchanged
                }
                guard cloudConfiguration.canonicalKey == identity.canonicalKey else {
                    throw GitFlowCloudConfigurationDocumentError.invalidDocument
                }
                let localConfiguration: GitFlowConfiguration
                switch localResult {
                case .none:
                    localConfiguration = fallbackConfiguration
                case .value(let configuration):
                    localConfiguration = configuration
                case .invalid:
                    return .unchanged
                }
                let merged = cloudConfiguration.applying(to: localConfiguration)
                try GitFlowPlanner().validate(merged)
                try await localStore.save(merged, in: repositoryURL)
                return GitFlowConfigurationSyncOutcome(
                    configuration: merged,
                    warningMessage: nil
                )
            }

            if case .value(let localConfiguration) = localResult {
                try await upload(
                    localConfiguration,
                    identity: identity,
                    uid: uid,
                    cloudStore: cloudStore
                )
            }
            return .unchanged
        } catch {
            return GitFlowConfigurationSyncOutcome(
                configuration: nil,
                warningMessage: "Git Flow is available locally, but its configuration could not sync: \(error.localizedDescription)"
            )
        }
    }

    private func saveNow(
        _ configuration: GitFlowConfiguration,
        repositoryURL: URL,
        uid: String?
    ) async throws -> String? {
        try await localStore.save(configuration, in: repositoryURL)
        guard let uid,
              let cloudStore,
              let identity = await identityResolver.identity(in: repositoryURL) else {
            return nil
        }
        let uploadID = pendingUploadID(uid: uid, repositoryID: identity.documentID)
        let pendingVersion = try await markPendingUpload(uploadID)

        do {
            try await upload(
                configuration,
                identity: identity,
                uid: uid,
                cloudStore: cloudStore
            )
            try await clearPendingUpload(uploadID, version: pendingVersion)
            return nil
        } catch {
            return "Git Flow was saved locally, but its configuration could not sync: \(error.localizedDescription)"
        }
    }

    private func upload(
        _ configuration: GitFlowConfiguration,
        identity: RepositoryBookmarkIdentity,
        uid: String,
        cloudStore: GitFlowConfigurationCloudStore
    ) async throws {
        try await cloudStore.save(
            GitFlowCloudConfiguration(
                configuration: configuration,
                canonicalKey: identity.canonicalKey
            ),
            repositoryID: identity.documentID,
            uid: uid
        )
    }

    private func localConfigurationChanged(
        from initial: GitFlowLocalStateLoadResult<GitFlowConfiguration>,
        to latest: GitFlowLocalStateLoadResult<GitFlowConfiguration>
    ) -> Bool {
        switch (initial, latest) {
        case (.none, .none):
            false
        case (.value(let initialConfiguration), .value(let latestConfiguration)):
            initialConfiguration != latestConfiguration
        default:
            true
        }
    }

    private func pendingUploadID(uid: String, repositoryID: String) -> String {
        "\(uid)|\(repositoryID)"
    }

    private func pendingVersion(_ id: String) -> String? {
        try? dataStore.value(String.self, in: "gitFlowPending", id: id)
    }

    private func markPendingUpload(_ id: String) async throws -> String {
        let version = UUID().uuidString
        try await dataStore.transaction { transaction in
            try transaction.set(version, in: "gitFlowPending", id: id)
        }
        return version
    }

    private func clearPendingUpload(_ id: String, version: String) async throws {
        try await dataStore.transaction { transaction in
            guard try transaction.value(String.self, in: "gitFlowPending", id: id) == version else { return }
            transaction.remove(in: "gitFlowPending", id: id)
        }
    }
}
