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

struct SidebarBranchSectionActions {
    let toggleSection: () -> Void
    let toggleFolder: (String) -> Void
    let select: (SidebarSelection) -> Void
    let checkout: (String) -> Void
    let fetch: (String) -> Void
    let pullTracked: (String) -> Void
    let pushTracked: (String) -> Void
    let updateCurrentBranch: (CurrentBranchIntegrationStatus) -> Void
    let rename: (String) -> Void
    let createPullRequest: (String) -> Void
    let createBranchFrom: (String) -> Void
    let createTagFrom: (String) -> Void
    let rebaseOnto: (String) -> Void
    let mergeIntoCurrent: (String) -> Void
    let pushToRemote: (String, String) -> Void
    let trackRemoteBranch: (String, String?) -> Void
    let confirmDelete: (DeleteConfirmationTarget) -> Void
    let makeItemProvider: (String) -> NSItemProvider
    let setHeaderDropTargeted: (Bool) -> Void
    let setCurrentDropTargeted: (Bool) -> Void
    let currentDropLabel: () -> String
    let drop: SidebarDropActions
    var forcePushTracked: (String) -> Void = { _ in }
    var forcePushToRemote: (String, String) -> Void = { _, _ in }
    var compare: (String) -> Void = { _ in }
}
