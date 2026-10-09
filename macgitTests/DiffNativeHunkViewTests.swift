// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import XCTest
@testable import macgit

final class DiffNativeHunkViewTests: XCTestCase {
    func testHunksOwnIndependentNativeHorizontalOffsets() {
        MainActor.assumeIsolated {
            let first = makePanel(width: 1_000_000)
            let second = makePanel(width: 800)
            first.horizontalScroll.contentView.scroll(to: CGPoint(x: 50_000, y: 0))
            first.horizontalScroll.reflectScrolledClipView(first.horizontalScroll.contentView)
            XCTAssertEqual(first.horizontalOffset, 50_000, accuracy: 0.5)
            XCTAssertEqual(second.horizontalOffset, 0)
            XCTAssertEqual(second.horizontalScroll.documentView?.frame.width, 800)
            XCTAssertEqual(first.header.frame.width, 600)
        }
    }

    func testLargeHunkKeepsNativeViewportAndHostingViewCountBounded() {
        MainActor.assumeIsolated {
            let panel = makePanel(width: 1_000_000)
            var configured = 0
            panel.updateLines(lineCount: 1_000_000, lineHeight: 22) { _, _, created in
                if created { configured += 1 }
            }
            XCTAssertLessThanOrEqual(configured, 28)
            XCTAssertLessThanOrEqual(panel.horizontalScroll.frame.height, 600)
            XCTAssertLessThanOrEqual(panel.horizontalScroll.documentView!.frame.height, 600)
            let existing = panel.cells.mapValues { ObjectIdentifier($0) }
            panel.updateGeometry(visible: CGRect(x: 0, y: 10, width: 600, height: 600),
                                 headerHeight: 32, lineHeight: 22, lineCount: 1_000_000,
                                 contentWidth: 1_000_000, restoredOffset: nil)
            panel.updateLines(lineCount: 1_000_000, lineHeight: 22) { _, _, _ in }
            for (index, identity) in existing {
                XCTAssertEqual(panel.cells[index].map { ObjectIdentifier($0) }, identity)
            }
            panel.updateGeometry(visible: CGRect(x: 0, y: 15_000_000, width: 600, height: 600),
                                 headerHeight: 32, lineHeight: 22, lineCount: 1_000_000,
                                 contentWidth: 1_000_000, restoredOffset: nil)
            panel.updateLines(lineCount: 1_000_000, lineHeight: 22) { _, _, _ in }
            XCTAssertLessThanOrEqual(panel.cells.count, 29)
            XCTAssertFalse(panel.cells.keys.contains(0))
        }
    }

    func testRestoredOffsetWaitsForAsynchronousWidthMeasurement() {
        MainActor.assumeIsolated {
            let panel = makePanel(width: 0, offset: 2_500)
            XCTAssertEqual(panel.horizontalOffset, 2_500)
            panel.updateGeometry(visible: CGRect(x: 0, y: 0, width: 600, height: 600),
                                 headerHeight: 32, lineHeight: 22, lineCount: 1_000_000,
                                 contentWidth: 10_000, restoredOffset: nil)
            XCTAssertEqual(panel.horizontalScroll.contentView.bounds.minX, 2_500, accuracy: 0.5)
            // Recreating a hunk after vertical recycling restores its native clip.
            let restored = makePanel(width: 10_000, offset: panel.horizontalOffset)
            XCTAssertEqual(restored.horizontalOffset, 2_500, accuracy: 0.5)
        }
    }

    @MainActor
    private func makePanel(width: CGFloat, offset: CGFloat? = nil) -> DiffNativeHunkView {
        let panel = DiffNativeHunkView(frame: CGRect(x: 0, y: 0, width: 600, height: 22_000_032))
        panel.updateGeometry(visible: CGRect(x: 0, y: 0, width: 600, height: 600),
                             headerHeight: 32, lineHeight: 22, lineCount: 1_000_000,
                             contentWidth: width, restoredOffset: offset)
        return panel
    }
}
