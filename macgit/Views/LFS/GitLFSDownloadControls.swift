// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitLFSDownloadControls: View {
    @Bindable var runtime: GitLFSRuntimeController
    var onInstalled: () -> Void = {}

    var body: some View {
        if runtime.isInstalling {
            HStack {
                ProgressView().controlSize(.small)
                Text("Downloading and verifying Git LFS…")
                Button("Cancel", role: .cancel) { runtime.cancel() }
            }
        } else {
            Button("Download & Use Embedded · \(runtime.downloadDescription)", systemImage: "arrow.down.circle") {
                Task {
                    if await runtime.install() { onInstalled() }
                }
            }
        }
    }
}
