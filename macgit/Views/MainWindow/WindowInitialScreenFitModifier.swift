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
import SwiftUI

struct WindowInitialScreenFitModifier: NSViewRepresentable {
    static let defaultContentSize = NSSize(width: 1180, height: 780)
    let isEnabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        scheduleInitialSize(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        scheduleInitialSize(for: nsView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled)
    }

    private func scheduleInitialSize(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.applyInitialSizeIfNeeded(window: view.window)
        }
    }

    final class Coordinator {
        var isEnabled: Bool
        private var didApplyInitialSize = false

        init(isEnabled: Bool) {
            self.isEnabled = isEnabled
        }

        func applyInitialSizeIfNeeded(window: NSWindow?) {
            guard !didApplyInitialSize,
                  let window,
                  let screen = window.screen ?? NSScreen.main else {
                return
            }

            didApplyInitialSize = true
            if isEnabled {
                window.setFrame(screen.visibleFrame, display: true)
                return
            }

            let availableContentSize = window.contentRect(forFrameRect: screen.visibleFrame).size
            let contentSize = NSSize(
                width: min(WindowInitialScreenFitModifier.defaultContentSize.width, availableContentSize.width),
                height: min(WindowInitialScreenFitModifier.defaultContentSize.height, availableContentSize.height)
            )
            window.setContentSize(contentSize)
            window.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - window.frame.width / 2,
                y: screen.visibleFrame.midY - window.frame.height / 2
            ))
        }
    }
}
