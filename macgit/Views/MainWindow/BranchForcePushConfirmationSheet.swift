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

struct BranchForcePushConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plan: BranchForcePushPlan
    let onConfirm: @MainActor () async throws -> Void
    @State private var isPushing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Force Push to \(plan.destination)?").font(.headline)
            Text("Replace the published history with local branch '\(plan.localBranch)'. \(plan.removedCommitCount) remote commit(s) will no longer be in this branch's history.")
            LabeledContent("Remote commit", value: String(plan.remoteHash.prefix(12)))
            LabeledContent("Replace with", value: String(plan.localHash.prefix(12)))
            if plan.isDefaultBranch {
                Label("This is a default branch. Other collaborators may depend on its history.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Text("If the remote changes before the push completes, the push will be rejected. Server branch protection still applies.")
                .foregroundStyle(.secondary)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isPushing)
                if isPushing { ProgressView().controlSize(.small) }
                Button("Force Push", role: .destructive) {
                    guard !isPushing else { return }
                    isPushing = true
                    errorMessage = nil
                    Task {
                        defer { isPushing = false }
                        do { try await onConfirm(); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .disabled(isPushing)
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(isPushing)
    }
}
