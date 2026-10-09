//
//  CommitGraphTypes.swift
//  macgit
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import SwiftUI

nonisolated enum CommitGraphHighlighting: Equatable, Sendable {
    case all
    case currentBranchOnly
}

nonisolated struct GraphCommitMetadata: Sendable {
    let colorIndex: Int
    let isHighlighted: Bool
    let leftMargin: Double
}

nonisolated struct GraphPath: Sendable {
    let points: [CGPoint]
    let colorIndex: Int
    let isHighlighted: Bool

    /// Generated points increase in Y. Include the segments crossing either
    /// boundary without scanning or rebuilding the rest of a long branch.
    func segmentEndIndices(intersecting rows: Range<Double>) -> Range<Int> {
        guard points.count > 1 else { return 0..<0 }
        func lowerBound(_ y: Double) -> Int {
            var lower = 0
            var upper = points.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if points[middle].y < y {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            return lower
        }
        let start = max(1, lowerBound(rows.lowerBound))
        let end = min(points.count, lowerBound(rows.upperBound) + 1)
        return start..<max(start, end)
    }
}

nonisolated struct GraphLink: Sendable {
    var targetCommitHash: String? = nil
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
    let colorIndex: Int
    let isHighlighted: Bool
}

nonisolated enum GraphDotType: Equatable, Sendable {
    case `default`
    case head
    case merge
}

nonisolated struct GraphDot: Equatable, Sendable {
    let center: CGPoint
    let lane: Int
    let type: GraphDotType
    let colorIndex: Int
    let isHighlighted: Bool
}

nonisolated struct CommitGraphModel: Sendable {
    // Each immutable graph snapshot owns a bounded cache of rendered rows.
    let rowGeometryCache = CommitGraphRowGeometryCache()
    let paths: [GraphPath]
    let links: [GraphLink]
    let dots: [GraphDot]
    let rowSlices: [CommitGraphRowSlice]
    let laneCount: Int
    let commitMetadata: [String: GraphCommitMetadata]
    let rowIndexByHash: [String: Int]

    init(
        paths: [GraphPath],
        links: [GraphLink],
        dots: [GraphDot],
        laneCount: Int,
        commitMetadata: [String: GraphCommitMetadata],
        rowIndexByHash: [String: Int],
        rowSlices: [CommitGraphRowSlice]? = nil
    ) {
        self.paths = paths
        self.links = links
        self.dots = dots
        self.rowSlices = rowSlices ?? CommitGraphRowSlice.makeRows(
            paths: paths,
            links: links,
            dots: dots,
            rowCount: dots.count
        )
        self.laneCount = laneCount
        self.commitMetadata = commitMetadata
        self.rowIndexByHash = rowIndexByHash
    }
}

struct GraphPalette {
    static let colors: [Color] = [
        Color(nsColor: .systemOrange),
        Color(nsColor: .systemGreen),
        Color(nsColor: .systemTeal),
        Color(nsColor: .systemYellow),
        Color(nsColor: .systemPink),
        Color(nsColor: .systemRed),
        Color(nsColor: .systemBrown),
        Color(nsColor: .systemIndigo),
        Color(nsColor: .systemBlue),
        Color(nsColor: .systemCyan),
        Color(nsColor: .systemPurple),
        Color(nsColor: .systemMint),
        Color(red: 0.82, green: 0.34, blue: 0.22),
        Color(red: 0.48, green: 0.58, blue: 0.20),
        Color(red: 0.58, green: 0.38, blue: 0.72),
        Color(red: 0.20, green: 0.52, blue: 0.66),
    ]

    static func nsColor(for index: Int) -> NSColor {
        NSColor(color(for: index))
    }

    static func color(for index: Int) -> Color {
        colors[index % colors.count]
    }
}
