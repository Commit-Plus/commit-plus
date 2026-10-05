// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Immutable drawing data retained independently of the graph and view lifetime.
nonisolated final class CommitGraphRowGeometry: NSObject {
    struct Stroke: Equatable {
        let path: Path
        let colorIndex: Int
        let isHighlighted: Bool
    }

    let strokes: [Stroke]
    let dots: [GraphDot]

    init(strokes: [Stroke], dots: [GraphDot]) {
        self.strokes = strokes
        self.dots = dots
    }
}
