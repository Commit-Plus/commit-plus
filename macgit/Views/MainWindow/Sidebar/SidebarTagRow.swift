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
import UniformTypeIdentifiers

struct SidebarTagRow: View {
    @Environment(\.appTextScale) private var textScale
    let row: BranchRowItem
    let expandedFolders: Set<String>
    let remoteNames: [String]
    let isDropTargeted: Bool
    let actions: SidebarTagSectionActions

    var body: some View {
        if row.isFolder {
            content
                .onTapGesture {
                    actions.toggleFolder(row.fullPath)
                }
        } else {
            let tagTarget = GitDragTarget.tag(name: row.fullPath)
            let rowView = content
                .tag(SidebarSelection.tag(row.fullPath))
                .contextMenu {
                    SidebarTagContextMenu(
                        tag: row.fullPath,
                        remoteNames: remoteNames,
                        actions: actions
                    )
                }

            rowView
                .overlay {
                    SidebarBranchDropTarget(
                        onTap: { actions.select(.tag(row.fullPath)) },
                        onDoubleTap: { actions.checkout(row.fullPath) },
                        onTargetedChange: { actions.setTagDropTargeted(row.fullPath, $0) },
                        fallbackPayload: actions.drop.activePayload,
                        canAcceptDrop: { payload in
                            actions.drop.canAccept(payload, tagTarget, false)
                        },
                        dragPayload: { nil },
                        dragTitle: { row.fullPath },
                        onDragEnded: { _ in },
                        onDrop: { payload in
                            actions.drop.handlePayload(payload, tagTarget, false)
                            return true
                        }
                    )
                }
                .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
                    if let payload = actions.drop.activePayload(),
                       !actions.drop.canAccept(payload, tagTarget, false) {
                        actions.drop.clearPayload(payload)
                        return false
                    }

                    return actions.drop.handleProviders(providers, tagTarget, false)
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
                Image(systemName: "tag")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            }

            Text(row.name)
                .font(.system(size: 12).scaled(by: textScale))
                .lineLimit(1)

            Spacer()

            if isDropTargeted {
                BranchDropLabel(text: "Move Tag")
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isDropTargeted ? Color.accentColor.opacity(0.24) : Color.clear)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }
}
