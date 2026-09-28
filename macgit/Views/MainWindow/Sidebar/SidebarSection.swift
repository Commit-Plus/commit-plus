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

enum SidebarSection: String, CaseIterable {
    case workspace = "WORKSPACE"
    case gitFlow = "GIT FLOW"
    case branches = "BRANCHES"
    case worktrees = "WORKTREES"
    case tags = "TAGS"
    case remotes = "REMOTES"
    case stashes = "STASHES"
    case submodules = "SUBMODULES"
    case subtrees = "SUBTREES"

    var icon: String {
        switch self {
        case .workspace:
            return "square.grid.2x2"
        case .gitFlow:
            return "point.3.connected.trianglepath.dotted"
        case .branches:
            return "arrow.triangle.branch"
        case .worktrees:
            return "rectangle.3.group"
        case .tags:
            return "tag"
        case .remotes:
            return "cloud"
        case .stashes:
            return "archivebox"
        case .submodules:
            return "shippingbox"
        case .subtrees:
            return "square.stack.3d.up"
        }
    }

    var iconColor: Color {
        switch self {
        case .workspace:
            return .blue
        case .branches:
            return .purple
        case .worktrees:
            return .orange
        case .tags:
            return .yellow
        case .remotes:
            return .cyan
        case .stashes:
            return .brown
        case .submodules:
            return .green
        case .subtrees:
            return .pink
        case .gitFlow:
            return .secondary
        }
    }

    var items: [SidebarItem] {
        switch self {
        case .workspace:
            return [.fileStatus, .history, .reflog, .pullRequests, .gitLFS, .search]
        default:
            return []
        }
    }
}
