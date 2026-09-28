// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

@MainActor
final class RepositoryWindowLifecycleControllerTests: XCTestCase {
    func testFirstAppearanceRegistersWindow() {
        let controller = RepositoryWindowLifecycleController()
        let id = UUID()

        XCTAssertTrue(controller.windowDidAppear(id: id))
        XCTAssertEqual(controller.activeWindowCount, 1)
    }

    func testRepeatedAppearanceDoesNotDuplicateWindow() {
        let controller = RepositoryWindowLifecycleController()
        let id = UUID()

        XCTAssertTrue(controller.windowDidAppear(id: id))
        XCTAssertFalse(controller.windowDidAppear(id: id))
        XCTAssertEqual(controller.activeWindowCount, 1)
    }

    func testClosingOneOfMultipleWindowsDoesNotRestoreWelcome() {
        let controller = RepositoryWindowLifecycleController()
        let first = UUID()
        let second = UUID()
        controller.windowDidAppear(id: first)
        controller.windowDidAppear(id: second)

        XCTAssertFalse(controller.windowDidDisappear(id: first))
        XCTAssertEqual(controller.activeWindowCount, 1)
    }

    func testClosingLastWindowRestoresWelcome() {
        let controller = RepositoryWindowLifecycleController()
        let id = UUID()
        controller.windowDidAppear(id: id)

        XCTAssertTrue(controller.windowDidDisappear(id: id))
        XCTAssertEqual(controller.activeWindowCount, 0)
        XCTAssertFalse(controller.windowDidDisappear(id: id))
    }
}
