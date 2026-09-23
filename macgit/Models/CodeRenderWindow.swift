// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import CoreGraphics

nonisolated enum CodeRenderWindow {
    static let maximumHighlightedLineLength = 4_096

    static func usesWindowedHighlighting(lineCount: Int, longestLineLength: Int, documentLength: Int) -> Bool {
        lineCount > 2_000 || longestLineLength > maximumHighlightedLineLength || documentLength > 65_536
    }

    static func rows(count: Int, viewport: CGRect, rowHeight: CGFloat) -> Range<Int> {
        let first = min(count, max(0, Int(max(0, viewport.minY) / rowHeight)))
        let visible = max(1, Int(ceil(max(0, viewport.height) / rowHeight)))
        return max(0, first - 8)..<min(count, first + visible + 8)
    }

    /// Native editors keep long lines plain; never feed an unbounded paragraph
    /// into the regex highlighter just because it intersects the viewport.
    static func highlightRanges(lineStarts: [Int], length: Int, rows: Range<Int>) -> [NSRange] {
        rows.compactMap { index in
            let start = lineStarts[index]
            let end = index + 1 < lineStarts.count ? lineStarts[index + 1] : length
            guard end > start, end - start <= maximumHighlightedLineLength else { return nil }
            return NSRange(location: start, length: end - start)
        }
    }
}
