//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import AppKit
import XCTest
@testable import macgit

@MainActor
final class RepositoryWindowRequestTests: XCTestCase {
    func testRepositoryPickerRequestsHaveUniqueWindowIdentity() {
        let first = RepositoryWindowRequest.repositoryPicker()
        let second = RepositoryWindowRequest.repositoryPicker()

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(first.repositoryURL)
        XCTAssertEqual(first.initialPresentation, .repositoryPicker)
        XCTAssertFalse(first.shouldFitVisibleScreen)
        XCTAssertNil(first.initialWindowFrame)
    }

    func testRepositoryRequestRoundTripsThroughWindowGroupCoding() throws {
        let repositoryURL = URL(fileURLWithPath: "/tmp/example-repository")
        let initialWindowFrame = RepositoryWindowRequest.InitialWindowFrame(
            CGRect(x: 120, y: 80, width: 1040, height: 720)
        )
        let request = RepositoryWindowRequest.repository(
            repositoryURL,
            shouldFitVisibleScreen: true,
            initialWindowFrame: initialWindowFrame
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(
            RepositoryWindowRequest.self,
            from: encoded
        )

        XCTAssertEqual(decoded, request)
    }

    func testWindowContextAcceptsOnlyItsOwningWindow() {
        let owningWindow = NSWindow()
        let otherWindow = NSWindow()
        let context = RepositoryWindowContext()
        context.window = owningWindow

        XCTAssertTrue(
            context.owns(Notification(name: .toolbarAction, object: owningWindow))
        )
        XCTAssertFalse(
            context.owns(Notification(name: .toolbarAction, object: otherWindow))
        )
        XCTAssertFalse(
            context.owns(Notification(name: .toolbarAction, object: nil))
        )
    }
}
