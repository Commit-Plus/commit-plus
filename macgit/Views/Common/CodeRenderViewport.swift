// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Fixed row geometry bounds both the SwiftUI view count and long-line rendering.
struct CodeRenderViewport<Content: View>: View {
    let count: Int
    let rowHeight: CGFloat
    let minimumWidth: CGFloat
    @ViewBuilder let content: (Int, CGRect) -> Content
    @State private var viewport = CGRect(x: 0, y: 0, width: 1_024, height: 400)

    var body: some View {
        GeometryReader { geometry in
            let range = CodeRenderWindow.rows(count: count, viewport: viewport, rowHeight: rowHeight)
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: CGFloat(range.lowerBound) * rowHeight)
                    ForEach(range, id: \.self) { index in
                        content(index, viewport)
                            .frame(height: rowHeight)
                    }
                    Color.clear.frame(height: CGFloat(count - range.upperBound) * rowHeight)
                }
                .frame(minWidth: max(geometry.size.width, minimumWidth), alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
            .onScrollGeometryChange(for: CGRect.self) { scroll in
                scroll.visibleRect
            } action: { _, value in
                viewport = value
            }
        }
    }
}
