// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryChooserView: View {
    let onOpen: (URL) -> Void
    @State private var selection: URL?

    var body: some View {
        PersistentHSplit(autosaveName: "RepositoryChooserDetailSplit", left: {
            RepoPickerView(isDashboardSidebar: true,
                           onRepositoryViewed: { selection = $0 },
                           selectedRepositoryURL: selection,
                           onRepositoriesChanged: updateSelection,
                           onRepositoryOpened: onOpen)
                .frame(minWidth: 340, idealWidth: 420, maxWidth: 600)
        }, right: {
            Group {
                if let selection {
                    RepositoryDetailView(repositoryURL: selection, onClose: nil, onOpen: onOpen)
                        .id(selection)
                } else {
                    ContentUnavailableView("No Repository Selected", systemImage: "externaldrive",
                                           description: Text("Open a repository or add a folder to get started. Repositories matching your filters appear on the left."))
                }
            }.frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        })
        .frame(minWidth: 900, minHeight: 620)
    }

    private func updateSelection(_ repositories: [URL]) {
        guard selection.map({ repositories.contains($0) }) != true else { return }
        selection = repositories.first
    }
}
