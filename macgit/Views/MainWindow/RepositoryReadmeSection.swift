// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryReadmeSection: View {
    let repositoryURL: URL
    let content: String?
    let file: URL?
    let isLoading: Bool
    let onOpenFile: (URL) -> Void
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(file?.lastPathComponent ?? "README", systemImage: "doc.text").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let file {
                    Button("Open File", systemImage: "arrow.up.right") { onOpenFile(file) }.buttonStyle(.link)
                }
            }.padding(.horizontal, 20).padding(.vertical, 12)
            if let content {
                RepositoryReadmeWebView(content: content, directory: file?.deletingLastPathComponent() ?? repositoryURL, contentHeight: $contentHeight)
                    .frame(height: contentHeight)
            } else if isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ContentUnavailableView("No README", systemImage: "doc.text", description: Text("This repository has no README file."))
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }.frame(maxWidth: .infinity)
    }
}
