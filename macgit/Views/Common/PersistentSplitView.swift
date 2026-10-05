//
//  PersistentSplitView.swift
//  macgit
//

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
import SwiftUI

final class ResizableCursorSplitView: NSSplitView {
    private static let cursorHitSlop: CGFloat = 8

    static func dividerCursor(forSplitViewIsVertical isVertical: Bool) -> NSCursor {
        isVertical ? .resizeLeftRight : .resizeUpDown
    }

    static func dividerCursorRect(for dividerRect: NSRect, splitViewIsVertical isVertical: Bool) -> NSRect {
        if isVertical {
            dividerRect.insetBy(dx: -cursorHitSlop, dy: 0)
        } else {
            dividerRect.insetBy(dx: 0, dy: -cursorHitSlop)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        let dividerCount = max(arrangedSubviews.count - 1, 0)
        guard dividerCount > 0 else { return }

        let cursor = Self.dividerCursor(forSplitViewIsVertical: isVertical)
        for dividerIndex in 0..<dividerCount {
            addCursorRect(
                Self.dividerCursorRect(
                    for: dividerRect(at: dividerIndex),
                    splitViewIsVertical: isVertical
                ),
                cursor: cursor
            )
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point) else { return nil }
        // hitTest receives a point in the superview's coordinates. Divider
        // frames are local, including NSSplitView's flipped y axis. Comparing
        // them directly creates a second, invisible divider over pane content.
        let localPoint = convert(point, from: superview)
        return containsDividerCursorRect(localPoint) ? self : hitView
    }

    private func containsDividerCursorRect(_ point: NSPoint) -> Bool {
        let dividerCount = max(arrangedSubviews.count - 1, 0)
        guard dividerCount > 0 else { return false }

        return (0..<dividerCount).contains { dividerIndex in
            Self.dividerCursorRect(
                for: dividerRect(at: dividerIndex),
                splitViewIsVertical: isVertical
            ).contains(point)
        }
    }

    private func dividerRect(at dividerIndex: Int) -> NSRect {
        let leadingSubview = arrangedSubviews[dividerIndex]

        if isVertical {
            return NSRect(
                x: leadingSubview.frame.maxX,
                y: bounds.minY,
                width: dividerThickness,
                height: bounds.height
            )
        } else {
            return NSRect(
                x: bounds.minX,
                y: leadingSubview.frame.maxY,
                width: bounds.width,
                height: dividerThickness
            )
        }
    }
}

// MARK: - Split View Configuration

func configurePersistentSplitView(
    _ splitView: NSSplitView,
    autosaveName: String,
    isVertical: Bool
) {
    splitView.isVertical = isVertical
    splitView.dividerStyle = .thin
    splitView.autosaveName = autosaveName
}

// MARK: - Persistent VSplit (vertical divider, top/bottom)

struct PersistentVSplit<Top: View, Bottom: View>: NSViewControllerRepresentable {
    let autosaveName: String
    var minimumTopHeight: CGFloat? = nil
    var minimumBottomHeight: CGFloat? = nil
    @ViewBuilder let top: () -> Top
    @ViewBuilder let bottom: () -> Bottom

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var topController: NSHostingController<Top>?
        var bottomController: NSHostingController<Bottom>?
    }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let topController = NSHostingController(rootView: top())
        let bottomController = NSHostingController(rootView: bottom())

        // Explicit split limits let AppKit own the viewport without asking the
        // hosted content to recompute its fitting sizes during scrolling.
        if minimumTopHeight != nil { topController.sizingOptions = [] }
        if minimumBottomHeight != nil { bottomController.sizingOptions = [] }

        let coordinator = context.coordinator
        coordinator.topController = topController
        coordinator.bottomController = bottomController

        let splitController = NSSplitViewController()
        splitController.splitView = ResizableCursorSplitView()
        configurePersistentSplitView(
            splitController.splitView,
            autosaveName: autosaveName,
            isVertical: false
        )

        let topItem = NSSplitViewItem(viewController: topController)
        let bottomItem = NSSplitViewItem(viewController: bottomController)
        if let minimumTopHeight { topItem.minimumThickness = minimumTopHeight }
        if let minimumBottomHeight { bottomItem.minimumThickness = minimumBottomHeight }

        splitController.addSplitViewItem(topItem)
        splitController.addSplitViewItem(bottomItem)

        return splitController
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        context.coordinator.topController?.rootView = top()
        context.coordinator.bottomController?.rootView = bottom()
    }
}

// MARK: - Persistent HSplit (horizontal divider, left/right)

struct PersistentHSplit<Left: View, Right: View>: NSViewControllerRepresentable {
    let autosaveName: String
    var minimumLeftWidth: CGFloat? = nil
    var minimumRightWidth: CGFloat? = nil
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var leftController: NSHostingController<Left>?
        var rightController: NSHostingController<Right>?
    }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let leftController = NSHostingController(rootView: left())
        let rightController = NSHostingController(rootView: right())

        if minimumLeftWidth != nil { leftController.sizingOptions = [] }
        if minimumRightWidth != nil { rightController.sizingOptions = [] }

        let coordinator = context.coordinator
        coordinator.leftController = leftController
        coordinator.rightController = rightController

        let splitController = NSSplitViewController()
        splitController.splitView = ResizableCursorSplitView()
        configurePersistentSplitView(
            splitController.splitView,
            autosaveName: autosaveName,
            isVertical: true
        )

        let leftItem = NSSplitViewItem(viewController: leftController)
        let rightItem = NSSplitViewItem(viewController: rightController)
        if let minimumLeftWidth { leftItem.minimumThickness = minimumLeftWidth }
        if let minimumRightWidth { rightItem.minimumThickness = minimumRightWidth }

        splitController.addSplitViewItem(leftItem)
        splitController.addSplitViewItem(rightItem)

        return splitController
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        context.coordinator.leftController?.rootView = left()
        context.coordinator.rightController?.rootView = right()
    }
}
