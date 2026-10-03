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

struct PullRequestChangesView: View {
    @Environment(\.appTextScale) private var textScale
    let files: [PullRequestChangedFile]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void

    @State private var selectedFileID: String?
    @State private var diffHunks: [DiffHunk] = []

    var body: some View {
        Group {
            if isLoading && files.isEmpty {
                ProgressView("Loading changes…")
                    .font(.body.scaled(by: textScale))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, files.isEmpty {
                unavailableState(
                    title: "Couldn’t Load Changes",
                    icon: "exclamationmark.triangle",
                    message: errorMessage,
                    showsRefresh: true
                )
            } else if files.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("This pull request has no changed files to display.")
                )
            } else {
                HStack(spacing: 0) {
                    fileList
                        .frame(width: 250)

                    Divider()

                    selectedFileDetail
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isLoading && !files.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            }
        }
        .task(id: files) {
            let updatedFiles = files
            if let selectedFileID,
               updatedFiles.contains(where: { $0.id == selectedFileID }) {
                return
            }
            selectedFileID = updatedFiles.first?.id
        }
        .task(id: selectedFile?.patch) {
            diffHunks = selectedFile?.diffHunks ?? []
        }
    }

    private var selectedFile: PullRequestChangedFile? {
        guard let selectedFileID else { return nil }
        return files.first { $0.id == selectedFileID }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                    .font(.subheadline.scaled(by: textScale))
                    .bold()
                Spacer()
                Button("Refresh changes", systemImage: "arrow.clockwise", action: onRefresh)
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .disabled(isLoading)
                    .help("Refresh changes")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List(selection: $selectedFileID) {
                ForEach(files) { file in
                    HStack(spacing: 8) {
                        Text(statusSymbol(for: file.status))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(statusColor(for: file.status))
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                .font(.system(size: 12, weight: .medium).scaled(by: textScale))
                                .lineLimit(1)
                            Text(directory(for: file.path))
                                .font(.system(size: 10).scaled(by: textScale))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        if let additions = file.additions,
                           let deletions = file.deletions {
                            Text("+\(additions) −\(deletions)")
                                .font(.system(size: 10, design: .monospaced).scaled(by: textScale))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(file.id)
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var selectedFileDetail: some View {
        if let selectedFile {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(selectedFile.path)
                        .font(.subheadline.monospaced().scaled(by: textScale))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(selectedFile.status.displayText)
                        .font(.caption.scaled(by: textScale))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                if let reason = selectedFile.patchUnavailableReason {
                    unavailableState(
                        title: "Diff Unavailable",
                        icon: "doc.questionmark",
                        message: reason,
                        showsRefresh: false
                    )
                } else if diffHunks.isEmpty {
                    unavailableState(
                        title: "No Text Diff",
                        icon: "doc.text.magnifyingglass",
                        message: "The provider returned no renderable diff hunks for this file.",
                        showsRefresh: false
                    )
                } else {
                    DiffView(hunks: diffHunks, filePath: selectedFile.path)
                }
            }
        } else {
            ContentUnavailableView(
                "Select a File",
                systemImage: "doc.text",
                description: Text("Choose a changed file to inspect its diff.")
            )
        }
    }

    private func unavailableState(
        title: String,
        icon: String,
        message: String,
        showsRefresh: Bool
    ) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView(title, systemImage: icon, description: Text(message))
            HStack(spacing: 8) {
                if showsRefresh {
                    Button("Try Again", systemImage: "arrow.clockwise", action: onRefresh)
                        .font(.body.scaled(by: textScale))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func directory(for path: String) -> String {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return directory == "/" ? "" : directory
    }

    private func statusSymbol(for status: CommitFileStatus) -> String {
        switch status {
        case .added: "+"
        case .modified: "•"
        case .deleted: "−"
        case .renamed: "→"
        case .copied: "C"
        }
    }

    private func statusColor(for status: CommitFileStatus) -> Color {
        switch status {
        case .added: .green
        case .modified: .orange
        case .deleted: .red
        case .renamed: .blue
        case .copied: .purple
        }
    }
}
