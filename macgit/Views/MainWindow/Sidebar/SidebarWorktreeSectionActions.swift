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
import Foundation

struct SidebarWorktreeSectionActions {
    let toggleSection: () -> Void
    let prepareCreate: () -> Void
    let confirmPrune: () -> Void
    let select: (WorktreeEntry) -> Void
    let open: (WorktreeEntry) -> Void
    let openInTerminal: (URL) -> Void
    let showInFinder: (URL) -> Void
    let editLabel: (WorktreeEntry) -> Void
    let clearLabel: (WorktreeEntry) -> Void
    let editLock: (WorktreeEntry) -> Void
    let unlock: (WorktreeEntry) -> Void
    let move: (WorktreeEntry) -> Void
    let switchBranch: (WorktreeEntry) -> Void
    let confirmRemoval: (WorktreeEntry) -> Void
}
