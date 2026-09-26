// SPDX-License-Identifier: AGPL-3.0-or-later
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
