// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class SheetPresentationCoordinatorTests: XCTestCase {
    func testReplacementClearsPreviousBindingAndIgnoresItsLateRelease() async {
        await MainActor.run {
            let coordinator = SheetPresentationCoordinator()
            let commit = UUID()
            let profile = UUID()
            var commitPresented = true
            var profilePresented = true
            coordinator.present(commit) { commitPresented = false }
            coordinator.present(profile) { profilePresented = false }
            XCTAssertFalse(commitPresented)
            XCTAssertTrue(profilePresented)

            coordinator.release(commit)
            coordinator.present(UUID()) { }
            XCTAssertFalse(profilePresented)
        }
    }

    func testRepeatedPresentationDoesNotDismissItself() async {
        await MainActor.run {
            let coordinator = SheetPresentationCoordinator()
            let id = UUID()
            var dismissCount = 0
            coordinator.present(id) { dismissCount += 1 }
            coordinator.present(id) { dismissCount += 1 }
            XCTAssertEqual(dismissCount, 0)
            coordinator.release(id)
            coordinator.present(UUID()) { }
            XCTAssertEqual(dismissCount, 0)
        }
    }

    func testSeparateWindowsAndNestedScopesDoNotDismissEachOther() async {
        await MainActor.run {
            let window = SheetPresentationCoordinator()
            let otherWindow = SheetPresentationCoordinator()
            let childScope = SheetPresentationCoordinator()
            var parentPresented = true
            var otherPresented = true
            var childPresented = true
            window.present(UUID()) { parentPresented = false }
            otherWindow.present(UUID()) { otherPresented = false }
            childScope.present(UUID()) { childPresented = false }
            childScope.present(UUID()) { }
            XCTAssertTrue(parentPresented)
            XCTAssertTrue(otherPresented)
            XCTAssertFalse(childPresented)
        }
    }
}
