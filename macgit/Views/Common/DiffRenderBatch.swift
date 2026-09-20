// SPDX-License-Identifier: AGPL-3.0-or-later

/// Bounds eager line layout inside each horizontally scrolling diff card.
/// These are display ranges only; patch actions still use the original hunk.
nonisolated enum DiffRenderBatch {
    static let lineLimit = 100

    static func ranges(lineCount: Int) -> [Range<Int>] {
        stride(from: 0, to: lineCount, by: lineLimit).map { start in
            start..<min(start + lineLimit, lineCount)
        }
    }
}
