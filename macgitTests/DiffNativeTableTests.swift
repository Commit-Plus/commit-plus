// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI
import XCTest

@testable import macgit

@MainActor
final class DiffNativeTableTests: XCTestCase {
    func testHundredHunksKeepOnlyViewportPanelsAndDoNotRehostRowsOnScroll() {
        let hunks = (0..<100).map { hunk in
            DiffHunk(
                header: "@@ hunk \(hunk) @@",
                lines: (0..<10).map { line in
                    DiffLine(
                        oldLineNumber: nil, newLineNumber: hunk * 10 + line,
                        text: "let value = \(line)", type: .added)
                })
        }
        let model = makeModel(hunks)
        let coordinator = model.makeCoordinator()
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = coordinator.document
        coordinator.observe(scroll)
        coordinator.connectTextStore()
        coordinator.apply(model, scroll: scroll)
        defer { coordinator.stop() }
        for y: CGFloat in [0, 1_000, 8_000, 20_000, 0] {
            scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            let panels = coordinator.document.subviews.compactMap { $0 as? DiffNativeHunkView }
            XCTAssertFalse(panels.isEmpty)
            XCTAssertLessThanOrEqual(panels.count, 14)
            for panel in panels {
                XCTAssertTrue(panel.canvas.subviews.isEmpty)
                XCTAssertLessThanOrEqual(panel.canvas.frame.width, 800)
            }
        }
        #if DEBUG
            DiffRenderStats.reset()
            for y in 1...10 {
                scroll.contentView.scroll(to: CGPoint(x: 0, y: CGFloat(y)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            XCTAssertEqual(DiffRenderStats.headerHostAssignments, 0)
        #endif
    }

    func testSameHunkIdentityWithChangedContentRecomputesGeometry() {
        let id = UUID()
        func hunk(count: Int) -> DiffHunk {
            DiffHunk(
                id: id, header: "@@",
                lines: (0..<count).map {
                    DiffLine(oldLineNumber: nil, newLineNumber: $0, text: "line", type: .added)
                })
        }
        let model = makeModel([hunk(count: 1)])
        let coordinator = model.makeCoordinator()
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 100))
        scroll.documentView = coordinator.document
        coordinator.apply(model, scroll: scroll)
        let before = coordinator.document.frame.height
        coordinator.apply(makeModel([hunk(count: 100)]), scroll: scroll)
        XCTAssertGreaterThan(coordinator.document.frame.height, before)
        XCTAssertEqual(
            coordinator.document.frame.height, DiffHunkGeometry(lineCounts: [100], scale: 1).height)
        coordinator.stop()
    }

    @MainActor
    private func makeModel(_ hunks: [DiffHunk]) -> DiffNativeTable<Text> {
        DiffNativeTable(
            hunks: hunks, textScale: 1, syntaxHighlighting: false,
            fileExtension: "swift", selectedLineIDs: [],
            onLineTap: { _, _, _ in }, lineMenu: { _, _ in NSMenu() }
        ) { hunk in
            Text(hunk.header)
        }
    }
}
