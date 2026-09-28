// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitLFSPreviewDownloadButton: View {
    let controller: RevisionBrowserController
    let remote: String
    @State private var runtime = GitLFSRuntimeController.shared
    @State private var showDownload = false
    @State private var requestedEntryID: String?

    var body: some View {
        GitLFSAccessView(repositoryURL: controller.repositoryURL) { authorize in
            downloadButton(authorize: authorize)
        }
    }

    @ViewBuilder
    private func downloadButton(authorize: @escaping @MainActor () async -> Bool) -> some View {
        Button("Download for Preview") {
            let selectedID = controller.selectedEntry?.id
            requestedEntryID = selectedID
            Task {
                guard await authorize() else { return }
                await runtime.refresh()
                guard controller.selectedEntry?.id == selectedID else { return }
                if runtime.status?.activeRuntime == nil { showDownload = true }
                else if await authorize(), controller.selectedEntry?.id == selectedID { controller.downloadLFSPreview(remote: remote) }
            }
        }
        .disabled(remote.isEmpty || controller.isLoadingPreview || runtime.isInstalling)
        .alert("Download Git LFS?", isPresented: $showDownload) {
            Button("Download & Continue") {
                let selectedID = requestedEntryID
                Task {
                    let installed = await runtime.install()
                    if installed, await authorize(), controller.selectedEntry?.id == selectedID {
                        controller.downloadLFSPreview(remote: remote)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Install a private copy managed by Commit+ on this Mac.\n\(runtime.downloadDescription)")
        }
        if runtime.isInstalling { ProgressView("Installing Git LFS…").controlSize(.small) }
        if let error = runtime.error { Text(error).foregroundStyle(.red) }
    }
}
