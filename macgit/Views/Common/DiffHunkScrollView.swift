// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Route a whole gesture (including zero-delta end and momentum events) to one
/// native scroll view. AppKit remains responsible for deceleration and elasticity.
final class DiffHunkScrollView: NSScrollView {
    weak var verticalScrollView: NSScrollView?
    private var horizontalGesture: Bool?

    override func scrollWheel(with event: NSEvent) {
        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if event.phase.contains(.began) || (!phased) { horizontalGesture = nil }
        if horizontalGesture == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
            horizontalGesture = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                || event.modifierFlags.contains(.shift)
        }
        if horizontalGesture == true {
            super.scrollWheel(with: event)
        } else {
            verticalScrollView?.scrollWheel(with: event)
        }
        // Keep the axis after phase.ended: momentum.began may follow it.
        if !phased || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) {
            horizontalGesture = nil
        }
    }
}
