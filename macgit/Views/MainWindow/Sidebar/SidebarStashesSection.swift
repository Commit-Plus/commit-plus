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

struct SidebarStashesSection: View {
    @Environment(\.appTextScale) private var textScale
    let stashes: [StashEntry]
    let isExpanded: Bool
    let isLoading: Bool
    let isHeaderDropTargeted: Bool
    let activeDropLabel: String?
    let actions: SidebarStashSectionActions

    var body: some View {
        Section {
            headerRow

            if isExpanded {
                if isLoading && stashes.isEmpty {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                } else if stashes.isEmpty {
                    Text("No stashes")
                        .font(.caption.scaled(by: textScale))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stashes) { stash in
                        SidebarStashRow(
                            stash: stash,
                            actions: actions
                        )
                        .padding(.leading, 6)
                        .sidebarPointingHandCursor()
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        SidebarSectionHeader(
            section: .stashes,
            isExpanded: isExpanded,
            activeDropLabel: activeDropLabel,
            onToggle: actions.toggleSection
        ) {
            EmptyView()
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHeaderDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .overlay {
            SidebarBranchDropTarget(
                onTap: actions.toggleSection,
                onTargetedChange: actions.setHeaderDropTargeted,
                fallbackPayload: actions.drop.activePayload,
                canAcceptDrop: { payload in
                    actions.drop.canAccept(payload, .stashesHeader, false)
                },
                dragPayload: { nil },
                dragTitle: { "" },
                onDragEnded: { _ in },
                onDrop: { payload in
                    actions.drop.handlePayload(payload, .stashesHeader, false)
                    return true
                }
            )
            .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
                if let payload = actions.drop.activePayload(),
                   !actions.drop.canAccept(payload, .stashesHeader, false) {
                    actions.drop.clearPayload(payload)
                    return false
                }

                return actions.drop.handleProviders(providers, .stashesHeader, false)
            }
        }
        .sidebarPointingHandCursor()
    }
}
