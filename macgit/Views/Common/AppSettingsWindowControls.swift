// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct AppSettingsWindowControls: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowControlsView {
        WindowControlsView()
    }

    func updateNSView(_ view: WindowControlsView, context: Context) {
        view.configureWindow()
    }

    final class WindowControlsView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            guard let window else { return }
            window.styleMask.remove(.miniaturizable)
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.tabbingMode = .disallowed
        }
    }
}
