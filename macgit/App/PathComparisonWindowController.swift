// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

@MainActor
final class PathComparisonWindowController: NSWindowController, NSWindowDelegate {
    private var comparison: ReferenceComparisonController?

    init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(path: ComparisonPath, in repositoryURL: URL) {
        close()
        let comparison = ReferenceComparisonController(
            repositoryURL: repositoryURL, baseRef: "HEAD", targetRef: "",
            isBranchComparison: false, title: "Compare with Revision", path: path,
            pathTarget: .workingTree)
        self.comparison = comparison
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: min(1100, visibleFrame.width - 40),
                          height: min(760, visibleFrame.height - 80))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Compare — \(path.path) — \(repositoryURL.lastPathComponent)"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: min(760, size.width), height: min(420, size.height))
        window.delegate = self
        let hostingView = NSHostingView(rootView: GeometryReader { geometry in
            ReferenceDiffView(controller: comparison, onClose: { [weak self] in self?.close() })
                .frame(width: geometry.size.width, height: geometry.size.height)
        })
        // Window geometry owns the viewport; diff content must never expand the window.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: visibleFrame.midX - window.frame.width / 2,
                                      y: visibleFrame.midY - window.frame.height / 2))
        self.window = window
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        comparison?.cancel()
        comparison = nil
    }
}
