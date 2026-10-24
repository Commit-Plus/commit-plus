// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Announces the daily fully merged branch check, matching the in-progress operation banner.
struct BranchCleanupBanner: View {
    let branchCount: Int
    let onDelete: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.orange)
                .font(.system(size: 12))

            Text(branchCount == 1
                ? "1 fully merged branch can be deleted."
                : "\(branchCount) fully merged branches can be deleted.")
                .font(.system(size: 12))

            Spacer()

            HStack(spacing: 8) {
                Button("Delete", action: onDelete)
                    .buttonStyle(.borderedProminent)
                    .pointingHandCursor()
                    .controlSize(.small)
                    .help("Review and delete fully merged branches")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .pointingHandCursor()
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
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
