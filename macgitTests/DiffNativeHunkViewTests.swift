// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import XCTest
@testable import macgit

final class DiffNativeHunkViewTests: XCTestCase {
    func testSmallHunkDoesNotRelayoutRowsForEachVerticalScrollTick() {
        MainActor.assumeIsolated {
            let panel = DiffNativeHunkView(frame: CGRect(x: 0, y: 0, width: 600, height: 252))
            func moveViewport(to y: CGFloat) {
                panel.updateGeometry(visible: CGRect(x: 0, y: y, width: 600, height: 600),
                                     headerHeight: 32, lineHeight: 22, lineCount: 10,
                                     contentWidth: 1_000, restoredOffset: nil)
            }
            moveViewport(to: -400)
            panel.updateLines(lineCount: 10, lineHeight: 22) { _, _, _ in }
            let frames = panel.cells.mapValues(\.frame)
            let scrollFrame = panel.horizontalScroll.frame
            var configurations = 0
            for y in stride(from: CGFloat(-399), through: 250, by: 1) {
                moveViewport(to: y)
                panel.updateLines(lineCount: 10, lineHeight: 22) { _, _, _ in configurations += 1 }
            }
            XCTAssertEqual(configurations, 0)
            XCTAssertEqual(panel.cells.mapValues(\.frame), frames)
            XCTAssertEqual(panel.horizontalScroll.frame, scrollFrame)
            // Selection/theme changes must still refresh stable row geometry.
            panel.updateLines(lineCount: 10, lineHeight: 22, refresh: true) { _, _, _ in configurations += 1 }
            XCTAssertEqual(configurations, 10)
        }
    }

    func testRebindingHunkReusesHostingViewsAndRestoresItsOwnOffset() {
        MainActor.assumeIsolated {
            let panel = makePanel(width: 10_000, offset: 2_500)
            panel.updateLines(lineCount: 1_000_000, lineHeight: 22) { _, _, _ in }
            let originalCells = Set(panel.cells.values.map(ObjectIdentifier.init))
            panel.updateGeometry(visible: CGRect(x: 0, y: 0, width: 600, height: 600),
                                 headerHeight: 32, lineHeight: 22, lineCount: 2,
                                 contentWidth: 800, restoredOffset: 100)
            var configured: [Int] = []
            panel.updateLines(lineCount: 2, lineHeight: 22, refresh: true) { _, line, _ in configured.append(line) }
            XCTAssertEqual(configured, [0, 1])
            XCTAssertEqual(panel.horizontalOffset, 100, accuracy: 0.5)
            panel.updateGeometry(visible: CGRect(x: 0, y: 0, width: 600, height: 600),
                                 headerHeight: 32, lineHeight: 22, lineCount: 1_000_000,
                                 contentWidth: 10_000, restoredOffset: 2_500)
            panel.updateLines(lineCount: 1_000_000, lineHeight: 22, refresh: true) { _, _, _ in }
            XCTAssertEqual(Set(panel.cells.values.map(ObjectIdentifier.init)), originalCells)
            XCTAssertEqual(panel.horizontalOffset, 2_500, accuracy: 0.5)
        }
    }

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
