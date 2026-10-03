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

struct SidebarStashRow: View {
    @Environment(\.appTextScale) private var textScale
    let stash: StashEntry
    let actions: SidebarStashSectionActions

    var body: some View {
        content
            .tag(SidebarSelection.stash(stash.ref))
            .onTapGesture {
                actions.select(.stash(stash.ref))
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    actions.apply(stash.ref)
                }
            )
            .onDrag {
                actions.makeItemProvider(stash.ref)
            } preview: {
                StashDragPreview(title: stash.displayTitle)
            }
            .contextMenu {
                Button("Apply stash") {
                    actions.apply(stash.ref)
                }
                Button("Delete stash", role: .destructive) {
                    actions.delete(stash.ref)
                }
            }
    }

    private var content: some View {
        HStack(spacing: 4) {
            Image(systemName: "tray")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            Text(stash.displayTitle)
                .font(.system(size: 12).scaled(by: textScale))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
