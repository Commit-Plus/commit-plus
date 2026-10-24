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
import SwiftUI

struct RepositoryAIChatResizeHandle: NSViewRepresentable {
    @Binding var panelWidth: CGFloat
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    var accessibilityLabel = "Resize AI Chat"
    /// Vertical inset of the drawn line, so it stops short of the panel's rounded corners.
    var lineInset = RepositoryToolbarShortcutPanel.cornerRadius

    func makeNSView(context: Context) -> ResizeHandleView {
        ResizeHandleView(
            panelWidth: panelWidth,
            minimumWidth: minimumWidth,
            maximumWidth: maximumWidth,
            accessibilityLabel: accessibilityLabel,
            lineInset: lineInset,
            onWidthChange: { panelWidth = $0 }
        )
    }

    func updateNSView(_ nsView: ResizeHandleView, context: Context) {
        nsView.panelWidth = panelWidth
        nsView.minimumWidth = minimumWidth
        nsView.maximumWidth = maximumWidth
        nsView.lineInset = lineInset
        nsView.onWidthChange = { panelWidth = $0 }
    }

    final class ResizeHandleView: NSView {
        var panelWidth: CGFloat
        var minimumWidth: CGFloat
        var maximumWidth: CGFloat
        var lineInset: CGFloat
        var onWidthChange: (CGFloat) -> Void

        private var dragStartScreenX: CGFloat?
        private var dragStartWidth: CGFloat?
        private var trackingArea: NSTrackingArea?
        private var isHovered = false

        init(
            panelWidth: CGFloat,
            minimumWidth: CGFloat,
            maximumWidth: CGFloat,
            accessibilityLabel: String,
            lineInset: CGFloat,
            onWidthChange: @escaping (CGFloat) -> Void
        ) {
            self.panelWidth = panelWidth
            self.minimumWidth = minimumWidth
            self.maximumWidth = maximumWidth
            self.lineInset = lineInset
            self.onWidthChange = onWidthChange
            super.init(frame: .zero)
            setAccessibilityRole(.splitter)
            setAccessibilityLabel(accessibilityLabel)
            setAccessibilityOrientation(.vertical)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func updateTrackingAreas() {
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseEnteredAndExited],
                owner: self
            )
            addTrackingArea(area)
            trackingArea = area
            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            dragStartScreenX = NSEvent.mouseLocation.x
            dragStartWidth = panelWidth
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStartScreenX, let dragStartWidth else { return }

            let horizontalDelta = dragStartScreenX - NSEvent.mouseLocation.x
            let newWidth = min(maximumWidth, max(minimumWidth, dragStartWidth + horizontalDelta))
            panelWidth = newWidth
            onWidthChange(newWidth)
        }

        override func mouseUp(with event: NSEvent) {
            dragStartScreenX = nil
            dragStartWidth = nil
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let isActive = dragStartScreenX != nil
            let lineWidth: CGFloat = isHovered || isActive ? 1.5 : 1
            let lineColor = NSColor.systemGray.withAlphaComponent(
                isHovered || isActive ? 0.55 : 0.4
            )
            let lineRect = NSRect(
                x: 0,
                y: lineInset,
                width: lineWidth,
                height: max(0, bounds.height - lineInset * 2)
            )
            lineColor.setFill()
            lineRect.fill()
        }
    }
}
