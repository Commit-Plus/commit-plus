// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct FileImagePreview: View {
    let image: NSImage

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .fixedSize()
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
