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

import Foundation

extension MainWindowView {
    var providerCredentialResolver: GitProviderCredentialResolver {
        providerAccountController.credentialResolver(
            preferredAccountIDsByRemoteIdentity: providerAccountPreferenceStore.preferences
        )
    }

    func runRemoteOperation(
        _ message: String,
        remotes: [String],
        operation: @escaping (GitProviderCredentialResolver) async -> Void
    ) {
        Task {
            guard let credentialResolver = await credentialResolverForRemoteOperation(remotes: remotes) else {
                return
            }
            runRepositoryOperation(message) {
                await operation(credentialResolver)
            }
        }
    }

    func executeRepositoryAIRemoteOperation(
        _ operation: RepositoryAIValidatedRemoteOperation
    ) async throws -> RepositoryAIRemoteOperationExecutionResult {
        let executor = RepositoryAIRemoteOperationExecutor(
            credentialResolverProvider: { remotes in
                await credentialResolverForRemoteOperation(remotes: remotes)
            },
            undoManager: undoManager,
            syncState: syncState,
            operationProgress: operationProgress
        )
        return try await executor.execute(operation, in: repositoryURL)
    }

    func credentialResolverForRemoteOperation(
        remotes: [String]
    ) async -> GitProviderCredentialResolver? {
        var resolver = providerCredentialResolver

        for remote in Set(remotes.filter { !$0.isEmpty }) {
            let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
            let matchingAccounts = resolver.matchingAccounts(for: remoteURL)
            guard matchingAccounts.count > 1,
                  resolver.preferredAccountID(for: remoteURL) == nil,
                  let identity = resolver.remoteIdentity(for: remoteURL),
                  let selectedAccountID = await selectProviderAccount(
                      remoteName: remote,
                      identity: identity,
                      accounts: matchingAccounts
                  ) else {
                if matchingAccounts.count > 1 && resolver.preferredAccountID(for: remoteURL) == nil {
                    return nil
                }
                continue
            }

            do {
                try await providerAccountPreferenceStore.update(accountID: selectedAccountID, for: identity)
            } catch {
                syncState.showError(error.localizedDescription)
                return nil
            }
            resolver = providerCredentialResolver
        }

        return resolver
    }

    func credentialResolverForFetch(
        options: GitStatusService.FetchOptions
    ) async -> GitProviderCredentialResolver? {
        let remotes: [String]
        if options.fetchAllRemotes {
            remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        } else if let defaultRemote = repoSettings.defaultRemoteName, !defaultRemote.isEmpty {
            remotes = [defaultRemote]
        } else {
            remotes = await GitStatusService.shared.remotes(in: repositoryURL).prefix(1).map { $0 }
        }
        return await credentialResolverForRemoteOperation(remotes: remotes)
    }

    func selectProviderAccount(
        remoteName: String,
        identity: GitRemoteIdentity,
        accounts: [GitProviderAccount]
    ) async -> String? {
        await withCheckedContinuation { continuation in
            providerAccountSelectionContinuation = continuation
            pendingProviderAccountSelection = PendingGitProviderAccountSelection(
                remoteName: remoteName,
                identity: identity,
                accounts: accounts
            )
        }
    }

    func completeProviderAccountSelection(with accountID: String?) {
        let continuation = providerAccountSelectionContinuation
        providerAccountSelectionContinuation = nil
        pendingProviderAccountSelection = nil
        continuation?.resume(returning: accountID)
    }

    func pushAfterCommit(remote: String, branch: String) async throws {
        guard let credentialResolver = await credentialResolverForRemoteOperation(remotes: [remote]) else {
            return
        }
        let options = GitStatusService.PushOptions(
            remote: remote,
            branches: [branch],
            pushTags: false
        )
        _ = try await GitStatusService.shared.push(
            options: options,
            in: repositoryURL,
            credentialResolver: credentialResolver
        )
    }

    func trackedRemote(for branch: String) async -> String? {
        guard let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else {
            return nil
        }
        let components = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let remote = components.first, !remote.isEmpty else { return nil }
        return String(remote)
    }
}
