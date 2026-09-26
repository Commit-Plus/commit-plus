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
        let message: String
        let current: String
        let selected: String
        // nil means a structural conflict that cannot safely use the text editor.
        let markedResult: String?
        let permissions: Int
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
