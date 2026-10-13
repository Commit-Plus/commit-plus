// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ImageComparisonOverlay: View {
    let before: NSImage
    let after: NSImage
    @Binding var fraction: Double

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let width = max(before.size.width, after.size.width, 1)
            let height = max(before.size.height, after.size.height, 1)
            let scale = max(0, min(size.width / width, size.height / height))
            let imageWidth = width * scale
            let imageOffset = (size.width - imageWidth) / 2
            let dividerX = imageOffset + imageWidth * fraction
            ZStack {
                Color(nsColor: .textBackgroundColor)
                image(after, scale: scale)
                    .frame(width: width * scale, height: height * scale, alignment: .topLeading)
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    image(before, scale: scale)
                        .frame(width: width * scale, height: height * scale, alignment: .topLeading)
                }
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: dividerX)
                    }
                Rectangle().fill(.primary).frame(width: 2)
                    .position(x: dividerX, y: size.height / 2)
                Image(systemName: "arrow.left.and.right")
                    .font(.caption.bold()).padding(8)
                    .background(.regularMaterial, in: Circle())
                    .position(x: dividerX, y: size.height / 2)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                fraction = min(1, max(0, (value.location.x - imageOffset) / max(imageWidth, 1)))
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before and after image comparison")
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func image(_ image: NSImage, scale: CGFloat) -> some View {
        Image(nsImage: image).resizable()
            .frame(width: image.size.width * scale, height: image.size.height * scale)
    }
}
