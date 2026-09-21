//
//  Commit.swift
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

nonisolated struct Commit: Identifiable, Equatable, Sendable {
    let hash: String
    let parents: [String]
    let message: String
    let author: String
    let email: String
    let date: Date
    let refs: [String]

    var id: String { hash }
    
    var shortHash: String {
        String(hash.prefix(7))
    }
    
    var isMerge: Bool {
        parents.count > 1
    }
    
    static func == (lhs: Commit, rhs: Commit) -> Bool {
        lhs.hash == rhs.hash
    }
}

// MARK: - Commit File Change

nonisolated struct CommitFileChange: Identifiable, Hashable, Sendable {
    let id = UUID()
    let path: String
    let status: CommitFileStatus
    var oldPath: String? = nil
}

nonisolated enum CommitFileStatus: String, Sendable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    
    var displayText: String {
        switch self {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        }
    }
    
    var color: String {
        switch self {
        case .added: return "green"
        case .modified: return "orange"
        case .deleted: return "red"
        case .renamed: return "blue"
        case .copied: return "purple"
        }
    }
}
