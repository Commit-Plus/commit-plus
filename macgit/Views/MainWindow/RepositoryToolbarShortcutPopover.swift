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

struct RepositoryToolbarShortcutPopover: View {
    let pinnedShortcuts: [RepositoryToolbarShortcut]
    let isActionDisabled: (RepositoryToolbarShortcut) -> Bool
    let onPerformAction: (RepositoryToolbarShortcut) -> Void
    let onSetPinned: (RepositoryToolbarShortcut, Bool) -> Void

    private var pinnedSet: Set<RepositoryToolbarShortcut> {
        Set(pinnedShortcuts)
    }

    private var pinLimitReached: Bool {
        pinnedShortcuts.count >= RepositoryToolbarShortcut.maximumPinnedCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Open in")
                    .font(.headline)
                Text("Pin up to \(RepositoryToolbarShortcut.maximumPinnedCount) actions to the toolbar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(RepositoryToolbarShortcut.allCases) { shortcut in
                    RepositoryToolbarShortcutPopoverRow(
                        shortcut: shortcut,
                        isPinned: pinnedSet.contains(shortcut),
                        isActionDisabled: isActionDisabled(shortcut),
                        isPinDisabled: !pinnedSet.contains(shortcut) && pinLimitReached,
                        onPerformAction: { onPerformAction(shortcut) },
                        onSetPinned: { isPinned in onSetPinned(shortcut, isPinned) }
                    )
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
