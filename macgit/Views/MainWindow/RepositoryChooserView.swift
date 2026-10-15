// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryChooserView: View {
    let onOpen: (URL) -> Void
    @State private var selection: URL?

    var body: some View {
        if let selection {
            PersistentHSplit(autosaveName: "RepositoryChooserDetailSplit", left: {
                RepoPickerView(isDashboardSidebar: true, onRepositoryViewed: { self.selection = $0 }, selectedRepositoryURL: selection, onRepositoryOpened: onOpen)
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: 600)
            }, right: {
                RepositoryDetailView(repositoryURL: selection, onClose: { self.selection = nil }, onOpen: onOpen)
                    .id(selection).frame(minWidth: 500)
            })
        } else {
            RepoPickerView(onRepositoryViewed: { selection = $0 }, onRepositoryOpened: onOpen)
        }
    }
}
