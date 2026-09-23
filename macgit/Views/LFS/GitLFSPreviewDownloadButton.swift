// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitLFSPreviewDownloadButton: View {
    let controller: RevisionBrowserController
    let remote: String
    @State private var runtime = GitLFSRuntimeController.shared
    @State private var showDownload = false

    var body: some View {
        Button("Download for Preview") {
            Task {
                await runtime.refresh()
                if runtime.status?.activeRuntime == nil { showDownload = true }
                else { controller.downloadLFSPreview(remote: remote) }
            }
        }
        .disabled(remote.isEmpty || controller.isLoadingPreview || runtime.isInstalling)
        .alert("Download Git LFS?", isPresented: $showDownload) {
            Button("Download & Continue") {
                let selectedID = controller.selectedEntry?.id
                Task {
                    let installed = await runtime.install()
                    if installed, controller.selectedEntry?.id == selectedID {
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
