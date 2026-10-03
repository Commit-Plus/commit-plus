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

struct SidebarSubtreeRow: View {
    @Environment(\.appTextScale) private var textScale
    let entry: GitSubtreeEntry
    let onShowInFinder: () -> Void
    let onOpenInTerminal: () -> Void
    let onPull: () -> Void
    let onPush: () -> Void
    let onEditLink: () -> Void
    let onUnlink: () -> Void

    private var actions: Set<SubtreeSidebarAction> {
        SubtreeSidebarPolicy.actions(for: entry)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.folderExists ? "square.stack.3d.up.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(entry.folderExists ? Color.accentColor : .red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.body.scaled(by: textScale))
                    .lineLimit(1)
                Text(entry.path)
                    .font(.caption.scaled(by: textScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if entry.squash {
                Text("Squashed")
                    .font(.caption.scaled(by: textScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !entry.folderExists {
                Text("Missing folder")
                    .font(.caption.scaled(by: textScale))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
        .contextMenu {
            if actions.contains(.showInFinder) {
                Button("Show in Finder", systemImage: "folder", action: onShowInFinder)
            }
            if actions.contains(.openInTerminal) {
                Button("Open in Terminal", systemImage: "terminal", action: onOpenInTerminal)
            }
            if actions.contains(.pull) {
                Button("Pull from Subtree Remote...", systemImage: "arrow.down.circle", action: onPull)
            }
            if actions.contains(.push) {
                Button("Push to Subtree Remote...", systemImage: "arrow.up.circle", action: onPush)
            }
            if actions.contains(.editLink) {
                Button("Edit Link...", systemImage: "slider.horizontal.3", action: onEditLink)
            }
            if actions.contains(.unlink) {
                Button("Unlink...", systemImage: "link.badge.minus", role: .destructive, action: onUnlink)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [entry.name, entry.path, entry.branch]
        if entry.squash {
            parts.append("Squashed")
        }
        if !entry.folderExists {
            parts.append("Missing folder")
        }
        return parts.joined(separator: ", ")
    }
}
