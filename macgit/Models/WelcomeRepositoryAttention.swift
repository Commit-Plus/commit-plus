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

struct WelcomeRepositoryAttention: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let name: String
    var branch = "Detached HEAD"
    var ahead = 0
    var behind = 0
    var conflicts = 0
    var operation: String?
    var unavailable = false
    var error: String?

    var needsAttention: Bool { priority < 6 }
    var showsHistory: Bool { conflicts == 0 && operation == nil && (ahead > 0 || behind > 0) }
    var priority: Int {
        if conflicts > 0 || operation != nil { return 0 }
        if ahead > 0 && behind > 0 { return 1 }
        if ahead > 0 { return 2 }
        if behind > 0 { return 3 }
        if unavailable { return 4 }
        if error != nil { return 5 }
        return 6
    }
    var summary: String {
        if conflicts > 0 { return "\(conflicts) unresolved file(s)" + (operation.map { " · \($0) in progress" } ?? "") }
        if let operation { return "\(operation) in progress · Finish or abort in the repository" }
        if ahead > 0 && behind > 0 { return "Branches diverged · \(ahead) ahead, \(behind) behind" }
        if ahead > 0 { return "\(ahead) commit(s) waiting to be pushed" }
        if behind > 0 { return "\(behind) commit(s) behind upstream · Review before pulling" }
        if unavailable { return "Local repository folder is unavailable" }
        return error ?? ""
    }
}
