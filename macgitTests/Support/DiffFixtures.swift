// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
@testable import macgit

nonisolated enum DiffFixtures {
    static func hunk(
        lines count: Int,
        lineLength: Int = 32,
        type: DiffLineType = .added
    ) -> DiffHunk {
        DiffHunk(
            header: "@@ -1,\(count) +1,\(count) @@",
            lines: (0..<count).map { index in
                DiffLine(
                    oldLineNumber: type == .added ? nil : index + 1,
                    newLineNumber: type == .removed ? nil : index + 1,
                    text: String(repeating: "x", count: lineLength),
                    type: type
                )
            }
        )
    }

    static func hunks(count: Int, linesEach: Int) -> [DiffHunk] {
        (0..<count).map { index in
            DiffHunk(
                header: "@@ -\(index * linesEach + 1),\(linesEach) +\(index * linesEach + 1),\(linesEach) @@",
                lines: hunk(lines: linesEach).lines
            )
        }
    }

    static func longASCIILine(length: Int) -> String {
        String(repeating: "x", count: length)
    }

    static func longCJKLine(length: Int) -> String {
        String(repeating: "中", count: length)
    }

    static func crlfLine(_ text: String) -> String { text + "\r" }
    static func tabbedLine(_ text: String) -> String { "\t" + text }
}
