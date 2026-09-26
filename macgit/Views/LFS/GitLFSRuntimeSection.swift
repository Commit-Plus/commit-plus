// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitLFSRuntimeSection: View {
    @State private var runtime = GitLFSRuntimeController.shared

    var body: some View {
        Section {
            HStack {
                Text("Git LFS Runtime")
                Spacer()
                ForEach(GitRuntimePreference.allCases) { preference in
                    Button(preference == .automatic ? "Automatic" : preference == .system ? "System" : "Embedded") {
                        Task { await runtime.select(preference) }
                    }
                    .tint(runtime.status?.preference == preference ? .accentColor : .secondary)
                    .disabled(runtime.isInstalling || (preference == .embedded && runtime.status?.embeddedRuntime == nil))
                }
            }
            if let active = runtime.status?.activeRuntime {
                LabeledContent("Active Git LFS", value: active.version)
                Text(active.executableURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } else {
                Label("Git LFS is not available", systemImage: "arrow.down.circle")
            }
            if runtime.status?.embeddedRuntime == nil {
                GitLFSDownloadControls(runtime: runtime)
            }
            if let error = runtime.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Button("Refresh Git LFS Information") { Task { await runtime.refresh() } }
                .disabled(runtime.isInstalling)
        } header: {
            Label("Git LFS Installation", systemImage: "externaldrive")
        } footer: {
            Text("Automatic uses System Git LFS when available, otherwise Embedded Git LFS. This choice is independent of Git Runtime and is stored only on this Mac.")
        }
        .task { await runtime.refresh() }
    }
}
