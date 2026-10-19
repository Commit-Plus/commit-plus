// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct PullRequestMarkdownContent: View {
    let content: String
    let baseURL: URL
    let textScale: CGFloat
    @State private var contentHeight: CGFloat = 100

    var body: some View {
        RepositoryReadmeWebView(
            content: content,
            baseURL: baseURL,
            textScale: Double(textScale),
            compact: true,
            isUntrustedContent: true,
            contentHeight: $contentHeight
        )
        .frame(height: contentHeight)
        .frame(maxWidth: .infinity)
    }
}
