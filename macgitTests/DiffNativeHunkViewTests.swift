// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import XCTest

@testable import macgit

@MainActor
final class DiffNativeHunkViewTests: XCTestCase {
    func testSmallHunkDoesNotRelayoutCanvasForEachVerticalScrollTick() {
        let panel = DiffNativeHunkView(frame: CGRect(x: 0, y: 0, width: 600, height: 252))
        func moveViewport(to y: CGFloat) {
            panel.updateGeometry(
                visible: CGRect(x: 0, y: y, width: 600, height: 600),
                headerHeight: 32, lineHeight: 22, lineCount: 10,
                contentWidth: 1_000, restoredOffset: nil)
        }
        moveViewport(to: -400)
        let frame = panel.canvas.frame
        let scrollFrame = panel.horizontalScroll.frame
        let origin = panel.canvas.contentOrigin
        for y in stride(from: CGFloat(-399), through: 250, by: 1) {
            panel.canvas.needsDisplay = false
            moveViewport(to: y)
            XCTAssertFalse(panel.canvas.needsDisplay)
        }
        XCTAssertEqual(panel.canvas.frame, frame)
        XCTAssertEqual(panel.canvas.contentOrigin, origin)
        XCTAssertEqual(panel.horizontalScroll.frame, scrollFrame)
        XCTAssertTrue(panel.canvas.subviews.isEmpty)
    }

    func testRebindingHunkReusesCanvasAndRestoresItsOwnOffset() {
        let panel = makePanel(width: 10_000, offset: 2_500)
        let canvas = panel.canvas
        panel.updateGeometry(
            visible: CGRect(x: 0, y: 0, width: 600, height: 600),
            headerHeight: 32, lineHeight: 22, lineCount: 2,
            contentWidth: 800, restoredOffset: 100)
        XCTAssertEqual(panel.horizontalOffset, 100, accuracy: 0.5)
        panel.updateGeometry(
            visible: CGRect(x: 0, y: 0, width: 600, height: 600),
            headerHeight: 32, lineHeight: 22, lineCount: 1_000_000,
            contentWidth: 10_000, restoredOffset: 2_500)
        XCTAssertTrue(panel.canvas === canvas)
        XCTAssertEqual(panel.horizontalOffset, 2_500, accuracy: 0.5)
    }

    func testHunksOwnIndependentNativeHorizontalOffsets() {
        let first = makePanel(width: 1_000_000)
        let second = makePanel(width: 800)
        first.horizontalScroll.contentView.scroll(to: CGPoint(x: 50_000, y: 0))
        first.horizontalScroll.reflectScrolledClipView(first.horizontalScroll.contentView)
        XCTAssertEqual(first.horizontalOffset, 50_000, accuracy: 0.5)
        XCTAssertEqual(first.canvas.contentOrigin.x, 50_000, accuracy: 0.5)
        XCTAssertEqual(second.horizontalOffset, 0)
        XCTAssertEqual(second.horizontalScroll.documentView?.frame.width, 800)
        XCTAssertEqual(first.header.frame.width, 600)
    }

    func testMillionRowHunkKeepsCanvasSizeAndSubviewCountBounded() {
        let panel = makePanel(width: 1_000_000)
        let canvas = panel.canvas
        for y: CGFloat in [0, 10, 15_000_000] {
            panel.updateGeometry(
                visible: CGRect(x: 0, y: y, width: 600, height: 600),
                headerHeight: 32, lineHeight: 22, lineCount: 1_000_000,
                contentWidth: 1_000_000, restoredOffset: nil)
            XCTAssertLessThanOrEqual(canvas.frame.width, 600)
            XCTAssertLessThanOrEqual(canvas.frame.height, 600 + 2 * 16 * 22)
            XCTAssertTrue(canvas.subviews.isEmpty)
            XCTAssertEqual(panel.horizontalScroll.documentView?.subviews.count, 1)
            XCTAssertTrue(panel.canvas === canvas)
        }
        XCTAssertGreaterThan(canvas.contentOrigin.y, 14_999_000)
    }

    func testRestoredOffsetWaitsForAsynchronousWidthMeasurement() {
        let panel = makePanel(width: 0, offset: 2_500)
        XCTAssertEqual(panel.horizontalOffset, 2_500)
        panel.updateGeometry(
            visible: CGRect(x: 0, y: 0, width: 600, height: 600),
            headerHeight: 32, lineHeight: 22, lineCount: 1_000_000,
            contentWidth: 10_000, restoredOffset: nil)
        XCTAssertEqual(panel.horizontalScroll.contentView.bounds.minX, 2_500, accuracy: 0.5)
        let restored = makePanel(width: 10_000, offset: panel.horizontalOffset)
        XCTAssertEqual(restored.horizontalOffset, 2_500, accuracy: 0.5)
    }

    func testCanvasHitTestingUsesScaledVerticalSliceAndIgnoresHorizontalOffset() {
        let store = DiffNativeTextStore()
        let lines = (0..<100).map {
            DiffLine(oldLineNumber: nil, newLineNumber: $0 + 1, text: "row \($0)", type: .added)
        }
        let canvas = DiffHunkCanvas()
        canvas.updateViewport(
            origin: CGPoint(x: 900, y: 440), size: CGSize(width: 600, height: 440))
        canvas.configure(
            hunk: DiffHunk(header: "@@", lines: lines), textStore: store,
            selectedLineIDs: [], lineHeight: 44)
        XCTAssertEqual(canvas.lineIndex(at: CGPoint(x: 1, y: 0)), 10)
        XCTAssertEqual(canvas.lineIndex(at: CGPoint(x: 599, y: 43)), 10)
        XCTAssertEqual(canvas.lineIndex(at: CGPoint(x: 1, y: 44)), 11)
        XCTAssertNil(canvas.lineIndex(at: CGPoint(x: 1, y: -1)))
        XCTAssertNil(canvas.lineIndex(at: CGPoint(x: 601, y: 0)))
    }

    @MainActor
    private func makePanel(width: CGFloat, offset: CGFloat? = nil) -> DiffNativeHunkView {
        let panel = DiffNativeHunkView(frame: CGRect(x: 0, y: 0, width: 600, height: 22_000_032))
        panel.updateGeometry(
            visible: CGRect(x: 0, y: 0, width: 600, height: 600),
            headerHeight: 32, lineHeight: 22, lineCount: 1_000_000,
            contentWidth: width, restoredOffset: offset)
        return panel
    }
}
