// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import WebKit

/// The README expands to its document height; its enclosing SwiftUI scroll view
/// owns vertical gestures. WebKit still handles horizontal code/table scrolling.
final class RepositoryReadmeContentView: WKWebView {
    private var scrollMonitor: Any?
    private var horizontalGesture: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopForwardingScroll()
        guard window != nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window,
                  self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
                  let hit = self.window?.contentView?.hitTest(event.locationInWindow),
                  hit === self || hit.isDescendant(of: self) else { return event }
            return self.forwardVerticalScroll(event) ? nil : event
        }
    }

    func stopForwardingScroll() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        horizontalGesture = nil
    }

    private func forwardVerticalScroll(_ event: NSEvent) -> Bool {
        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if event.phase.contains(.began) || !phased { horizontalGesture = nil }
        if horizontalGesture == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
            horizontalGesture = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || event.modifierFlags.contains(.shift)
        }
        defer {
            if !phased || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) { horizontalGesture = nil }
        }
        guard horizontalGesture != true else { return false }
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                scrollView.scrollWheel(with: event)
                return true
            }
            ancestor = view.superview
        }
        return false
    }
}
