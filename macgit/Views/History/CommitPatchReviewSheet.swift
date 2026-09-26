// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct CommitPatchReviewSheet: View {
    let prepared: PreparedCommitPatch
    let isBusy: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onApply: () -> Void
    let onOpenConflict: (CommitPatchReviewFile) -> Void

    private struct FilePreview: Identifiable {
        let review: CommitPatchReviewFile
        var file: CommitFileChange { review.file }
        let hunks: [DiffHunk]
        let metadata: String
        var id: UUID { file.id }
    }

    private let previews: [FilePreview]
    @State private var selectedPreviewID: UUID?

    init(prepared: PreparedCommitPatch, isBusy: Bool, errorMessage: String?,
         onCancel: @escaping () -> Void, onApply: @escaping () -> Void,
         onOpenConflict: @escaping (CommitPatchReviewFile) -> Void) {
        self.prepared = prepared
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.onCancel = onCancel
        self.onApply = onApply
        self.onOpenConflict = onOpenConflict
        self.previews = prepared.reviewFiles.map { review in
            FilePreview(review: review, hunks: DiffParser.parse(review.patch), metadata: review.patch.components(separatedBy: "\n")
                .prefix { !$0.hasPrefix("@@ ") }
                .filter { $0.hasPrefix("old mode ") || $0.hasPrefix("new mode ") || $0.hasPrefix("new file mode ") || $0.hasPrefix("deleted file mode ") }
                .joined(separator: "\n"))
        }
        self._selectedPreviewID = State(initialValue: prepared.reviewFiles.first(where: { $0.state == .conflict })?.id
            ?? prepared.reviewFiles.first?.id)

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
                        Text("\(preview.file.path) — \(preview.review.displayState)").tag(Optional(preview.id))
                    }
                }
            }
            if prepared.hasConflicts {
                Text("Some selected changes need attention. Resolve overlapping edits, or review files that are missing or cannot be changed safely. Nothing has been changed yet.")
                    .font(.callout).foregroundStyle(.orange)
            } else if !prepared.hasChanges {
                Text(prepared.reviewFiles.allSatisfy { $0.state == .alreadyApplied }
                    ? "These changes are already present in your working copy. Nothing needs to be applied."
                    : "Nothing remains to apply. Your working copy is unchanged.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let preview = selectedPreview {
                HStack {
                    Text(preview.review.displayState)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(preview.review.state == .conflict ? .orange : .secondary)
                    Spacer()
                    if preview.review.state == .conflict {
                        Button(preview.review.conflict?.markedResult == nil ? "Why can’t I apply this?" : "Resolve…") {
                            onOpenConflict(preview.review)
                        }
                    }
                }

                if let oldPath = preview.file.oldPath {
                    Text(prepared.request.direction == .apply ? "\(oldPath) → \(preview.file.path)" : "\(preview.file.path) → \(oldPath)")
                    if preview.review.appliesChanges || preview.review.state == .conflict {
                        Text("The rename is included with the selected content changes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if previews.count == 1 {
                    Text(preview.file.path)
                }
                if !preview.metadata.isEmpty {
                    Text(preview.metadata)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if preview.review.state == .alreadyApplied || preview.review.state == .skipped {
                    Text("Preview of the selected changes. This file will not be changed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Group {
                    if preview.review.state == .resolved && preview.review.patch.isEmpty {
                        EmptyStateView(message: "No changes needed", detail: "This file will not be changed.")
                    } else if preview.hunks.isEmpty {
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
                Button(prepared.hasChanges || prepared.hasConflicts ? prepared.request.direction.rawValue : "Done", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(prepared.hasConflicts)
            }
            .disabled(isBusy)
        }
        .padding(24)
        .frame(width: 720, height: 560)
        .interactiveDismissDisabled(isBusy)
    }
}
