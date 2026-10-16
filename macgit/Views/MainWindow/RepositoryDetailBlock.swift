// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryDetailBlock<Content: View, Header: View>: View {
    let content: Content
    let header: Header

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.content = content()
        self.header = header()
    }

    init(@ViewBuilder content: () -> Content) where Header == EmptyView {
        self.content = content()
        self.header = EmptyView()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}
