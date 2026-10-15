// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Hover feedback stays local so scrolling under the pointer does not invalidate the picker.
struct RepoPickerHoverRow<Content: View>: View {
    @State private var isHovered = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(
                Color.primary.opacity(isHovered ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .onHover { hovered in
                if isHovered != hovered { isHovered = hovered }
            }
    }
}
