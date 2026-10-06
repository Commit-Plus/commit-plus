// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

@MainActor
final class RepositorySettingsWindowController: NSWindowController, NSWindowDelegate {
    private var onClose: (() -> Void)?

    init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show<Content: View>(content: Content, onClose: @escaping () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = "Repository Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 600, height: 480)
        window.collectionBehavior = [.fullScreenNone]
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.delegate = self
        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 640, height: 540))
        window.center()
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
