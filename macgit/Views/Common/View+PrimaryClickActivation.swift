// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

private struct PrimaryClickActivationModifier: ViewModifier {
    let onMouseDown: () -> Bool
    let onMouseUp: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            PrimaryClickActivationView(onMouseDown: onMouseDown, onMouseUp: onMouseUp)
        }
    }
}

private struct PrimaryClickActivationView: NSViewRepresentable {
    let onMouseDown: () -> Bool
    let onMouseUp: () -> Void

    func makeNSView(context: Context) -> PrimaryClickActivationNSView {
        PrimaryClickActivationNSView(onMouseDown: onMouseDown, onMouseUp: onMouseUp)
    }

    func updateNSView(_ nsView: PrimaryClickActivationNSView, context: Context) {
        nsView.onMouseDown = onMouseDown
        nsView.onMouseUp = onMouseUp
    }
}

private final class PrimaryClickActivationNSView: NSView {
    var onMouseDown: () -> Bool
    var onMouseUp: () -> Void
    private var activatedOnMouseDown = false

    init(onMouseDown: @escaping () -> Bool, onMouseUp: @escaping () -> Void) {
        self.onMouseDown = onMouseDown
        self.onMouseUp = onMouseUp
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        activatedOnMouseDown = onMouseDown()
    }

    override func mouseUp(with event: NSEvent) {
        defer { activatedOnMouseDown = false }
        guard !activatedOnMouseDown, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onMouseUp()
    }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        nextResponder?.rightMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

extension View {
    func primaryClickActivation(
        onMouseDown: @escaping () -> Bool,
        onMouseUp: @escaping () -> Void
    ) -> some View {
        modifier(PrimaryClickActivationModifier(onMouseDown: onMouseDown, onMouseUp: onMouseUp))
    }
}
