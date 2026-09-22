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

struct RepositoryAIMutationConfirmationSheet: View {
    let pending: PendingRepositoryAIMutation
    let isExecuting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(pending.preview.title, systemImage: "sparkles")
                .font(.title2)
                .bold()

            Text(pending.preview.summary)

            if let warning = pending.preview.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Warning: \(warning)")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(pending.preview.items) { item in
                        RepositoryAIMutationPreviewRow(item: item)
                    }
                }
            }
            .frame(maxHeight: 220)

            if !pending.preview.details.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pending.preview.details) { item in
                        LabeledContent(item.title) {
                            Text(item.detail)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .pointingHandCursor()
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(pending.preview.confirmationLabel, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .pointingHandCursor()
                    .disabled(isExecuting)
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 300)
        // Keep every dismissal app-owned so Escape follows the Cancel button
        // path and the transcript records an explicit cancellation result.
        .interactiveDismissDisabled()
    }
}
