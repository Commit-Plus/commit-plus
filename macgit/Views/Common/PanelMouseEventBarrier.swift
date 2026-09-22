// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

/// Gives empty panel space a native hit target behind its interactive content.
struct PanelMouseEventBarrier: NSViewRepresentable {
    func makeNSView(context: Context) -> MouseEventBarrierView {
        MouseEventBarrierView()
    }

    func updateNSView(_ nsView: MouseEventBarrierView, context: Context) {}

    final class MouseEventBarrierView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // Do not forward background events through the responder chain to
        // repository content underneath the floating panel.
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {}
        override func mouseDragged(with event: NSEvent) {}
        override func rightMouseDown(with event: NSEvent) {}
        override func rightMouseUp(with event: NSEvent) {}
        override func rightMouseDragged(with event: NSEvent) {}
        override func otherMouseDown(with event: NSEvent) {}
        override func otherMouseUp(with event: NSEvent) {}
        override func otherMouseDragged(with event: NSEvent) {}
        override func scrollWheel(with event: NSEvent) {}
    }
}
