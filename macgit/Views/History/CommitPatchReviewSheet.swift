// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct CommitPatchReviewSheet: View {
    let prepared: PreparedCommitPatch
    let isBusy: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onApply: () -> Void

    private struct FilePreview: Identifiable {
        let file: CommitFileChange
        let hunks: [DiffHunk]
        let metadata: String
        var id: UUID { file.id }
    }

    private let previews: [FilePreview]
    @State private var selectedPreviewID: UUID?

    init(prepared: PreparedCommitPatch, isBusy: Bool, errorMessage: String?,
         onCancel: @escaping () -> Void, onApply: @escaping () -> Void) {
        self.prepared = prepared
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.onCancel = onCancel
        self.onApply = onApply
        // Preparation concatenates one complete patch per requested file, in this order.
        // Parse each separately so headers from another file never become hunk content.
        let patches = prepared.patch.components(separatedBy: "\ndiff --git ")
        self.previews = zip(prepared.request.files, patches).map { file, patch in
            FilePreview(file: file, hunks: DiffParser.parse(patch), metadata: patch.components(separatedBy: "\n")
                .prefix { !$0.hasPrefix("@@ ") }
                .filter { $0.hasPrefix("old mode ") || $0.hasPrefix("new mode ") || $0.hasPrefix("new file mode ") || $0.hasPrefix("deleted file mode ") }
                .joined(separator: "\n"))
        }
        self._selectedPreviewID = State(initialValue: prepared.request.files.first?.id)
    }

    private var selectedPreview: FilePreview? {
        previews.first { $0.id == selectedPreviewID } ?? previews.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(prepared.request.direction.rawValue) Selected Changes")
                .font(.title2.bold())
            Text(prepared.repositoryURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Commit \(prepared.request.commit.prefix(12)) → \(prepared.targetBranch)")
                .font(.callout.monospaced())
            Text("\(prepared.request.scope) · Changes will remain unstaged. Nothing will be committed.")
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if previews.count > 1 {
                Picker("File", selection: $selectedPreviewID) {
                    ForEach(previews) { preview in
                        Text(preview.file.path).tag(Optional(preview.id))
                    }
                }
            }
            if let preview = selectedPreview {
                if let oldPath = preview.file.oldPath {
                    Text(prepared.request.direction == .apply ? "\(oldPath) → \(preview.file.path)" : "\(preview.file.path) → \(oldPath)")
                    Text("The rename is included with the selected content changes.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if previews.count == 1 {
                    Text(preview.file.path)
                }
                if !preview.metadata.isEmpty {
                    Text(preview.metadata)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Group {
                    if preview.hunks.isEmpty {
                        EmptyStateView(message: "File metadata changes", detail: "This file has no changed lines.")
                    } else {
                        DiffView(hunks: preview.hunks, filePath: preview.file.path, prefersTextDiff: true)
                            .id(preview.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                if isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(prepared.request.direction.rawValue, action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(isBusy)
        }
        .padding(24)
        .frame(width: 720, height: 560)
        .interactiveDismissDisabled(isBusy)
    }
}
