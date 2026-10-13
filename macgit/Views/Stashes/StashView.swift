//
//  StashView.swift
//  macgit
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import SwiftUI

struct StashView: View {
    let repositoryURL: URL
    let stashRef: String

    @State private var fileChanges: [CommitFileChange] = []
    @State private var stashEntry: StashEntry?
    @State private var selectedFile: CommitFileChange? = nil
    @State private var diffHunks: [DiffHunk] = []
    @State private var isDiffLoading = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        VStack(spacing: 0) {
            stashHeader

            Group {
                if isLoading && fileChanges.isEmpty {
                    ProgressView("Loading stash…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if fileChanges.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        message: "No files in stash",
                        detail: "This stash does not contain any file changes"
                    )
                } else {
                    PersistentHSplit(
                        autosaveName: "StashDetailSplit",
                        left: {
                            CommitFileListView(
                                changes: fileChanges,
                                selectedFile: $selectedFile,
                                allowsEmptySelection: false
                            )
                                .frame(minWidth: 220)
                        },
                        right: {
                            stashDiffPanel
                                .frame(minWidth: 300)
                        }
                    )
                }
            }
        }
        .id(stashRef)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: stashRef) {
            await loadStash(for: stashRef)
        }
        .task(id: selectedFile?.id) {
            guard let selectedFile else {
                diffHunks = []
                isDiffLoading = false
                return
            }
            await loadDiff(for: selectedFile, stashRef: stashRef)
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                Task {
                    await loadStash(for: stashRef)
                }
            }
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
    }

    private var stashHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(stashTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(stashMetadata)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(fileChanges.count) file\(fileChanges.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private var stashTitle: String {
        guard let stashEntry else { return "Stash" }
        return stashEntry.description.isEmpty ? stashEntry.displayTitle : stashEntry.description
    }

    private var stashMetadata: String {
        var components = [stashRef]
        if let branchName = stashEntry?.branchName, !branchName.isEmpty {
            components.append("On \(branchName)")
        }
        if let createdAt = stashEntry?.createdAt {
            components.append(createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        return components.joined(separator: " · ")
    }

    private var stashDiffPanel: some View {
        Group {
            if let file = selectedFile {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.primary)
                            .font(.system(size: 14, weight: .medium))
                        Text(file.path)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.separator)
                            .frame(height: 0.5)
                    }

                    if isDiffLoading {
                        ProgressView("Loading diff…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        DiffView(
                            hunks: diffHunks,
                            file: nil,
                            repositoryURL: repositoryURL,
                            undoManager: nil,
                            onRefresh: {},
                            onError: { _ in },
                            filePath: file.path,
                            gitRef: stashRef
                        )
                    }
                }
            } else {
                EmptyStateView(
                    icon: "doc.text",
                    message: "Select a file",
                    detail: "Click a file on the left to see its diff"
                )
            }
        }
    }

    private func loadStash(for ref: String) async {
        isLoading = true
        defer { isLoading = false }

        await MainActor.run {
            fileChanges = []
            selectedFile = nil
            diffHunks = []
        }

        async let changesRequest = GitStatusService.shared.changedFiles(in: ref, in: repositoryURL)
        async let stashesRequest = GitStatusService.shared.stashes(in: repositoryURL)
        let (changes, stashes) = await (changesRequest, stashesRequest)
        await MainActor.run {
            fileChanges = changes
            stashEntry = stashes.first { $0.ref == ref }
            selectedFile = changes.first
        }
    }

    private func loadDiff(for file: CommitFileChange, stashRef: String) async {
        diffHunks = []
        isDiffLoading = true
        let hunks = await GitStatusService.shared.diff(for: file.path, in: stashRef, in: repositoryURL)
        guard !Task.isCancelled, selectedFile?.id == file.id, self.stashRef == stashRef else { return }
        diffHunks = hunks
        isDiffLoading = false
    }
}

#Preview {
    StashView(repositoryURL: URL(fileURLWithPath: "/tmp"), stashRef: "stash@{0}")
}
