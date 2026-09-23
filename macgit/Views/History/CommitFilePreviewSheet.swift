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

struct CommitFilePreviewSheet: View {
    let request: CommitFilePreviewRequest
    let availableSize: CGSize
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [DiffLine] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "eye")
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.file.path)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text("Commit \(request.commitHash.prefix(7)) · Full file with changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            content
        }
        // Bound the entire sheet, including its header, to the presenting view.
        // An ideal height alone allows the sheet to extend beyond the window.
        .frame(
            width: min(1100, max(1, availableSize.width - 48)),
            height: min(640, max(1, availableSize.height - 48))
        )
        .task {
            do {
                let loaded = try await GitStatusService.shared.fullFilePreview(
                    for: request.file,
                    in: request.commitHash,
                    in: request.repositoryURL
                )
                guard !Task.isCancelled else { return }
                lines = loaded
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading full file…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            EmptyStateView(icon: "doc.questionmark", message: "Unable to preview file", detail: errorMessage)
        } else if lines.isEmpty {
            EmptyStateView(icon: "doc.text", message: "Empty file")
        } else {
            CommitFilePreviewContent(
                lines: lines,
                fileExtension: SyntaxHighlighter.syntaxIdentifier(forFilePath: request.file.path)
            )
        }
    }
}
