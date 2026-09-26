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
        if expandedFolders.contains(path) {
            expandedFolders.remove(path)
        } else {
            expandedFolders.insert(path)
            if let loadID = activeBranchSyncLoadID {
                startBranchSync(for: branchesUnderPrefix(path), loadID: loadID)
            }
        }
    }

    func toggleRemoteFolder(_ path: String) {
        if expandedRemoteFolders.contains(path) {
            expandedRemoteFolders.remove(path)
        } else {
            expandedRemoteFolders.insert(path)
        }
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
    }

    func confirmDeleteBranch(_ branch: String) {
        let force = forceDeleteBranch
        deleteConfirmationTarget = nil
        forceDeleteBranch = false
        onRunRepositoryOperation("Deleting \(branch)...") {
            await deleteBranch(branch, force: force)
        }
    }

    func deleteBranch(_ branch: String, force: Bool = false) async {
        do {
            let support = GitBranchUndoSupport()
            let tip = try await support.tip(of: branch, in: repositoryURL)
            let upstream = await support.upstream(of: branch, in: repositoryURL)
            _ = try await GitStatusService.shared.deleteBranch(name: branch, force: force, in: repositoryURL)

            await MainActor.run {
                var undoOperations: [GitUndoOperation] = [
                    .createLocalBranch(name: branch, startPoint: tip, checkout: false)
                ]

                if let upstream {
                    undoOperations.append(.setUpstream(branch: branch, upstream: upstream))
                }

                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Delete branch \(branch)",
                        undoOperation: .sequence(undoOperations),
                        redoOperation: .deleteLocalBranch(name: branch, force: force, expectedTip: tip)
                    )
                )
            }

            NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
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
