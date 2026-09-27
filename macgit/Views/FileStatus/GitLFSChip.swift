// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitLFSChip: View {
    var body: some View {
        Text("LFS")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.secondary.opacity(0.6), lineWidth: 1)
            }
            .fixedSize()
            .accessibilityLabel("Tracked by Git LFS")
            .help("Tracked by Git Large File Storage")
    }
}
