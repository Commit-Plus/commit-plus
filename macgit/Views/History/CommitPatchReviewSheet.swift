// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct CommitPatchReviewSheet: View {
    let prepared: PreparedCommitPatch
    let isBusy: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onApply: () -> Void

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
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(prepared.request.files) { file in
                        if let oldPath = file.oldPath {
                            Text(prepared.request.direction == .apply ? "\(oldPath) → \(file.path)" : "\(file.path) → \(oldPath)")
                            Text("The rename is included with the selected content changes.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else { Text(file.path) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 100)
            ScrollView([.horizontal, .vertical]) {
                Text(prepared.patch)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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
