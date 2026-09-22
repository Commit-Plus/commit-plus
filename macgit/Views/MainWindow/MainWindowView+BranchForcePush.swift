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
        Task {
            guard let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else {
                syncState.showError("This branch has no upstream. Choose a remote from Push to → Force Push to Other Remote.")
                return
            }
            let parts = upstream.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            requestBranchForcePush(branch: branch, remote: parts[0], remoteBranch: parts[1])
        }
    }

    func requestBranchForcePush(branch: String, remote: String, remoteBranch: String) {
        guard !syncState.isAnySyncing, operationProgress.activeOperation == nil else { return }
        runRemoteOperation("Preparing Force Push...", remotes: [remote]) { resolver in
            do {
                pendingBranchForcePush = try await GitStatusService.shared.prepareBranchForcePush(
                    remote: remote, localBranch: branch, remoteBranch: remoteBranch,
                    in: repositoryURL, credentialResolver: resolver
                )
            } catch {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    func forcePushSheetDismissed() {
        guard let request = pendingSheetForcePush else { return }
        pendingSheetForcePush = nil
        requestBranchForcePush(branch: request.branch, remote: request.remote, remoteBranch: request.remoteBranch)
    }

    func confirmBranchForcePush(_ plan: BranchForcePushPlan) {
        pendingBranchForcePush = nil
        runRemoteOperation("Force-pushing \(plan.destination)...", remotes: [plan.remote]) { resolver in
            guard !syncState.isAnySyncing else { return }
            syncState.isPushing = true
            defer { syncState.isPushing = false }
            do {
                try await GitStatusService.shared.forcePushBranch(plan, in: repositoryURL, credentialResolver: resolver)
                undoManager.register(GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: "Force Push \(plan.destination)",
                    undoOperation: .replaceRemoteBranch(plan, restoring: true),
                    redoOperation: .replaceRemoteBranch(plan, restoring: false),
                    confirmationMessage: "Rewrite '\(plan.destination)' to the saved commit? This is allowed only if the remote still matches the previous operation."
                ))
                await syncState.refresh(repositoryURL: repositoryURL)
                NotificationCenter.default.post(name: .repositoryDidChange, object: nil,
                                                userInfo: ["repositoryURL": repositoryURL])
            } catch {
                syncState.showError(error.localizedDescription)
            }
        }
    }
}
