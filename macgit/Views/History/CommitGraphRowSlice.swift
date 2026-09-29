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
import Foundation

/// References the graph primitives that intersect one native table row.
/// Primitives keep their global coordinates so every row clips the exact same
/// Bezier geometry at its upper and lower boundary.
nonisolated struct CommitGraphRowSlice: Equatable, Sendable {
    let pathIndices: [Int]
    let linkIndices: [Int]
    let dotIndices: [Int]

    static func makeRows(
        paths: [GraphPath],
        links: [GraphLink],
        dots: [GraphDot],
        rowCount: Int
    ) -> [CommitGraphRowSlice] {
        makeRows(
            paths: paths,
            links: links,
            dots: dots,
            rowRange: 0..<rowCount,
            rowCount: rowCount
        )
    }

    static func makeRows(
        paths: [GraphPath],
        links: [GraphLink],
        dots: [GraphDot],
        rowRange: Range<Int>,
        rowCount: Int
    ) -> [CommitGraphRowSlice] {
        guard rowCount > 0, !rowRange.isEmpty else { return [] }

        var pathIndices = Array(repeating: [Int](), count: rowRange.count)
        var linkIndices = Array(repeating: [Int](), count: rowRange.count)
        var dotIndices = Array(repeating: [Int](), count: rowRange.count)

        for (index, path) in paths.enumerated() {
            add(
                index,
                spanning: path.points.map(\.y),
                rowRange: rowRange,
                rowCount: rowCount,
                to: &pathIndices
            )
        }

        for (index, link) in links.enumerated() {
            add(
                index,
                spanning: [link.start.y, link.control.y, link.end.y],
                rowRange: rowRange,
                rowCount: rowCount,
                to: &linkIndices
            )
        }

        for (index, dot) in dots.enumerated() {
            let row = min(rowCount - 1, max(0, Int(floor(dot.center.y))))
            if rowRange.contains(row) {
                dotIndices[row - rowRange.lowerBound].append(index)
            }
        }

        return pathIndices.indices.map { row in
            CommitGraphRowSlice(
                pathIndices: pathIndices[row],
                linkIndices: linkIndices[row],
                dotIndices: dotIndices[row]
            )
        }
    }

    private static func add(
        _ index: Int,
        spanning yValues: [CGFloat],
        rowRange: Range<Int>,
        rowCount: Int,
        to rows: inout [[Int]]
    ) {
        guard let minimumY = yValues.min(),
              let maximumY = yValues.max(),
              maximumY >= 0,
              minimumY <= CGFloat(rowCount) else {
            return
        }

        let lowerRow = max(0, Int(floor(minimumY)))
        let upperRow = min(rowCount - 1, Int(floor(maximumY)))
        guard lowerRow <= upperRow else { return }

        let visibleLowerRow = max(lowerRow, rowRange.lowerBound)
        let visibleUpperRow = min(upperRow, rowRange.upperBound - 1)
        guard visibleLowerRow <= visibleUpperRow else { return }

        for row in visibleLowerRow...visibleUpperRow {
            rows[row - rowRange.lowerBound].append(index)
        }
    }
}
