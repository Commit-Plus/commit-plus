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

extension SidebarView {
    func toggleFolder(_ path: String) {
        let expanding = !expandedFolders.contains(path)
        if expandedFolders.contains(path) {
            expandedFolders.remove(path)
        } else {
            expandedFolders.insert(path)
        }
        cachedVisibleBranchRows = SidebarTreeBuilder.visibleRows(
            from: branchNodes,
            expandedFolders: expandedFolders
        )
        if expanding, let loadID = activeBranchSyncLoadID {
            let newlyVisibleBranches = visibleBranchRows
                .filter { !$0.isFolder && $0.fullPath.hasPrefix(path + "/") }
                .map(\.fullPath)
            startBranchSync(for: newlyVisibleBranches, loadID: loadID)
        }
    }

    func toggleRemoteFolder(_ path: String) {
        if expandedRemoteFolders.contains(path) {
            expandedRemoteFolders.remove(path)
        } else {
            expandedRemoteFolders.insert(path)
        }
        cachedVisibleRemoteRows = SidebarTreeBuilder.visibleRows(
            from: remoteNodes,
            expandedFolders: expandedRemoteFolders
        )
    }

    func requestRemoteBranchCheckout(_ fullPath: String) {
        guard let remoteBranch = remoteBranchParts(from: fullPath) else {
            errorMessage = "Could not parse remote branch '\(fullPath)'."
            showingError = true
            return
        }
        guard remoteBranch.branch != "HEAD" else { return }
        onRequestRemoteBranchCheckout(
            RemoteBranchCheckoutTarget(remote: remoteBranch.remote, branch: remoteBranch.branch)
        )
    }

    func deleteRemoteBranch(_ target: RemoteBranchDeleteTarget) async {
        do {
            _ = try await GitStatusService.shared.deleteRemoteBranch(
                remote: target.remote,
                name: target.branch,
                in: repositoryURL
            )
            await loadRemotes()
            await MainActor.run {
                remoteBranchDeleteTarget = nil
                if selection == .remoteBranch(target.fullPath) {
                    selection = .item(.history)
                }
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await MainActor.run {
                remoteBranchDeleteTarget = nil
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    @MainActor
    func expandBranchesSection() {
        guard !sectionStates.branchesExpanded else { return }
        sectionStates.branchesExpanded = true
        SidebarSettingsStore.shared.update(for: repositoryURL.path, state: sectionStates)
    }

    func remoteBranchParts(from fullPath: String) -> (remote: String, branch: String)? {
        let parts = fullPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let remote = String(parts[0])
        let branch = String(parts[1])
        guard !remote.isEmpty, !branch.isEmpty else { return nil }
        return (remote, branch)
    }

    func branchesUnderPrefix(_ prefix: String) -> [String] {
        var leaves: [String] = []

        func collect(_ nodes: [BranchNode]) {
            for node in nodes {
                if node.isFolder {
                    collect(node.children)
                } else {
                    leaves.append(node.fullPath)
                }
            }
        }

        collect(branchNodes)
        return leaves.filter { $0.hasPrefix(prefix + "/") }.sorted()
    }

    func cancelDeleteConfirmation() {
        deleteConfirmationTarget = nil
        forceDeleteBranch = false
        deleteRemoteBranchAlongsideLocal = false
    }

    func requestFullyMergedBranchDeletion(_ branch: String) {
        let branches = Set(branchMergeDetectionController.assessments.values
            .filter {
                $0.isFullyMerged && $0.branch != currentBranch
                    && branchMergeDetectionController.isCleanupCandidate($0.branch, configuration: gitFlowConfiguration)
            }
            .map(\.branch))
        guard branches.contains(branch) else { return }
        deleteConfirmationTarget = .merged(branches)
    }

    func recordDailyBranchCleanupCheckIfReady() {
        guard hasLoadedBranches,
              branchMergeDetectionController.loadingBranches.isEmpty,
              featureAccessController.decision(
                for: .branchMergeDetection,
                entitlement: accountController.entitlement
              ).isAllowed else { return }
        let branches = branchMergeDetectionController.assessments.values
            .filter {
                $0.isFullyMerged && $0.branch != currentBranch
                    && branchMergeDetectionController.isCleanupCandidate(
                        $0.branch,
                        configuration: gitFlowConfiguration
                    )
            }
            .map(\.branch)
        Task {
            await appNotificationController.recordDailyBranchCleanupCheck(
                repositoryURL: repositoryURL,
                branchNames: branches
            )
        }
    }

    func presentPendingBranchCleanupIfReady() {
        guard let notification = appNotificationController.pendingBranchCleanup,
              notification.repositoryURL.resolvingSymlinksInPath().standardizedFileURL
                == repositoryURL.resolvingSymlinksInPath().standardizedFileURL,
              !currentBranch.isEmpty else { return }
        let branches = Set(notification.branchNames.filter { $0 != currentBranch })
        appNotificationController.consumePendingBranchCleanup(id: notification.id)
        guard !branches.isEmpty else { return }
        deleteConfirmationTarget = .merged(branches)
    }

    @MainActor
    func validateMergedBranchDeletion(_ branch: String) async throws -> String {
        guard let assessment = await branchMergeDetectionController.revalidateFullyMerged(
            branch: branch,
            repositoryURL: repositoryURL,
            entitlement: accountController.entitlement,
            policy: featureAccessController.policy
        ) else {
            throw GitError.commandFailed("Deletion stopped because '\(branch)' changed, is protected or in use, or its merge evidence could not be verified.")
        }
        return assessment.tipSHA
    }

    func confirmDeleteBranch(_ branch: String) {
        let force = forceDeleteBranch
        let remoteTarget = deleteRemoteBranchAlongsideLocal
            ? matchingRemoteDeleteTarget(for: branch)
            : nil
        deleteConfirmationTarget = nil
        forceDeleteBranch = false
        deleteRemoteBranchAlongsideLocal = false
        onRunRepositoryOperation("Deleting \(branch)...") {
            await deleteBranch(branch, force: force, remoteTarget: remoteTarget)
        }
    }

    func matchingRemoteDeleteTarget(for branch: String) -> RemoteBranchDeleteTarget? {
        RemoteBranchDeleteResolver.target(
            localBranch: branch,
            upstream: upstreamByBranch[branch],
            branchesByRemote: branchesByRemote
        )
    }

    func deleteBranch(
        _ branch: String,
        force: Bool = false,
        remoteTarget: RemoteBranchDeleteTarget? = nil
    ) async {
        do {
            let support = GitBranchUndoSupport()
            let tip = try await support.tip(of: branch, in: repositoryURL)
            let upstream = await support.upstream(of: branch, in: repositoryURL)
            let remoteHash: String?
            if let remoteTarget {
                remoteHash = try await GitRemoteUndoSupport().remoteHash(
                    remote: remoteTarget.remote,
                    branch: remoteTarget.branch,
                    in: repositoryURL
                )
            } else {
                remoteHash = nil
            }
            _ = try await GitStatusService.shared.deleteBranch(name: branch, force: force, in: repositoryURL)

            do {
                if let remoteTarget {
                    _ = try await GitStatusService.shared.deleteRemoteBranch(
                        remote: remoteTarget.remote,
                        name: remoteTarget.branch,
                        in: repositoryURL
                    )
                }
            } catch {
                registerDeletedBranchUndo(
                    branch: branch,
                    force: force,
                    tip: tip,
                    upstream: upstream,
                    remoteTarget: nil,
                    remoteHash: nil
                )
                throw error
            }

            registerDeletedBranchUndo(
                branch: branch,
                force: force,
                tip: tip,
                upstream: upstream,
                remoteTarget: remoteTarget,
                remoteHash: remoteHash
            )

            NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    @MainActor
    private func registerDeletedBranchUndo(
        branch: String,
        force: Bool,
        tip: String,
        upstream: String?,
        remoteTarget: RemoteBranchDeleteTarget?,
        remoteHash: String?
    ) {
        undoManager?.register(
            GitBranchUndoSupport.deletedBranchUndoEntry(
                repositoryURL: repositoryURL,
                branch: branch,
                force: force,
                tip: tip,
                upstream: upstream,
                remoteTarget: remoteTarget,
                remoteHash: remoteHash
            )
        )
    }

    func refreshAfterBranchDeletion() {
        Task {
            await loadBranches(force: true)
            await loadRemotes()
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        }
    }
}
