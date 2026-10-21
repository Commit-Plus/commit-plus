// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

/// Weak handle to the Settings window so window-scoped presentation can target it.
final class AppSettingsWindowReference {
    weak var window: NSWindow?
}

struct AppSettingsWindowControls: NSViewRepresentable {
    let windowReference: AppSettingsWindowReference

    func makeNSView(context: Context) -> WindowControlsView {
        let view = WindowControlsView()
        view.windowReference = windowReference
        return view
    }

    func updateNSView(_ view: WindowControlsView, context: Context) {
        view.windowReference = windowReference
        view.configureWindow()
    }

    final class WindowControlsView: NSView {
        var windowReference: AppSettingsWindowReference?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            guard let window else { return }
            windowReference?.window = window
            window.styleMask.remove(.miniaturizable)
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.tabbingMode = .disallowed
        }
    }
}
