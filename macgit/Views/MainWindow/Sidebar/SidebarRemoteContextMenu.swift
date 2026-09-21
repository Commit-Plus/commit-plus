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
import AppKit
import SwiftUI

struct SidebarRemoteContextMenu: View {
    let fullPath: String
    let currentBranch: String
    let actions: SidebarRemoteSectionActions

    var body: some View {
        if let remoteBranch = remoteBranchParts(from: fullPath) {
            Button("Checkout...") {
                actions.select(.remoteBranch(fullPath))
                actions.checkoutFromContextMenu(fullPath)
            }
            .disabled(remoteBranch.branch == "HEAD")

            let pullTarget = currentBranch.isEmpty ? "current branch" : currentBranch
            Button("Pull \(fullPath) into \(pullTarget)") {
                actions.pullIntoCurrent(remoteBranch.remote, remoteBranch.branch)
            }
            .disabled(currentBranch.isEmpty || remoteBranch.branch == "HEAD")

            Divider()

            copyBranchNameButton

            Button("Compare with…") { actions.compare(fullPath) }
                .disabled(remoteBranch.branch == "HEAD")

            Divider()

            Button("Delete...", role: .destructive) {
                actions.confirmDelete(
                    RemoteBranchDeleteTarget(
                        remote: remoteBranch.remote,
                        branch: remoteBranch.branch
                    )
                )
            }
            .disabled(remoteBranch.branch == "HEAD")

            Divider()

            Button("Create Pull Request...") {
                actions.createPullRequest(remoteBranch.remote, remoteBranch.branch)
            }
            .disabled(remoteBranch.branch == "HEAD")
        } else {
            copyBranchNameButton
        }
    }

    private var copyBranchNameButton: some View {
        Button("Copy Branch Name to Clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fullPath, forType: .string)
        }
    }

    private func remoteBranchParts(from fullPath: String) -> (remote: String, branch: String)? {
        let parts = fullPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let remote = String(parts[0])
        let branch = String(parts[1])
        guard !remote.isEmpty, !branch.isEmpty else { return nil }
        return (remote, branch)
    }
}
