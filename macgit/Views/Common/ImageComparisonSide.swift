// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ImageComparisonSide: View {
    let title: String
    let image: NSImage?
    let error: String?
    let isMissing: Bool
    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.caption.weight(.semibold)).padding(10)
            Divider()
            if let image {
                GeometryReader { geometry in
                    ScrollView {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: max(0, geometry.size.width - 24)).padding(12)
                    }
                }
            } else {
                EmptyStateView(icon: "photo", message: isMissing ? "No image" : "Unable to preview image", detail: error)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
