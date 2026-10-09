// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CoreGraphics

/// Fixed row metrics let us find visible hunks without constructing their views.
nonisolated struct DiffHunkGeometry {
    let starts: [CGFloat]
    let heights: [CGFloat]
    let headerHeight: CGFloat
    let lineHeight: CGFloat
    let height: CGFloat

    init(lineCounts: [Int], scale: CGFloat) {
        headerHeight = 32 * scale
        lineHeight = 22 * scale
        var starts: [CGFloat] = []
        var heights: [CGFloat] = []
        var y: CGFloat = 4
        for count in lineCounts {
            starts.append(y)
            let height = headerHeight + CGFloat(count) * lineHeight
            heights.append(height)
            y += height + 8
        }
        self.starts = starts
        self.heights = heights
        height = y
    }

    func frame(at index: Int, width: CGFloat) -> CGRect {
        CGRect(x: 4, y: starts[index], width: max(1, width - 8), height: heights[index])
    }

    func visibleHunks(in viewport: CGRect) -> Range<Int> {
        guard viewport.height > 0 else { return 0..<0 }
        var low = 0
        var high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] + heights[middle] <= viewport.minY { low = middle + 1 }
            else { high = middle }
        }
        let first = low
        while low < starts.count, starts[low] < viewport.maxY { low += 1 }
        return first..<low
    }

    static func visibleLines(start: CGFloat, height: CGFloat, lineHeight: CGFloat, count: Int) -> Range<Int> {
        guard height > 0, lineHeight > 0 else { return 0..<0 }
        let first = min(count, max(0, Int(floor(start / lineHeight))))
        let end = min(count, max(first, Int(ceil((start + height) / lineHeight))))
        return first..<end
    }
}
