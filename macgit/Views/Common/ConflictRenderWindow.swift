// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics

nonisolated enum ConflictRenderWindow {
    static let batchSize = 100
    static let buffer = 400

    static func rows(count: Int, minY: CGFloat, height: CGFloat, rowHeight: CGFloat = 18) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let first = min(count - 1, max(0, Int(max(0, minY - 8) / rowHeight)))
        let last = min(count, first + Int(max(0, height) / rowHeight) + 2)
        let lower = max(0, (first / batchSize) * batchSize - buffer)
        let upper = min(count, ((last + batchSize - 1) / batchSize) * batchSize + buffer)
        return lower..<upper
    }
}
