// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitLFSRemoveRuleSheet: View {
    let rule: GitLFSTrackingRule
    let onCancel: () -> Void
    let onRemove: @MainActor () async throws -> Void
    @State private var isRemoving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remove Tracking Rule").font(.title2)
            Text(rule.pattern).font(.headline).textSelection(.enabled)
            Text("Remove this rule from .gitattributes. Existing committed pointers and history will not be converted. Review and stage the change in File Status.")
                .foregroundStyle(.secondary)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .disabled(isRemoving)
                Spacer()
                if isRemoving { ProgressView().controlSize(.small) }
                Button(role: .destructive) {
                    guard !isRemoving else { return }
                    isRemoving = true
                    errorMessage = nil
                    Task {
                        defer { isRemoving = false }
                        do { try await onRemove() }
                        catch { errorMessage = error.localizedDescription }
                    }
                } label: {
                    Text("Remove Rule").foregroundStyle(.red)
                }
                .disabled(isRemoving)
            }
        }
        .padding(24)
        .frame(width: 540)
        .interactiveDismissDisabled(isRemoving)
    }
}
