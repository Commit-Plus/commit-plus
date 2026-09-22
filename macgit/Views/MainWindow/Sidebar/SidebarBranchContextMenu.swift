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

struct SidebarBranchContextMenu: View {
    let branch: String
    let currentBranch: String
    let syncStatus: BranchSyncStatus?
    let upstream: String?
    let remoteNames: [String]
    let branchesByRemote: [String: [String]]
    let actions: SidebarBranchSectionActions

    private var pushRemotes: [String] {
        BranchUpstreamActionPolicy.pushRemotes(branch: branch, upstream: upstream, remotes: remoteNames)
    }

    var body: some View {
        Button("Checkout \(branch)") {
            actions.checkout(branch)
        }
        .disabled(branch == currentBranch)

        Divider()

        Button("Merge \(branch) into \(currentBranch)") {
            actions.mergeIntoCurrent(branch)
        }
        .disabled(branch == currentBranch)
        Button("Rebase current changes onto \(branch)") {
            actions.rebaseOnto(branch)
        }
        .disabled(branch == currentBranch)

        Divider()

        Button("Fetch \(branch)") {
            actions.fetch(branch)
        }
        .disabled(!BranchFetchActionPolicy.shouldEnableFetch(for: syncStatus))
        let pullLabel = upstream.map { "Pull \($0) (tracked)" } ?? "Pull (tracked)"
        Button(pullLabel) {
            actions.pullTracked(branch)
        }
        .disabled(!BranchUpstreamActionPolicy.shouldEnablePullFromUpstream(for: upstream))
        Menu("Push to") {
            let pushLabel = upstream.map { "\($0) (tracked)" } ?? "Push to (tracked)"
            Button(pushLabel) {
                actions.pushTracked(branch)
            }
            .disabled(!BranchUpstreamActionPolicy.shouldEnablePushToUpstream(for: upstream))
            if !pushRemotes.isEmpty {
                Menu("Other Remote") {
                    ForEach(pushRemotes, id: \.self) { remote in
                        Button(remote) {
                            actions.pushToRemote(branch, remote)
                        }
                    }
                }
            }

            if upstream?.isEmpty == false || !pushRemotes.isEmpty {
                Divider()
            }
            if let upstream, !upstream.isEmpty {
                Button("Force Push to \(upstream) (tracked)…", role: .destructive) {
                    actions.forcePushTracked(branch)
                }
            }
            if !pushRemotes.isEmpty {
                Menu("Force Push to Other Remote") {
                    ForEach(pushRemotes, id: \.self) { remote in
                        Button("\(remote)/\(branch)…", role: .destructive) {
                            actions.forcePushToRemote(branch, remote)
                        }
                    }
                }
            }
        }
        Menu("Track Remote Branch") {
            if remoteNames.isEmpty {
                Text("No remotes configured")
            } else {
                let hasAnyRemoteBranch = remoteNames.contains { !(branchesByRemote[$0] ?? []).isEmpty }
                if hasAnyRemoteBranch {
                    ForEach(remoteNames.sorted(), id: \.self) { remote in
                        ForEach((branchesByRemote[remote] ?? []).sorted(), id: \.self) { remoteBranch in
                            let upstreamRef = "\(remote)/\(remoteBranch)"
                            Button {
                                actions.trackRemoteBranch(branch, upstreamRef)
                            } label: {
                                if upstream == upstreamRef {
                                    Label(upstreamRef, systemImage: "checkmark")
                                } else {
                                    Text(upstreamRef)
                                }
                            }
                        }
                    }
                    Divider()
                } else {
                    Text("No remote branches")
                    Divider()
                }
                Button {
                    actions.trackRemoteBranch(branch, nil)
                } label: {
                    if upstream == nil {
                        Label("(None)", systemImage: "checkmark")
                    } else {
                        Text("(None)")
                    }
                }
            }
        }
        .disabled(remoteNames.isEmpty)

        Divider()

        Button("Create Branch from '\(branch)'...") {
            actions.createBranchFrom(branch)
        }
        Button("Create Tag from '\(branch)'...") {
            actions.createTagFrom(branch)
        }

        Divider()

        Button("Compare with…") { actions.compare(branch) }

        Divider()

        Button("Rename...") {
            actions.rename(branch)
        }
        Button("Delete \(branch)") {
            actions.confirmDelete(.single(branch))
        }
        .disabled(branch == currentBranch)

        Divider()

        Button("Copy Branch Name to Clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch, forType: .string)
        }

        Divider()

        Button("Create Pull Request...") {
            actions.createPullRequest(branch)
        }
        .disabled(!BranchUpstreamActionPolicy.shouldEnableCreatePullRequest(for: upstream))
    }
}
