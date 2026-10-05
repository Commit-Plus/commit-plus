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
@testable import macgit
import XCTest

final class PersistentSplitViewTests: XCTestCase {
    func testLeftRightSplitUsesHorizontalResizeCursor() {
        XCTAssertIdentical(
            ResizableCursorSplitView.dividerCursor(forSplitViewIsVertical: true),
            NSCursor.resizeLeftRight
        )
    }

    func testTopBottomSplitUsesVerticalResizeCursor() {
        XCTAssertIdentical(
            ResizableCursorSplitView.dividerCursor(forSplitViewIsVertical: false),
            NSCursor.resizeUpDown
        )
    }

    func testDividerHitAreaExpandsAroundThinDivider() {
        let dividerRect = ResizableCursorSplitView.dividerCursorRect(
            for: NSRect(x: 200, y: 0, width: 1, height: 100),
            splitViewIsVertical: true
        )

        XCTAssertGreaterThanOrEqual(dividerRect.width, 8)
        XCTAssertTrue(dividerRect.contains(NSPoint(x: 203, y: 50)))
    }

    func testSplitViewConfigurationUsesNativeAutosaveNameForGlobalPersistence() {
        let splitView = ResizableCursorSplitView()

        configurePersistentSplitView(splitView, autosaveName: "FileStatusMainSplit", isVertical: true)

        XCTAssertEqual(splitView.autosaveName, "FileStatusMainSplit")
        XCTAssertTrue(splitView.isVertical)
        XCTAssertEqual(splitView.dividerStyle, .thin)
        XCTAssertNil(splitView.delegate)
    }

    func testTopBottomSplitDoesNotInterceptContentAtMirroredDividerPosition() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 700))
        let splitView = makeSplit(in: parent, isVertical: false)
        let bottomPane = splitView.arrangedSubviews[1]

        // NSSplitView is flipped, while this parent is not. Local y=500 maps
        // to parent y=200, which used to be mistaken for the local divider.
        let contentPoint = splitView.convert(NSPoint(x: 400, y: 500), to: parent)
        XCTAssertIdentical(splitView.hitTest(contentPoint), bottomPane)

        let dividerPoint = splitView.convert(NSPoint(x: 400, y: 204), to: parent)
        XCTAssertIdentical(splitView.hitTest(dividerPoint), splitView)
    }

    func testLeftRightSplitDoesNotInterceptContentAtTranslatedDividerPosition() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 700))
        let splitView = makeSplit(in: parent, isVertical: true)
        let leftPane = splitView.arrangedSubviews[0]

        // Local x=100 maps to parent x=200 because the split is inset by 100.
        let contentPoint = splitView.convert(NSPoint(x: 100, y: 400), to: parent)
        XCTAssertIdentical(splitView.hitTest(contentPoint), leftPane)

        let dividerPoint = splitView.convert(NSPoint(x: 204, y: 400), to: parent)
        XCTAssertIdentical(splitView.hitTest(dividerPoint), splitView)
    }

    private func makeSplit(in parent: NSView, isVertical: Bool) -> ResizableCursorSplitView {
        let splitView = ResizableCursorSplitView(
            frame: NSRect(x: 100, y: 100, width: 600, height: 600)
        )
        splitView.isVertical = isVertical
        splitView.dividerStyle = .thin
        parent.addSubview(splitView)
        let firstPane = NSView()
        let secondPane = NSView()
        splitView.addArrangedSubview(firstPane)
        splitView.addArrangedSubview(secondPane)
        let trailingOrigin = 200 + splitView.dividerThickness
        if isVertical {
            firstPane.frame = NSRect(x: 0, y: 0, width: 200, height: 600)
            secondPane.frame = NSRect(x: trailingOrigin, y: 0, width: 600 - trailingOrigin, height: 600)
        } else {
            firstPane.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
            secondPane.frame = NSRect(x: 0, y: trailingOrigin, width: 600, height: 600 - trailingOrigin)
        }
        return splitView
    }
}
