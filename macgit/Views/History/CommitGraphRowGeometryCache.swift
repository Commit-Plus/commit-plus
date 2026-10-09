// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// NSCache is thread-safe; drawing data is accessed only on the main actor.
/// Ownership by one graph snapshot makes invalidation automatic when it changes.
nonisolated final class CommitGraphRowGeometryCache: @unchecked Sendable {
    private let rows = NSCache<NSString, CommitGraphRowGeometry>()

    init() {
        rows.countLimit = 512
    }

    @MainActor
    func geometry(for model: CommitGraphModel, rowIndex: Int, canvasWidth: CGFloat? = nil) -> CommitGraphRowGeometry {
        let key = "\(rowIndex):\(canvasWidth.map { String(Double($0)) } ?? "unbounded")" as NSString
        if let cached = rows.object(forKey: key) { return cached }
        guard model.rowSlices.indices.contains(rowIndex) else {
            return CommitGraphRowGeometry(strokes: [], dots: [])
        }

        let row = model.rowSlices[rowIndex]
        let offset = Double(rowIndex)
        let strokes = row.pathIndices.compactMap { index -> CommitGraphRowGeometry.Stroke? in
            guard model.paths.indices.contains(index) else { return nil }
            let path = model.paths[index]
            return CommitGraphRowGeometry.Stroke(
                path: BranchGraphCanvas.path(
                    for: path,
                    rowHeight: BranchGraphRowCanvas.rowHeight,
                    laneWidth: BranchGraphRowCanvas.laneWidth,
                    rowOffset: offset,
                    visibleRows: (offset - 1)..<(offset + 2)
                ),
                colorIndex: path.colorIndex,
                isHighlighted: path.isHighlighted
            )
        } + row.linkIndices.compactMap { index -> CommitGraphRowGeometry.Stroke? in
            guard model.links.indices.contains(index) else { return nil }
            let link = model.links[index]
            return CommitGraphRowGeometry.Stroke(
                path: BranchGraphCanvas.linkPath(
                    for: link,
                    rowHeight: BranchGraphRowCanvas.rowHeight,
                    laneWidth: BranchGraphRowCanvas.laneWidth,
                    rowOffset: offset,
                    canvasWidth: canvasWidth
                ),
                colorIndex: link.colorIndex,
                isHighlighted: link.isHighlighted
            )
        }
        let dots = row.dotIndices.compactMap { index in
            model.dots.indices.contains(index) ? model.dots[index] : nil
        }
        let geometry = CommitGraphRowGeometry(strokes: strokes, dots: dots)
        rows.setObject(geometry, forKey: key)
        return geometry
    }
}
