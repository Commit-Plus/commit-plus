// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryDetailHeader: View {
    let repositoryURL: URL
    let onClose: () -> Void
    let onRefresh: () -> Void
    let onOpen: () -> Void
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        HStack(spacing: 12) {
            Button("Back", systemImage: "chevron.left", action: onClose)
                .labelStyle(.iconOnly).help("Back to overview")
            VStack(alignment: .leading, spacing: 4) {
                Text(repositoryURL.lastPathComponent).font(.title2.bold().scaled(by: textScale)).lineLimit(1)
                Button(action: revealInFinder) {
                    Label(repositoryURL.path, systemImage: "folder")
                        .font(.callout.scaled(by: textScale)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }.buttonStyle(.plain).help("Show in Finder: \(repositoryURL.path)")
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .labelStyle(.iconOnly).help("Refresh repository details")
            Button("Open", action: onOpen).buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
        .padding(20)
    }

    private func revealInFinder() { NSWorkspace.shared.activateFileViewerSelecting([repositoryURL]) }
}
