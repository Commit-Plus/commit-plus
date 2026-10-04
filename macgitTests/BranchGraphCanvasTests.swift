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
import XCTest
@testable import macgit

@MainActor
final class BranchGraphCanvasTests: XCTestCase {
    func testStraightVerticalPathReachesEnd() {
        let graphPath = GraphPath(
            points: [
                CGPoint(x: 10, y: 0.5),
                CGPoint(x: 10, y: 2.5),
            ],
            colorIndex: 0,
            isHighlighted: true
        )

        let path = BranchGraphCanvas.path(
            for: graphPath,
            rowHeight: 20,
            laneWidth: 10
        )

        let rect = path.boundingRect
        XCTAssertEqual(rect.midX, 5, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 10, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 50, accuracy: 0.001)
    }

    func testLaneChangingPathUsesCurveAndReachesTarget() {
        let graphPath = GraphPath(
            points: [
                CGPoint(x: 10, y: 0.5),
                CGPoint(x: 22, y: 1.5),
            ],
            colorIndex: 0,
            isHighlighted: true
        )

        let path = BranchGraphCanvas.path(
            for: graphPath,
            rowHeight: 20,
            laneWidth: 10
        )

        let rect = path.boundingRect
        XCTAssertEqual(rect.minX, 5, accuracy: 0.001)
        XCTAssertEqual(rect.maxX, 15, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 10, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 30, accuracy: 0.001)
    }

    func testSinglePointPathIsEmpty() {
        let graphPath = GraphPath(
            points: [CGPoint(x: 10, y: 0.5)],
            colorIndex: 0,
            isHighlighted: true
        )

        let path = BranchGraphCanvas.path(
            for: graphPath,
            rowHeight: 20,
            laneWidth: 10
        )

        XCTAssertTrue(path.boundingRect.isEmpty)
    }

    func testMergeLinkUsesQuadraticCurve() {
        let link = GraphLink(
            start: CGPoint(x: 10, y: 0.5),
            control: CGPoint(x: 22, y: 0.5),
            end: CGPoint(x: 22, y: 1),
            colorIndex: 1,
            isHighlighted: true
        )

        let path = BranchGraphCanvas.linkPath(
            for: link,
            rowHeight: 20,
            laneWidth: 10
        )

        let rect = path.boundingRect
        XCTAssertEqual(rect.minX, 5, accuracy: 0.001)
        XCTAssertEqual(rect.maxX, 15, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 10, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 20, accuracy: 0.001)
    }

    func testRowOffsetPreservesPathGeometryAndTranslatesItsOrigin() {
        let graphPath = GraphPath(
            points: [
                CGPoint(x: 10, y: 1.5),
                CGPoint(x: 22, y: 2.5),
            ],
            colorIndex: 0,
            isHighlighted: true
        )

        let fullPath = BranchGraphCanvas.path(
            for: graphPath,
            rowHeight: 20,
            laneWidth: 10
        )
        let rowPath = BranchGraphCanvas.path(
            for: graphPath,
            rowHeight: 20,
            laneWidth: 10,
            rowOffset: 1
        )

        XCTAssertEqual(rowPath.boundingRect.minX, fullPath.boundingRect.minX, accuracy: 0.001)
        XCTAssertEqual(rowPath.boundingRect.maxX, fullPath.boundingRect.maxX, accuracy: 0.001)
        XCTAssertEqual(rowPath.boundingRect.minY, fullPath.boundingRect.minY - 20, accuracy: 0.001)
        XCTAssertEqual(rowPath.boundingRect.maxY, fullPath.boundingRect.maxY - 20, accuracy: 0.001)
    }

    func testLongBranchBuildsOnlySegmentsNearVisibleRow() {
        let graphPath = GraphPath(
            points: (0..<20_000).map { CGPoint(x: 10, y: Double($0) + 0.5) },
            colorIndex: 0,
            isHighlighted: true
        )

        XCTAssertEqual(graphPath.segmentEndIndices(intersecting: 14_999..<15_002), 14_999..<15_003)
        let rowPath = BranchGraphCanvas.path(
            for: graphPath,
            rowHeight: 24,
            laneWidth: 14,
            rowOffset: 15_000,
            visibleRows: 14_999..<15_002
        )
        XCTAssertEqual(rowPath.boundingRect.minY, -36, accuracy: 0.001)
        XCTAssertEqual(rowPath.boundingRect.maxY, 60, accuracy: 0.001)
    }

    func testVisibleRowIncludesSegmentCrossingBothBoundaries() {
        let graphPath = GraphPath(
            points: [CGPoint(x: 10, y: 0.5), CGPoint(x: 10, y: 1_000.5)],
            colorIndex: 0,
            isHighlighted: true
        )
        XCTAssertEqual(graphPath.segmentEndIndices(intersecting: 499..<502), 1..<2)
        XCTAssertTrue(graphPath.segmentEndIndices(intersecting: 1_001..<1_004).isEmpty)
    }

    func testDotPathsUseSourceGitStyleSizes() {
        let center = CGPoint(x: 10, y: 0.5)

        for (type, expectedSize) in [
            (GraphDotType.default, 8.0),
            (.head, 12.0),
            (.merge, 12.0),
        ] {
            let dot = GraphDot(
                center: center,
                lane: 0,
                type: type,
                colorIndex: 0,
                isHighlighted: true
            )

            let path = BranchGraphCanvas.dotPath(
                for: dot,
                rowHeight: 20,
                laneWidth: 10,
                dotSize: 8
            )

            XCTAssertEqual(path.boundingRect.width, expectedSize, accuracy: 0.001)
            XCTAssertEqual(path.boundingRect.height, expectedSize, accuracy: 0.001)
        }
    }
}
