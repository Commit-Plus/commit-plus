// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// Measures the presenting repository window, before a sheet is attached.
struct HistoryRebaseWindowSizeReader: NSViewRepresentable {
    let onHeightChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ReaderView {
        ReaderView(onHeightChange: onHeightChange)
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onHeightChange = onHeightChange
    }

    static func dismantleNSView(_ nsView: ReaderView, coordinator: Void) {
        NotificationCenter.default.removeObserver(nsView)
    }

    final class ReaderView: NSView {
        var onHeightChange: (CGFloat) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(reportHeight),
                name: NSWindow.didResizeNotification, object: window)
            // Publish after SwiftUI finishes attaching the measuring view.
            DispatchQueue.main.async { [weak self] in self?.reportHeight() }
        }

        @objc private func reportHeight() {
            guard let window else { return }
            onHeightChange(window.frame.height)
        }
    }
}
