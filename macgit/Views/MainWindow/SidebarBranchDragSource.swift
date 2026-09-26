//
//  SidebarBranchDragSource.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
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

import AppKit
import SwiftUI

struct SidebarBranchDragSource: NSViewRepresentable {
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let dragPayload: () -> GitDragPayload
    let dragTitle: String
    let onDragEnded: (GitDragPayload) -> Void

    func makeNSView(context: Context) -> DragSourceView {
        DragSourceView(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            dragPayload: dragPayload,
            dragTitle: dragTitle,
            onDragEnded: onDragEnded
        )
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.onTap = onTap
        nsView.onDoubleTap = onDoubleTap
        nsView.dragPayload = dragPayload
        nsView.dragTitle = dragTitle
        nsView.onDragEnded = onDragEnded
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var onTap: () -> Void
        var onDoubleTap: () -> Void
        var dragPayload: () -> GitDragPayload
        var dragTitle: String
        var onDragEnded: (GitDragPayload) -> Void

        private var dragStartEvent: NSEvent?
        private var activeDragPayload: GitDragPayload?

        init(
            onTap: @escaping () -> Void,
            onDoubleTap: @escaping () -> Void,
            dragPayload: @escaping () -> GitDragPayload,
            dragTitle: String,
            onDragEnded: @escaping (GitDragPayload) -> Void
        ) {
            self.onTap = onTap
            self.onDoubleTap = onDoubleTap
            self.dragPayload = dragPayload
            self.dragTitle = dragTitle
            self.onDragEnded = onDragEnded
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            dragStartEvent = event
            // AppKit owns double-click timing; selection never waits for a tap recognizer.
            onTap()
            if event.clickCount == 2 {
                dragStartEvent = nil
                onDoubleTap()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard activeDragPayload == nil, let dragStartEvent else {
                return
            }
            let start = dragStartEvent.locationInWindow
            let location = event.locationInWindow
            guard hypot(location.x - start.x, location.y - start.y) >= 4 else {
                return
            }

            let payload = dragPayload()
            guard let item = SidebarBranchDropTarget.DropTargetView.pasteboardItem(for: payload) else {
                onDragEnded(payload)
                return
            }

            activeDragPayload = payload
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            let image = dragImage(title: dragTitle)
            draggingItem.setDraggingFrame(
                NSRect(
                    x: 0,
                    y: max(0, bounds.midY - image.size.height / 2),
                    width: image.size.width,
                    height: image.size.height
                ),
                contents: image
            )
            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            dragStartEvent = nil
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            dragStartEvent = nil
            if let activeDragPayload {
                onDragEnded(activeDragPayload)
            }
            activeDragPayload = nil
        }

        private func dragImage(title: String) -> NSImage {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
            let text = NSString(string: title)
            let textSize = text.size(withAttributes: attributes)
            let imageSize = NSSize(width: max(96, textSize.width + 28), height: 28)
            let image = NSImage(size: imageSize)

            image.lockFocus()
            NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
            NSBezierPath(
                roundedRect: NSRect(origin: .zero, size: imageSize),
                xRadius: 6,
                yRadius: 6
            ).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(
                roundedRect: NSRect(x: 0.5, y: 0.5, width: imageSize.width - 1, height: imageSize.height - 1),
                xRadius: 6,
                yRadius: 6
            ).stroke()
            text.draw(
                at: NSPoint(x: 14, y: (imageSize.height - textSize.height) / 2),
                withAttributes: attributes
            )
            image.unlockFocus()

            return image
        }
    }
}
