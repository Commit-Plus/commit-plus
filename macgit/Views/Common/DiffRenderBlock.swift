// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import CoreGraphics

/// Stable geometry lets the viewport retain four fully rendered neighbours in
/// either direction without asking a lazy stack to estimate offscreen heights.
nonisolated struct DiffRenderBlock: Identifiable {
    static let rowHeight: CGFloat = 22
    static let headerHeight: CGFloat = 32
    static let scrollerHeight: CGFloat = 16
    static let spacing: CGFloat = 12
    static let overscan = 4

    let hunk: DiffHunk
    let lineRange: Range<Int>
    let offset: CGFloat

    var id: String { "\(hunk.id)-\(lineRange.lowerBound)" }
    var height: CGFloat {
        Self.headerHeight + CGFloat(lineRange.count) * Self.rowHeight + Self.scrollerHeight
    }
    var endOffset: CGFloat { offset + height + Self.spacing }

    static func layout(hunks: [DiffHunk]) -> [Self] {
        var offset: CGFloat = 0
        return hunks.flatMap { hunk in
            DiffRenderBatch.ranges(lineCount: hunk.lines.count).map { range in
                let block = Self(hunk: hunk, lineRange: range, offset: offset)
                offset = block.endOffset
                return block
            }
        }
    }

    static func renderedRange(in blocks: [Self], viewport: CGRect) -> Range<Int> {
        guard !blocks.isEmpty else { return 0..<0 }
        // Binary search avoids scanning every hunk on each scroll event.
        func index(at position: CGFloat) -> Int {
            var lower = 0
            var upper = blocks.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if blocks[middle].endOffset <= position {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            return min(lower, blocks.count - 1)
        }
        let first = index(at: viewport.minY)
        let last = index(at: viewport.maxY)
        return max(0, first - overscan)..<min(blocks.count, last + overscan + 1)
    }
}
