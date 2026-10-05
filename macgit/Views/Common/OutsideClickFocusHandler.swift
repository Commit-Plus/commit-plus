// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// Observes clicks in the same window without consuming the clicked control's event.
struct OutsideClickFocusHandler: NSViewRepresentable {
    let isFocused: Bool
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isFocused = isFocused
        context.coordinator.onOutsideClick = onOutsideClick
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var isFocused = false
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?

        init() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.isFocused, let view = self.view, let window = view.window,
                          event.window === window else { return event }
                    let point = view.convert(event.locationInWindow, from: nil)
                    if !view.bounds.contains(point) {
                        self.onOutsideClick?()
                    }
                    return event
                }
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
