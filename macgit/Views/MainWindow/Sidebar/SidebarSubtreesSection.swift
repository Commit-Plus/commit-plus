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

struct SidebarSubtreesSection: View {
    @Environment(\.appTextScale) private var textScale
    let repositoryURL: URL
    let entries: [GitSubtreeEntry]
    let isExpanded: Bool
    let isLoading: Bool
    let onAddLinkSubtree: () -> Void
    let actions: SidebarSubtreeSectionActions

    var body: some View {
        Section {
            headerRow

            if isExpanded {
                if isLoading && entries.isEmpty {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                } else if entries.isEmpty {
                    Text("No subtrees")
                        .font(.caption.scaled(by: textScale))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        row(for: entry)
                            .padding(.leading, 6)
                            .sidebarPointingHandCursor()
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        SidebarSectionHeader(
            section: .subtrees,
            isExpanded: isExpanded,
            activeDropLabel: nil,
            onToggle: actions.toggleSection
        ) {
            Button("Add/Link Subtree", systemImage: "plus", action: onAddLinkSubtree)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Add/Link Subtree")
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .sidebarPointingHandCursor()
    }

    private func row(for entry: GitSubtreeEntry) -> some View {
        let path = repositoryURL.appendingPathComponent(entry.path, isDirectory: true)
        return SidebarSubtreeRow(
            entry: entry,
            onShowInFinder: { actions.showInFinder(path) },
            onOpenInTerminal: { actions.openInTerminal(path) },
            onPull: { actions.pull(entry) },
            onPush: { actions.push(entry) },
            onEditLink: { actions.edit(entry) },
            onUnlink: { actions.unlink(entry) }
        )
        .tag(SidebarSelection.subtree(entry.id))
    }
}
