//
//  CommitPatchReviewFile.swift
//  macgit
//
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software; you can redistribute it and/or modify
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

nonisolated struct CommitPatchReviewFile: Identifiable, Sendable {
    enum State: String, Sendable {
        case ready = "Ready"
        case merged = "Merged with your changes"
        case alreadyApplied = "Already present"
        case conflict = "Needs resolution"
        case skipped = "Skipped"
        case resolved = "Resolved"
    }

    let file: CommitFileChange
    var patch: String
    var state: State
    var conflict: Conflict?
    var id: UUID { file.id }

    struct Conflict: Sendable {
        enum Kind: Sendable, Equatable {
            case missingFile
            case unsupportedChange
            case existingMarkers
            case overlappingEdits
        }

        let kind: Kind
        let message: String
        let current: String
        let selected: String
        // nil means a structural conflict that cannot safely use the text editor.
        let markedResult: String?
        let permissions: Int
    }

    var reviewTitle: String {
        conflict?.markedResult == nil ? "Review Selected Changes" : "Resolve Text Conflict"
    }

    var displayState: String {
        guard state == .conflict, let conflict else { return state.rawValue }
        switch conflict.kind {
        case .missingFile: return "File missing"
        case .unsupportedChange: return "Cannot apply safely"
        case .existingMarkers, .overlappingEdits: return "Needs resolution"
        }
    }

    var appliesChanges: Bool {
        state != .conflict && state != .skipped && state != .alreadyApplied && !patch.isEmpty
    }

    static func containsConflictMarkers(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains {
            $0.hasPrefix("<<<<<<<") || $0.hasPrefix("=======") || $0.hasPrefix(">>>>>>>") || $0.hasPrefix("|||||||")
        }
    }
}
