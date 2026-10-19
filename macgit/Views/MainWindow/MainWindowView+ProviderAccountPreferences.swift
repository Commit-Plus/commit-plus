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

    /// Runs a remote operation in this window's background lane instead of the blocking overlay.
    /// Credentials, including any reconnect prompt, are resolved before the item is queued.
    /// `onNotQueued` runs when credential resolution is cancelled or the window's background
    /// lane was cancelled (e.g. the window closed) while credentials were being resolved.
    func runBackgroundRemoteOperation(
        _ title: String,
        remotes: [String],
        onNotQueued: (@MainActor () -> Void)? = nil,
        operation: @escaping (GitProviderCredentialResolver) async -> RepositoryBackgroundActivityOutcome
    ) {
        let generation = operationProgress.backgroundGeneration
        Task {
            guard let credentialResolver = await credentialResolverForRemoteOperation(remotes: remotes) else {
                onNotQueued?()
                return
            }
            let queuedID = operationProgress.runInBackground(ifGeneration: generation, title: title) {
                await operation(credentialResolver)
            }
            if queuedID == nil {
                onNotQueued?()
            }
        }
    }

    /// Foreground actions that also update remote-tracking refs wait for this window's
    /// queued background fetches and pushes. Returns false when the wait was cancelled.
    func waitForBackgroundRemoteActivity() async -> Bool {
        await operationProgress.waitForBackgroundIdle()
        return !Task.isCancelled
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
            guard !Task.isCancelled else { return nil }
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

            guard !Task.isCancelled else { return nil }
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
        let remotes = await GitStatusService.shared.remoteNamesForFetch(
            options: options,
            in: repositoryURL
        )
        return await credentialResolverForRemoteOperation(remotes: remotes)
    }

    func selectProviderAccount(
        remoteName: String,
        identity: GitRemoteIdentity,
        accounts: [GitProviderAccount]
    ) async -> String? {
        guard !Task.isCancelled else { return nil }
        return await withCheckedContinuation { continuation in
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
