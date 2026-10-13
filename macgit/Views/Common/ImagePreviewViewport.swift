// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Fits the preview to its viewport, scrolling only below the minimum usable height.
struct ImagePreviewViewport<Content: View>: View {
    private let minimumHeight: CGFloat = 240
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let height = max(minimumHeight, geometry.size.height)
            ScrollView(.vertical) {
                content()
                    .frame(width: max(0, geometry.size.width), height: height)
            }
            .scrollDisabled(geometry.size.height >= minimumHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
