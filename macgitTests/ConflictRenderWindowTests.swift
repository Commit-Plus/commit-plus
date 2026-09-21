// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class ConflictRenderWindowTests: XCTestCase {
    func testLargeFileWindowIncludesNavigationTargetAndBuffersInBothDirections() {
        for row in [0, 100, 10_000, 19_999, 5_000, 0] {
            let range = ConflictRenderWindow.rows(count: 20_000, minY: CGFloat(row * 18 + 8), height: 720)
            XCTAssertTrue(range.contains(row))
            XCTAssertLessThanOrEqual(range.count, 1_000)
            XCTAssertLessThanOrEqual(range.lowerBound, max(0, row - 400))
            XCTAssertGreaterThanOrEqual(range.upperBound, min(20_000, row + 440))
        }
    }

    func testWindowHandlesEmptySmallAndShrinkingFiles() {
        XCTAssertEqual(ConflictRenderWindow.rows(count: 0, minY: 0, height: 720), 0..<0)
        XCTAssertEqual(ConflictRenderWindow.rows(count: 20, minY: 0, height: 720), 0..<20)
        XCTAssertEqual(ConflictRenderWindow.rows(count: 20, minY: 360_000, height: 720), 0..<20)
    }

    func testCachedConflictTargetPreservesSectionIdentityAfterResolution() {
        let context = (0..<10_000).map { "line \($0)\n" }.joined()
        var document = ConflictResolutionDocument(
            sections: [.context(context), .conflict(current: "ours\n", incoming: "theirs\nextra\n"), .context("end\n")],
            currentContent: "", incomingContent: ""
        )
        let before = ConflictPanelAlignment(document: document)
        XCTAssertEqual(before.rowIndex(forConflictSectionIndex: 1), 10_000)
        XCTAssertEqual(before.incomingRows[10_000].conflictSectionIndex, 1)
        XCTAssertTrue(before.currentRows[10_001].isPlaceholder)
        document.sections[1].resolution = .both
        let after = ConflictPanelAlignment(document: document)
        XCTAssertEqual(after.rowIndex(forConflictSectionIndex: 1), 10_000)
        XCTAssertEqual(after.incomingRows.count, before.incomingRows.count + 1)
    }
}
