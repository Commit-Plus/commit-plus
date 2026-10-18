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

enum DeleteConfirmationTarget: Identifiable {
    case single(String)
    case prefix(String)
    case merged(Set<String>)

    var id: String {
        switch self {
        case .single(let branch): return "single:\(branch)"
        case .prefix(let prefix): return "prefix:\(prefix)"
        case .merged(let branches): return "merged:\(branches.sorted().joined(separator: "|"))"
        }
    }
}
