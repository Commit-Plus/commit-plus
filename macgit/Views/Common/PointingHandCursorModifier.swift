// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct PointingHandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovering = true
                    (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
                case .ended:
                    isHovering = false
                    NSCursor.arrow.set()
                }
            }
            .onChange(of: isEnabled) {
                if isHovering {
                    (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
                }
            }
            .onDisappear {
                if isHovering { NSCursor.arrow.set() }
            }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}
