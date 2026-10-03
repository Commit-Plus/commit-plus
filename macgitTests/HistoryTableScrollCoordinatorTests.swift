// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import XCTest
@testable import macgit

@MainActor
final class HistoryTableScrollCoordinatorTests: XCTestCase {
    func testViewportChangeDuringHeaderDragDoesNotRestoreOldWidths() async {
        let fixture = makeFixture()
        let graph = fixture.table.tableColumns[0]
        let originalWidth = graph.width
        fixture.header.testResizedColumn = 0
        graph.width = originalWidth + 1

        // A scroller transition can change the clip frame before the column's
        // resize notification arrives. The persisted width is still the old one.
        let clipView = fixture.scrollView.contentView
        clipView.setFrameSize(NSSize(width: clipView.bounds.width - 15, height: 280))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clipView)

        XCTAssertEqual(graph.width, originalWidth + 1, accuracy: 0.01)
        XCTAssertTrue(fixture.table.tableColumns.allSatisfy { $0.resizingMask == .userResizingMask })
        withExtendedLifetime(fixture.coordinator) {}
    }

    func testResizeNotificationRecordsOverflowWithoutRetiling() async throws {
        let fixture = makeFixture()
        let graph = fixture.table.tableColumns[0]
        let messageWidth = fixture.table.tableColumns[1].width
        fixture.header.testResizedColumn = 0
        graph.width += 1
        let tileCount = fixture.table.tileCount

        NotificationCenter.default.post(name: NSTableView.columnDidResizeNotification, object: fixture.table)

        XCTAssertEqual(fixture.table.tileCount, tileCount)
        XCTAssertEqual(fixture.table.tableColumns[1].width, messageWidth)
        let data = try XCTUnwrap(fixture.defaults.data(forKey: "history.tableColumnLayout"))
        let saved = try JSONDecoder().decode(HistoryTableColumnLayout.self, from: data)
        XCTAssertEqual(try XCTUnwrap(saved.widths["graph"]), Double(graph.width), accuracy: 0.01)
        withExtendedLifetime(fixture.coordinator) {}
    }

    func testFinalResizeNotificationAfterHeaderTrackingPreservesMessageWidth() async throws {
        let fixture = makeFixture()
        let message = fixture.table.tableColumns[1]
        let viewportWidth = fixture.scrollView.contentView.bounds.width
        let resizedWidth = message.width + 120
        message.width = resizedWidth
        fixture.header.testResizedColumn = -1
        let tileCount = fixture.table.tileCount

        NotificationCenter.default.post(
            name: NSTableView.columnDidResizeNotification,
            object: fixture.table,
            userInfo: ["NSTableColumn": message]
        )

        XCTAssertEqual(fixture.table.tileCount, tileCount)
        let data = try XCTUnwrap(fixture.defaults.data(forKey: "history.tableColumnLayout"))
        let saved = try JSONDecoder().decode(HistoryTableColumnLayout.self, from: data)
        XCTAssertEqual(try XCTUnwrap(saved.widths["message"]), Double(resizedWidth), accuracy: 0.01)

        // A later viewport change must preserve the latest absolute user width.
        let clipView = fixture.scrollView.contentView
        clipView.setFrameSize(NSSize(width: viewportWidth + 100, height: 280))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clipView)

        XCTAssertEqual(
            message.width,
            resizedWidth,
            accuracy: 0.01
        )
        withExtendedLifetime(fixture.coordinator) {}
    }

    func testExternalResizeAndRepeatedAttachmentPreserveAllColumnWidths() async {
        let fixture = makeFixture()
        let widths = fixture.table.tableColumns.map(\.width)
        let marker = NSView()
        fixture.table.addSubview(marker)
        let clipView = fixture.scrollView.contentView

        for width in [CGFloat(600), CGFloat(1_400)] {
            clipView.setFrameSize(NSSize(width: width, height: 280))
            NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: clipView)
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clipView)
            // AppKit may tile in response to resize notifications. Measure only
            // whether attaching the coordinator again causes another tile.
            let tileCount = fixture.table.tileCount
            XCTAssertTrue(fixture.coordinator.attach(from: marker))

            XCTAssertEqual(fixture.table.tableColumns.map(\.width), widths)
            XCTAssertEqual(fixture.table.tileCount, tileCount)
        }
        withExtendedLifetime(fixture.coordinator) {}
    }

    private func makeFixture() -> (
        coordinator: HistoryTableScrollCoordinator,
        scrollView: NSScrollView,
        table: LayoutCountingHistoryTable,
        header: ResizingHistoryHeader,
        defaults: UserDefaults
    ) {
        let suiteName = "HistoryTableScrollCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 300))
        let table = LayoutCountingHistoryTable(frame: scrollView.bounds)
        let header = ResizingHistoryHeader()
        table.headerView = header
        for title in ["Graph", "Message", "Author", "Date", "Commit"] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
            column.title = title
            column.minWidth = 50
            column.maxWidth = 10_000
            table.addTableColumn(column)
        }
        scrollView.documentView = table
        let marker = NSView()
        table.addSubview(marker)
        let coordinator = HistoryTableScrollCoordinator(defaults: defaults)
        XCTAssertTrue(coordinator.attach(from: marker))
        return (coordinator, scrollView, table, header, defaults)
    }
}

@MainActor
private final class ResizingHistoryHeader: NSTableHeaderView {
    var testResizedColumn = -1
    override var resizedColumn: Int { testResizedColumn }
}

@MainActor
private final class LayoutCountingHistoryTable: NSTableView {
    var tileCount = 0
    override func tile() {
        tileCount += 1
        super.tile()
    }
}
