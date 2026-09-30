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
    let shouldFitVisibleScreen: Bool?
    let initialWindowFrame: CGRect?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        scheduleInitialSize(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shouldFitVisibleScreen = shouldFitVisibleScreen
        context.coordinator.initialWindowFrame = initialWindowFrame
        scheduleInitialSize(for: nsView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            shouldFitVisibleScreen: shouldFitVisibleScreen,
            initialWindowFrame: initialWindowFrame
        )
    }

    private func scheduleInitialSize(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.applyInitialSizeIfNeeded(window: view.window)
        }
    }

    final class Coordinator {
        var shouldFitVisibleScreen: Bool?
        var initialWindowFrame: CGRect?
        private var didApplyInitialSize = false

        init(shouldFitVisibleScreen: Bool?, initialWindowFrame: CGRect?) {
            self.shouldFitVisibleScreen = shouldFitVisibleScreen
            self.initialWindowFrame = initialWindowFrame
        }

        func applyInitialSizeIfNeeded(window: NSWindow?) {
            guard !didApplyInitialSize,
                  let window,
                  let screen = window.screen ?? NSScreen.main else {
                return
            }

            didApplyInitialSize = true
            guard let shouldFitVisibleScreen else { return }

            if shouldFitVisibleScreen {
                window.setFrame(screen.visibleFrame, display: true)
                return
            }

            if let initialWindowFrame {
                window.setFrame(initialWindowFrame, display: true)
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
