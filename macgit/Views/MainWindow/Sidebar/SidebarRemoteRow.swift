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

struct SidebarRemoteRow: View {
    let row: BranchRowItem
    let currentBranch: String
    let expandedFolders: Set<String>
    let actions: SidebarRemoteSectionActions

    var body: some View {
        if row.isFolder {
            content
                .onTapGesture {
                    actions.toggleFolder(row.fullPath)
                }
        } else {
            leafRow
        }
    }

    @ViewBuilder
    private var leafRow: some View {
        let rowView = content
            .tag(SidebarSelection.remoteBranch(row.fullPath))
            .onTapGesture {
                actions.select(.remoteBranch(row.fullPath))
            }
            .onTapGesture(count: 2) {
                actions.select(.remoteBranch(row.fullPath))
                actions.checkoutFromRow(row.fullPath)
            }

        if isHeadReference {
            rowView
                .contextMenu {
                    SidebarRemoteContextMenu(
                        fullPath: row.fullPath,
                        currentBranch: currentBranch,
                        actions: actions
                    )
                }
        } else {
            rowView
                .overlay {
                    SidebarBranchDragSource(
                        onTap: {
                            actions.select(.remoteBranch(row.fullPath))
                        },
                        onDoubleTap: {
                            actions.select(.remoteBranch(row.fullPath))
                            actions.checkoutFromRow(row.fullPath)
                        },
                        dragPayload: {
                            actions.makePayload(row.fullPath)
                        },
                        dragTitle: row.fullPath,
                        onDragEnded: { _ in
                            actions.finishDrag(row.fullPath)
                        }
                    )
                }
                .contextMenu {
                    SidebarRemoteContextMenu(
                        fullPath: row.fullPath,
                        currentBranch: currentBranch,
                        actions: actions
                    )
                }
        }
    }

    private var content: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<row.indent, id: \.self) { _ in
                    Color.clear
                        .frame(width: 16)
                }
            }

            if row.isFolder {
                Image(systemName: expandedFolders.contains(row.fullPath) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            } else {
                Color.clear
                    .frame(width: 16)
            }

            Text(row.name)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var isHeadReference: Bool {
        remoteBranchParts(from: row.fullPath)?.branch == "HEAD"
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
