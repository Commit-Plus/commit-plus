// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryUnavailableView: View {
    let repositoryURL: URL
    let onLocate: () -> Void
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Repository Moved or Deleted", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Commit+ can no longer access \"\(repositoryURL.lastPathComponent)\" at \(repositoryURL.path).")
        } actions: {
            HStack {
                Button("Locate Folder…", action: onLocate)
                Button("Try Again", action: onRetry)
                Button("Close Repository", role: .cancel, action: onClose)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
