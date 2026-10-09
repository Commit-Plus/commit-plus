// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import CoreGraphics
@testable import macgit

final class DiffHunkGeometryTests: XCTestCase {
    func testVisibleHunksMatchIntersectionIncludingGapsAndEdges() {
        let geometry = DiffHunkGeometry(lineCounts: [0, 1, 100_000, 2], scale: 1.25)
        let positions: [CGFloat] = [-500, 0, 4, 44, 48, 100, 900_000, geometry.height - 1, geometry.height]
        for y in positions {
            let viewport = CGRect(x: 0, y: y, width: 800, height: 600)
            let expected = geometry.starts.indices.filter {
                geometry.frame(at: $0, width: 800).intersects(viewport)
            }
            XCTAssertEqual(Array(geometry.visibleHunks(in: viewport)), expected)
        }
        XCTAssertEqual(geometry.visibleHunks(in: CGRect(x: 0, y: 44, width: 800, height: 8)), 1..<1)
    }

    func testMillionLineHunkOnlyMaterializesVisibleRows() {
        for start: CGFloat in [0, 0.5, 123_456.7, 21_999_800] {
            let rows = DiffHunkGeometry.visibleLines(start: start, height: 600, lineHeight: 22, count: 1_000_000)
            XCTAssertLessThanOrEqual(rows.count, 29)
            XCTAssertLessThanOrEqual(CGFloat(rows.lowerBound) * 22, start)
            XCTAssertGreaterThanOrEqual(CGFloat(rows.upperBound) * 22, min(22_000_000, start + 600))
        }
    }

    func testManyHunksHaveBoundedVisibleRange() {
        let geometry = DiffHunkGeometry(lineCounts: Array(repeating: 3, count: 100_000), scale: 1)
        for y: CGFloat in [0, 500_000, geometry.height - 600] {
            let visible = geometry.visibleHunks(in: CGRect(x: 0, y: y, width: 800, height: 600))
            XCTAssertFalse(visible.isEmpty)
            XCTAssertLessThanOrEqual(visible.count, 7)
        }
    }

    func testOverscanViewportIncludesHunksBeforeAndAfterVisibleContent() {
        let geometry = DiffHunkGeometry(lineCounts: Array(repeating: 3, count: 30), scale: 1)
        let viewport = CGRect(x: 0, y: 600, width: 800, height: 300)
        let visible = geometry.visibleHunks(in: viewport)
        let overscanned = geometry.visibleHunks(in: viewport.insetBy(dx: 0, dy: -viewport.height))

        XCTAssertLessThanOrEqual(overscanned.lowerBound, visible.lowerBound)
        XCTAssertGreaterThanOrEqual(overscanned.upperBound, visible.upperBound)
        XCTAssertGreaterThan(overscanned.count, visible.count)
    }

    func testEmptyViewportAndRows() {
        XCTAssertTrue(DiffHunkGeometry(lineCounts: [], scale: 1).visibleHunks(in: .zero).isEmpty)
        XCTAssertTrue(DiffHunkGeometry.visibleLines(start: 0, height: 0, lineHeight: 22, count: 100).isEmpty)
        XCTAssertTrue(DiffHunkGeometry.visibleLines(start: 0, height: 600, lineHeight: 22, count: 0).isEmpty)
    }
}
