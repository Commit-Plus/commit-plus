// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct ReferenceComparisonPatch: Sendable {
    let hunks: [DiffHunk]
    let isBinary: Bool
    let isTruncated: Bool
}
