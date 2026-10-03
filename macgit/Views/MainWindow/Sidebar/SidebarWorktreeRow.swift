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

struct SidebarWorktreeRow: View {
    @Environment(\.appTextScale) private var textScale
    let entry: WorktreeEntry
    let isCurrentRepositoryWorktree: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onOpenInNewWindow: () -> Void
    let onOpenInTerminal: () -> Void
    let onEditLabel: () -> Void
    let onClearLabel: () -> Void
    let onEditLock: () -> Void
    let onUnlock: () -> Void
    let onMove: () -> Void
    let onSwitchBranch: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.isLocked ? "lock.fill" : (isCurrentRepositoryWorktree ? "circle.fill" : "folder"))
                .font(.system(size: isCurrentRepositoryWorktree ? 7 : 10))
                .foregroundStyle(isCurrentRepositoryWorktree ? Color.accentColor : .secondary)
                .frame(width: 16, alignment: .center)

            Text(entry.displayTitle)
                .font(.system(size: 12).scaled(by: textScale))
                .fontWeight(isCurrentRepositoryWorktree ? .bold : .regular)
                .italic(isCurrentRepositoryWorktree)
                .lineLimit(1)

            if isCurrentRepositoryWorktree {
                Text("(this)")
                    .font(.system(size: 10).scaled(by: textScale))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isCurrentRepositoryWorktree, entry.dirtyCount > 0 {
                Text("\(entry.dirtyCount)")
                    .font(.system(size: 10, weight: .medium).scaled(by: textScale))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .cornerRadius(4)
            } else if !isCurrentRepositoryWorktree, entry.dirtyCount < 0 {
                Text("?")
                    .font(.system(size: 10, weight: .medium).scaled(by: textScale))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .tag(SidebarSelection.worktree(entry.path))
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onOpen)
        .contextMenu {
            SidebarWorktreeContextMenu(
                entry: entry,
                isCurrentRepositoryWorktree: isCurrentRepositoryWorktree,
                onOpenInNewWindow: onOpenInNewWindow,
                onOpenInTerminal: onOpenInTerminal,
                onEditLabel: onEditLabel,
                onClearLabel: onClearLabel,
                onEditLock: onEditLock,
                onUnlock: onUnlock,
                onMove: onMove,
                onSwitchBranch: onSwitchBranch,
                onRemove: onRemove
            )
        }
    }
}
