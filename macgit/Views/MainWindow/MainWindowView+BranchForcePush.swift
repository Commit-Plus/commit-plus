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
import SwiftUI

extension MainWindowView {
    func requestTrackedBranchForcePush(_ branch: String) {
        guard !syncState.isAnySyncing, operationProgress.activeOperation == nil else { return }
        pendingBranchForcePush = RepositorySheetRequest(input: (branch: branch, remote: nil, remoteBranch: nil))
    }

    func requestBranchForcePush(branch: String, remote: String, remoteBranch: String) {
        guard !syncState.isAnySyncing, operationProgress.activeOperation == nil else { return }
        pendingBranchForcePush = RepositorySheetRequest(input: (branch: branch, remote: remote, remoteBranch: remoteBranch))
    }

    func prepareForcePush(_ request: RepositorySheetRequest<(branch: String, remote: String?, remoteBranch: String?)>) async throws -> BranchForcePushPlan {
        let input = request.input
        let remote: String
        let remoteBranch: String
        if let requestedRemote = input.remote, let requestedBranch = input.remoteBranch {
            remote = requestedRemote
            remoteBranch = requestedBranch
        } else {
            guard let upstream = await GitStatusService.shared.upstreamBranch(for: input.branch, in: repositoryURL) else {
                throw GitError.commandFailed("This branch has no upstream. Choose a remote from Push to, then enable Force Push in the Push dialog.")
            }
            let parts = upstream.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw GitError.commandFailed("Could not parse upstream branch.") }
            remote = parts[0]
            remoteBranch = parts[1]
        }
        try Task.checkCancellation()
        guard let resolver = await credentialResolverForRemoteOperation(remotes: [remote]) else {
            throw GitError.commandFailed("Account selection was cancelled.")
        }
        try Task.checkCancellation()
        return try await GitStatusService.shared.prepareBranchForcePush(
            remote: remote, localBranch: input.branch, remoteBranch: remoteBranch,
            in: repositoryURL, credentialResolver: resolver
        )
    }

    var providerAccountSelectionOutsideOperationSheet: Binding<PendingGitProviderAccountSelection?> {
        Binding(
            get: { pendingBranchForcePush == nil && pendingTagDeletion == nil ? pendingProviderAccountSelection : nil },
            set: { pendingProviderAccountSelection = $0 }
        )
    }

    func forcePushPreparationSheet(for request: RepositorySheetRequest<(branch: String, remote: String?, remoteBranch: String?)>) -> some View {
        RepositorySheetLoadingView(title: "Force Push \(request.input.branch)", load: {
            try await prepareForcePush(request)
        }, onCancel: {
            if pendingProviderAccountSelection != nil { completeProviderAccountSelection(with: nil) }
            pendingBranchForcePush = nil
        }) { plan in
            BranchForcePushConfirmationSheet(plan: plan) { try await confirmBranchForcePush(plan) }
        }
        .id(request.id)
        .replacingSheet(item: $pendingProviderAccountSelection) { selection in
            GitProviderAccountSelectionSheet(
                selection: selection,
                onSelect: { completeProviderAccountSelection(with: $0) },
                onCancel: { completeProviderAccountSelection(with: nil) }
            )
        }
        .onDisappear {
            if pendingProviderAccountSelection != nil { completeProviderAccountSelection(with: nil) }
        }
    }

    func forcePushSheetDismissed() {
        pushSheetSelection = nil
        guard let request = pendingSheetForcePush else { return }
        pendingSheetForcePush = nil
        requestBranchForcePush(branch: request.branch, remote: request.remote, remoteBranch: request.remoteBranch)
    }

    func confirmBranchForcePush(_ plan: BranchForcePushPlan) async throws {
        guard !syncState.isAnySyncing else {
            throw GitError.commandFailed("Wait for the current Git operation to finish before force-pushing.")
        }
        guard let resolver = await credentialResolverForRemoteOperation(remotes: [plan.remote]) else {
            throw GitError.commandFailed("Account selection was cancelled.")
        }
        guard !syncState.isAnySyncing else {
            throw GitError.commandFailed("Wait for the current Git operation to finish before force-pushing.")
        }
        syncState.isPushing = true
        defer { syncState.isPushing = false }
        try await GitStatusService.shared.forcePushBranch(plan, in: repositoryURL, credentialResolver: resolver)
        undoManager.register(GitUndoEntry(
            repositoryURL: repositoryURL,
            label: "Force Push \(plan.destination)",
            undoOperation: .replaceRemoteBranch(plan, restoring: true),
            redoOperation: .replaceRemoteBranch(plan, restoring: false),
            confirmationMessage: "Rewrite '\(plan.destination)' to the saved commit? This is allowed only if the remote still matches the previous operation."
        ))
        pendingBranchForcePush = nil
        Task {
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(name: .repositoryDidChange, object: nil,
                                            userInfo: ["repositoryURL": repositoryURL])
        }
    }
}
