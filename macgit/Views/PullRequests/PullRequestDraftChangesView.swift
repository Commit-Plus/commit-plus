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

struct PullRequestDraftChangesView: View {
    let repositoryURL: URL
    let remoteName: String?
    let sourceBranch: String
    let targetBranch: String?

    @State private var changes: [CommitFileChange] = []
    @State private var selectedFile: CommitFileChange?
    @State private var diffHunks: [DiffHunk] = []
    @State private var isLoading = false
    @State private var isLoadingDiff = false
    @State private var errorMessage: String?
    @State private var diffErrorMessage: String?
    @State private var changesLoadID = UUID()
    @State private var diffLoadID = UUID()
    @AppStorage("createPullRequest.fileListWidth") private var fileListWidth: Double = 250

    var body: some View {
        Group {
            if targetBranch == nil {
                ContentUnavailableView(
                    "Select a Target Branch",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Choose a target branch to compare changes.")
                )
            } else if sourceBranch == targetBranch {
                ContentUnavailableView(
                    "Choose Different Branches",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Source and target branches must be different.")
                )
            } else if isLoading {
                ProgressView("Loading changes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn’t Load Changes",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if changes.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("The source branch has no changes relative to the target branch.")
                )
            } else {
                comparisonContent
            }
        }
        .task(id: comparisonID) {
            await loadChanges()
        }
        .onChange(of: selectedFile) { _, file in
            loadDiff(for: file)
        }
    }

    private var comparisonID: String {
        "\(remoteName ?? "")|\(targetBranch ?? "")...\(sourceBranch)"
    }

    private var comparisonContent: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 6)
            HStack(spacing: 0) {
                CommitFileListView(
                    changes: changes,
                    selectedFile: $selectedFile,
                    showsLayoutControls: true
                )
                .frame(width: CGFloat(fileListWidth))

                ColumnResizer(
                    leftWidth: Binding(
                        get: { CGFloat(fileListWidth) },
                        set: { fileListWidth = Double($0) }
                    ),
                    rightWidth: Binding(
                        get: { max(40, availableWidth - CGFloat(fileListWidth)) },
                        set: { fileListWidth = Double(availableWidth - $0) }
                    ),
                    minimumLeftWidth: 220
                )

                selectedFileDiff
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var selectedFileDiff: some View {
        if isLoadingDiff {
            ProgressView("Loading file diff…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let diffErrorMessage {
            ContentUnavailableView(
                "Diff Unavailable",
                systemImage: "doc.questionmark",
                description: Text(diffErrorMessage)
            )
        } else if let selectedFile {
            if diffHunks.isEmpty {
                ContentUnavailableView(
                    "No Text Diff",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No renderable text changes were found for \(selectedFile.path).")
                )
            } else {
                DiffView(
                    hunks: diffHunks,
                    repositoryURL: repositoryURL,
                    filePath: selectedFile.path
                )
            }
        } else {
            ContentUnavailableView(
                "Select a File",
                systemImage: "doc.text",
                description: Text("Choose a changed file to inspect its diff.")
            )
        }
    }

    @MainActor
    private func loadChanges() async {
        let loadID = UUID()
        changesLoadID = loadID
        changes = []
        selectedFile = nil
        diffHunks = []
        errorMessage = nil
        diffErrorMessage = nil
        guard let targetBranch, sourceBranch != targetBranch else {
            isLoading = false
            return
        }

        isLoading = true
        do {
            let loadedChanges = try await GitStatusService.shared.pullRequestChangedFiles(
                sourceBranch: sourceBranch,
                targetBranch: targetBranch,
                remoteName: remoteName,
                in: repositoryURL
            )
            guard changesLoadID == loadID, !Task.isCancelled else { return }
            changes = loadedChanges
            selectedFile = loadedChanges.first
            isLoading = false
        } catch is CancellationError {
            guard changesLoadID == loadID else { return }
            isLoading = false
        } catch {
            guard changesLoadID == loadID else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadDiff(for file: CommitFileChange?) {
        let loadID = UUID()
        diffLoadID = loadID
        diffHunks = []
        diffErrorMessage = nil
        guard let file else {
            isLoadingDiff = false
            return
        }

        isLoadingDiff = true
        Task {
            do {
                guard let targetBranch else {
                    isLoadingDiff = false
                    return
                }
                let hunks = try await GitStatusService.shared.pullRequestDiff(
                    for: file.path,
                    sourceBranch: sourceBranch,
                    targetBranch: targetBranch,
                    remoteName: remoteName,
                    in: repositoryURL
                )
                guard diffLoadID == loadID, !Task.isCancelled else { return }
                diffHunks = hunks
                isLoadingDiff = false
            } catch is CancellationError {
                guard diffLoadID == loadID else { return }
                isLoadingDiff = false
            } catch {
                guard diffLoadID == loadID else { return }
                diffErrorMessage = error.localizedDescription
                isLoadingDiff = false
            }
        }
    }
}
