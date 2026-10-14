//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

extension MainWindowView {
    func presentBranchSheet(startPoint: GitBranchStartPoint?) {
        branchSheetPresentation = BranchSheetPresentation(startPoint: startPoint)
    }

    func handleDragDropRequest(_ request: GitDragDropRequest) {
        switch request {
        case .cherryPick(let commits, let targetBranch):
            pendingCommitDropConfirmation = PendingCommitDropConfirmation(
                commits: commits,
                targetBranch: targetBranch
            )
        case .branchOperation(let source, let target, let operation):
            pendingBranchDropConfirmation = PendingBranchDropConfirmation(
                sourceBranch: source,
                targetBranch: target,
                operation: operation
            )
        case .createBranch(let startPoint):
            presentCreateBranchSheet(startPoint: startPoint)
        case .checkoutRemoteBranch(let fullPath):
            runRepositoryOperation("Checking out \(fullPath)...") {
                await checkoutRemoteBranchFromDrop(fullPath)
            }
        case .createTagFromBranch(let sourceBranch):
            presentTagSheetFromBranchTip(sourceBranch)
        case .createTagFromCommit(let commit):
            presentTagSheetFromCommit(commit)
        case .moveTag(let tagName, let commit):
            presentTagMoveConfirmation(tagName: tagName, commit: commit)
        case .pushBranchToRemote(let branch):
            presentPushBranchDropConfirmation(branch)
        case .stashFiles(let paths):
            handleStashFilesDrop(paths: paths)
        case .applyStash(let ref):
            requestStashAction(ref: ref, action: .apply)
        }
    }

    func handleStashFilesDrop(paths: [String]) {
        guard !paths.isEmpty else { return }
        if syncState.isAnySyncing {
            syncState.showInfo("Wait for the current operation to finish before stashing more files.")
            return
        }
        pendingStashPaths = paths
        showingStashSheet = true
    }

    func checkoutRemoteBranchFromDrop(_ fullPath: String) async {
        let parts = fullPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            await MainActor.run {
                syncState.showError("Could not parse remote branch '\(fullPath)'.")
            }
            return
        }

        let remote = String(parts[0])
        let branch = String(parts[1])
        guard !remote.isEmpty, !branch.isEmpty else {
            await MainActor.run {
                syncState.showError("Could not parse remote branch '\(fullPath)'.")
            }
            return
        }

        do {
            let localBranch = try await GitStatusService.shared.checkoutRemoteBranch(
                remote: remote,
                branch: branch,
                in: repositoryURL
            )
            await MainActor.run {
                selectedItem = .branch(localBranch)
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    func presentCreateBranchSheet(startPoint: GitBranchStartPoint) {
        switch startPoint {
        case .commit:
            presentBranchSheet(startPoint: startPoint)
        case .branch(let sourceBranch):
            presentBranchSheetFromBranchTip(sourceBranch)
        }
    }

    func presentBranchSheetFromBranchTip(_ sourceBranch: String) {
        presentBranchSheet(startPoint: .branch(sourceBranch))
    }

    func initializeSubmodule(at path: String) async {
        do {
            try await GitStatusService.shared.initializeSubmodule(
                path: path,
                in: repositoryURL,
                credentialResolver: providerCredentialResolver
            )
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    func updateSubmodule(at path: String, mode: SubmoduleUpdateMode) async {
        do {
            try await GitStatusService.shared.updateSubmodule(
                path: path,
                mode: mode,
                in: repositoryURL,
                credentialResolver: providerCredentialResolver
            )
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    func synchronizeSubmoduleURL(at path: String) async {
        do {
            try await GitStatusService.shared.synchronizeSubmoduleURL(
                path: path,
                in: repositoryURL
            )
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    func presentPushBranchDropConfirmation(_ branch: String) {
        pendingPushBranchDropConfirmation = RepositorySheetRequest(input: branch)
    }

    func loadPushBranchDropConfirmation(_ branch: String) async throws -> PendingPushBranchDropConfirmation {
        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        try Task.checkCancellation()
        guard let remote = remotes.first(where: { $0 == "origin" }) ?? remotes.first else {
            throw GitError.commandFailed("No remotes configured.")
        }
        return PendingPushBranchDropConfirmation(branch: branch, remote: remote)
    }

    func performConfirmedBranchPush(_ confirmation: PendingPushBranchDropConfirmation) async {
        let options = GitStatusService.PushOptions(
            remote: confirmation.remote,
            branches: [confirmation.branch],
            branchMappings: [confirmation.branch: confirmation.branch]
        )

        await syncState.performPush(
            options: options,
            repositoryURL: repositoryURL,
            undoManager: undoManager,
            credentialResolver: providerCredentialResolver
        )
    }
}
