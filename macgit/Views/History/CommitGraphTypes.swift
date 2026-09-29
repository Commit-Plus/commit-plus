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
}

nonisolated struct GraphLink: Sendable {
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

nonisolated struct GraphDot: Sendable {
    let center: CGPoint
    let lane: Int
    let type: GraphDotType
    let colorIndex: Int
    let isHighlighted: Bool
}

nonisolated struct CommitGraphModel: Sendable {
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
        rowIndexByHash: [String: Int]
    ) {
        self.paths = paths
        self.links = links
        self.dots = dots
        self.rowSlices = CommitGraphRowSlice.makeRows(
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
        Color(nsColor: .systemGreen),
        Color(nsColor: .systemBlue),
        Color(nsColor: .systemCyan),
    ]

    static func color(for index: Int) -> Color {
        colors[index % colors.count]
    }
}
