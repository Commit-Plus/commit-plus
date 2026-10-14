// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

@MainActor
final class PullRequestDetailWindowController: NSWindowController, NSWindowDelegate {
    private var onClose: (() -> Void)?

    init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func activateIfPresented() -> Bool {
        guard let window else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func show<Content: View>(title: String, content: Content, onClose: @escaping () -> Void) {
        if activateIfPresented() { return }
        self.onClose = onClose
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: min(1200, visibleFrame.width - 40),
                          height: min(800, visibleFrame.height - 80))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenNone]
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        let hostingView = NSHostingView(rootView: GeometryReader { geometry in
            content.frame(width: geometry.size.width, height: geometry.size.height)
        })
        // Window geometry owns the viewport; diff content must not expand the window.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: min(960, size.width), height: min(560, size.height))
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: visibleFrame.midX - window.frame.width / 2,
                                      y: visibleFrame.midY - window.frame.height / 2))
        self.window = window
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let callback = onClose
        onClose = nil
        window = nil
        callback?()
    }
}
