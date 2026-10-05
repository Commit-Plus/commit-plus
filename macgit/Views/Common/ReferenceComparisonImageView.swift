// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ReferenceComparisonImageView: View {
    let file: CommitFileChange
    let snapshot: ReferenceComparisonSnapshot
    let mode: ReferenceComparisonMode
    let repositoryURL: URL

    var body: some View {
        HSplitView {
            if file.status != .added, let base = try? snapshot.diffBase(for: mode) {
                ImageSide(title: "Base", path: file.oldPath ?? file.path, ref: base, repositoryURL: repositoryURL)
            }
            if file.status != .deleted {
                ImageSide(title: "Target", path: file.path, ref: snapshot.target, repositoryURL: repositoryURL)
            }
        }
    }

    private struct ImageSide: View {
        let title: String
        let path: String
        let ref: String
        let repositoryURL: URL
        @State private var image: NSImage?
        @State private var error: String?

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(title).font(.caption.weight(.semibold))
                    Spacer()
                    if let image {
                        Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                Divider()
                if let image {
                    FileImagePreview(image: image)
                } else if let error {
                    EmptyStateView(icon: "photo", message: "Unable to preview image", detail: error)
                } else {
                    ProgressView("Loading image…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 140, maxWidth: .infinity, maxHeight: .infinity)
            .task {
                do {
                    let data = try await GitStatusService.shared.showFile(at: path, ref: ref, in: repositoryURL)
                    try Task.checkCancellation()
                    if let decoded = NSImage(data: data) {
                        image = decoded
                    } else {
                        error = "This image format cannot be previewed, or its content is unavailable locally."
                    }
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
            }
        }
    }
}
