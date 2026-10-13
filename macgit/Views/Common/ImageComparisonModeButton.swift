// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ImageComparisonModeButton: View {
    @Binding var mode: ImageComparisonMode

    private var nextMode: ImageComparisonMode {
        mode == .overlay ? .sideBySide : .overlay
    }

    var body: some View {
        Button {
            mode = nextMode
        } label: {
            Image(systemName: mode.icon)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Switch to \(nextMode.title)")
        .accessibilityLabel("Switch image comparison to \(nextMode.title)")
        .accessibilityValue(mode.title)
    }
}
