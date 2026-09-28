// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    @ViewBuilder
    func repositoryToolbarButtonStyle() -> some View {
        if #available(macOS 27, *) {
            buttonStyle(RepositoryToolbarButtonStyle())
        } else {
            self
        }
    }
}

/// Keeps the complete two-line label inside the button's measured bounds.
/// The system toolbar button style can clip custom stacked labels on macOS 27.
private struct RepositoryToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RepositoryToolbarButtonBody(configuration: configuration)
    }
}

private struct RepositoryToolbarButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(.primary.opacity(highlightOpacity))
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { isHovered = $0 }
    }

    private var highlightOpacity: Double {
        guard isEnabled else { return 0 }
        if configuration.isPressed { return 0.16 }
        return isHovered ? 0.08 : 0
    }
}
