// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct RepositoryBookmarkRepairSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bookmarkController: RepositoryBookmarkController
    @StateObject private var model: RepositoryBookmarkRepairModel
    let initialRepositoryURL: URL?
    let onSaved: (URL) -> Void

    init(bookmark: RepositoryBookmark, initialRepositoryURL: URL?, onSaved: @escaping (URL) -> Void) {
        _model = StateObject(wrappedValue: RepositoryBookmarkRepairModel(bookmark: bookmark))
        self.initialRepositoryURL = initialRepositoryURL
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Update Bookmark")
                .font(.title2.bold())
            Text("If the repository was renamed or moved, choose its local folder and the remote URL to save. Review the change before updating.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Current bookmark").font(.headline)
                Text(model.bookmark.remoteURL.absoluteString)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local folder").font(.headline)
                    Text(model.repositoryURL?.path ?? "No folder selected")
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(model.repositoryURL?.path ?? "Choose the repository folder on this Mac")
                }
                Spacer()
                Button("Choose Folder…", action: chooseFolder)
                    .disabled(model.isSaving)
            }

            if model.isLoading {
                ProgressView("Reading remotes…")
                    .controlSize(.small)
            } else if !model.remotes.isEmpty {
                Picker("Remote", selection: $model.selectedRemoteID) {
                    ForEach(model.remotes) { remote in
                        Text("\(remote.name) — \(remote.identity.host)/\(remote.identity.ownerPath)/\(remote.identity.repositoryName)")
                            .tag(Optional(remote.id))
                    }
                }
                .disabled(model.isSaving)
            }

            if let remote = model.selectedRemote {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New bookmark URL").font(.headline)
                    Text(remote.identity.canonicalRemoteURL.absoluteString)
                        .textSelection(.enabled)
                }
                Text("This replaces the saved bookmark URL and links this folder. The change will sync to your other devices when you're signed in and online. An existing bookmark for the new URL will be merged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isSaving)
                Button("Update Bookmark", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
        .padding(24)
        .frame(width: 560)
        .interactiveDismissDisabled(model.isSaving)
        .task {
            if let initialRepositoryURL { await model.selectRepository(initialRepositoryURL) }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the repository whose remote URL should replace this bookmark."
        panel.prompt = "Choose Repository"
        panel.directoryURL = model.repositoryURL
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.selectRepository(url) }
        }
    }

    private func save() {
        Task {
            if await model.save(using: bookmarkController), let url = model.repositoryURL {
                onSaved(url)
                dismiss()
            }
        }
    }
}
