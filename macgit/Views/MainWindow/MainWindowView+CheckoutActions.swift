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
    func performCheckout(ref: String, stash: Bool) async {
        do {
            let support = GitBranchUndoSupport()
            let previousRef = try await support.currentRef(in: repositoryURL)
            if stash {
                try await GitStatusService.shared.stash(
                    options: GitStatusService.StashOptions(
                        message: "Stashed before switching to \(ref)",
                        keepIndex: false
                    ),
                    in: repositoryURL
                )
            }
            try await GitStatusService.shared.checkoutCommit(ref, in: repositoryURL)
            await MainActor.run {
                undoManager.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Checkout \(ref)",
                        undoOperation: .checkoutRef(ref: previousRef),
                        redoOperation: .checkoutRef(ref: ref)
                    )
                )
            }
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            syncState.showError(error.localizedDescription)
        }
    }

    func performTagCheckout(tag: String) async {
        await performCheckout(ref: tag, stash: false)
    }

    func remoteBranchCheckoutTarget(
        for reference: String,
        remotes: [String]
    ) -> RemoteBranchCheckoutTarget? {
        guard let separator = reference.firstIndex(of: "/") else { return nil }
        let remote = String(reference[..<separator])
        let branchStart = reference.index(after: separator)
        let branch = String(reference[branchStart...])
        guard remotes.contains(remote), !branch.isEmpty, branch != "HEAD" else { return nil }
        return RemoteBranchCheckoutTarget(remote: remote, branch: branch)
    }

    func performRemoteBranchCheckout(
        target: RemoteBranchCheckoutTarget,
        localBranch: String,
        trackRemote: Bool
    ) async {
        do {
            let checkedOutBranch = try await GitStatusService.shared.checkoutRemoteBranch(
                remote: target.remote,
                branch: target.branch,
                localBranch: localBranch,
                trackRemote: trackRemote,
                in: repositoryURL
            )
            await syncState.refresh(repositoryURL: repositoryURL)
            await MainActor.run {
                selectedItem = .branch(checkedOutBranch)
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL, "checkedOutBranch": checkedOutBranch]
            )
        } catch {
            syncState.showError(error.localizedDescription)
        }
    }
}
