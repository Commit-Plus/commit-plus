// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Banner for a paused merge, cherry-pick, revert, or rebase.
struct InProgressOperationBanner: View {
    let operation: GitInProgressOperation
    /// True when no file changes remain, so the operation can only be continued, skipped, or aborted.
    let isEmpty: Bool
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onAbort: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))

            Text(isEmpty ? operation.emptyMessage : operation.message)
                .font(.system(size: 12))

            Spacer()

            HStack(spacing: 8) {
                if isEmpty && operation.canSkip && !operation.isRebase {
                    Button("Skip", action: onSkip)
                        .buttonStyle(.borderedProminent)
                        .pointingHandCursor()
                        .controlSize(.small)

                    Button("Abort", action: onAbort)
                        .buttonStyle(.borderless)
                        .pointingHandCursor()
                        .controlSize(.small)
                } else {
                    if operation.isRebase {
                        Button("Skip", action: onSkip)
                            .buttonStyle(.borderless)
                            .pointingHandCursor()
                            .controlSize(.small)
                    }
                    Button("Abort", action: onAbort)
                        .buttonStyle(.borderless)
                        .pointingHandCursor()
                        .controlSize(.small)

                    Button("Continue", action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .pointingHandCursor()
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
        .overlay(
            Rectangle()
                .fill(Color.orange.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
