// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

@MainActor
final class HistoryTableColumnLayoutTests: XCTestCase {
    private func makeLayout() -> HistoryTableColumnLayout {
        HistoryTableColumnLayout(
            widths: ["graph": 200, "message": 400, "author": 180, "date": 140, "commit": 80],
            viewportWidth: 1_000
        )
    }

    func testDraggingPastViewportPreservesOtherColumnsAndOverflow() async {
        var layout = makeLayout()
        layout.resizeColumn("graph", to: 600, viewportWidth: 1_000)

        XCTAssertEqual(layout.widths["message"], 400)
        XCTAssertEqual(layout.widths.values.reduce(0, +), 1_400)
        XCTAssertEqual(layout.width(for: "graph", minimumWidth: 60), 600)
        XCTAssertEqual(layout.width(for: "message", minimumWidth: 120), 400)
    }

    func testMinimumWidthDoesNotAlterSavedAbsoluteWidth() async {
        let layout = makeLayout()
        XCTAssertEqual(layout.width(for: "author", minimumWidth: 200), 200)
        XCTAssertEqual(layout.width(for: "author", minimumWidth: 140), 180)
        XCTAssertEqual(layout.viewportWidth, 1_000)
    }

    func testDraggingAfterWindowResizePreservesOtherColumns() async {
        var layout = makeLayout()
        layout.resizeColumn("graph", to: 300, viewportWidth: 500)

        XCTAssertEqual(layout.viewportWidth, 500)
        XCTAssertEqual(layout.widths["message"], 400)
        XCTAssertEqual(layout.widths["author"], 180)
        XCTAssertEqual(layout.width(for: "author", minimumWidth: 140), 180)
        XCTAssertEqual(layout.width(for: "graph", minimumWidth: 60), 300)
    }

    func testSavedLayoutRoundTripPreservesOverflowAndReferenceViewport() async throws {
        var layout = makeLayout()
        layout.resizeColumn("graph", to: 800, viewportWidth: 1_000)
        let restored = try JSONDecoder().decode(
            HistoryTableColumnLayout.self,
            from: JSONEncoder().encode(layout)
        )

        XCTAssertTrue(restored.isValid)
        XCTAssertEqual(restored.widths, layout.widths)
        XCTAssertEqual(restored.viewportWidth, 1_000)
        XCTAssertEqual(restored.width(for: "graph", minimumWidth: 60), 800)
    }

    func testInvalidPersistedLayoutIsRejected() async {
        XCTAssertFalse(HistoryTableColumnLayout(widths: makeLayout().widths, viewportWidth: 0).isValid)
        XCTAssertFalse(HistoryTableColumnLayout(widths: ["graph": 200], viewportWidth: 1_000).isValid)
        var widths = makeLayout().widths
        widths["graph"] = .infinity
        XCTAssertFalse(HistoryTableColumnLayout(widths: widths, viewportWidth: 1_000).isValid)
    }
}
