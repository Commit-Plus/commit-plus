// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct CommitPatchRequest: Sendable {
    enum Direction: String, Sendable {
        case apply = "Apply"
        case revert = "Revert"
    }

    // Line numbers are relative to the immutable source commit, never the working copy.
    struct Line: Hashable, Sendable {
        let old: Int?
        let new: Int?

        init(_ line: DiffLine) {
            old = line.oldLineNumber
            new = line.newLineNumber
        }

        init(old: Int?, new: Int?) {
            self.old = old
            self.new = new
        }
    }

    let commit: String
    let files: [CommitFileChange]
    let direction: Direction
    // nil means complete files; a nonempty set means only these changed lines in one file.
    let lines: Set<Line>?
    let scope: String
}
