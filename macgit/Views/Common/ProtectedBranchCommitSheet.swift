// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ProtectedBranchCommitSheet: View {
    let warning: ProtectedBranchCommitController.Warning
    @Binding var skipWarnings: Bool
    let onDecision: (ProtectedBranchCommitController.Decision) -> Void
    @State private var enteringBranchName = false
    @State private var branchName = ""
    @FocusState private var branchNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(warning.status == .protected ? "Commit to a protected branch?" : "Branch protection could not be checked", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.headline)
            Text(warning.status == .protected
                 ? "\(warning.remoteBranch) has branch protection rules. You can commit your changes on a new branch or continue on \(warning.branch)."
                 : "Commit+ could not read the rules for \(warning.remoteBranch). Check your connection and provider account access, or choose how to continue.")
                .foregroundStyle(.secondary)
            if enteringBranchName {
                TextField("New branch name", text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .focused($branchNameFocused)
                Text("The new branch starts from your current commit and keeps your staged and unstaged changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel", role: .cancel) { onDecision(.cancel) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Commit Anyway") { onDecision(.commitAnyway) }
                Button(enteringBranchName ? "Create Branch and Commit" : "Commit in a New Branch") {
                    if enteringBranchName {
                        onDecision(.newBranch(branchName.trimmingCharacters(in: .whitespacesAndNewlines)))
                    } else {
                        enteringBranchName = true
                        branchNameFocused = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(enteringBranchName && branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Toggle("Skip protected branch commit warnings for this repository", isOn: $skipWarnings)
                .toggleStyle(.checkbox)
            Text("You can change this in Repository Settings → Advanced. Remote push rules still apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 560)
    }
}
