//
//  GitInProgressOperation.swift
//  macgit
//

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

nonisolated enum GitInProgressOperation: Equatable, Sendable {
    case merge(head: String)
    case cherryPick(head: String)
    case revert(head: String)

    var displayName: String {
        switch self {
        case .merge: return "Merge"
        case .cherryPick: return "Cherry-pick"
        case .revert: return "Revert"
        }
    }

    var shortHead: String {
        switch self {
        case .merge(let head), .cherryPick(let head), .revert(let head):
            return String(head.prefix(7))
        }
    }

    var message: String {
        "\(displayName) in progress (\(shortHead)). Resolve conflicts, then continue or abort."
    }

    var canSkip: Bool {
        if case .merge = self { return false }
        return true
    }

    var emptyMessage: String {
        if case .merge = self {
            return "Merge in progress (\(shortHead)). No file changes remain. Continue to complete the merge or abort."
        }
        return "\(displayName) (\(shortHead)) produced an empty commit. Skip the commit or abort."
    }
}
