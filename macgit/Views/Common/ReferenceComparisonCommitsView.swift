// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ReferenceComparisonCommitsView: View {
    let controller: ReferenceComparisonController
    let targetSide: Bool

    private var commits: [Commit] { targetSide ? controller.targetCommits : controller.baseCommits }
    private var total: Int { (targetSide ? controller.snapshot?.targetOnlyCount : controller.snapshot?.baseOnlyCount) ?? 0 }
    private var isLoading: Bool { targetSide ? controller.isLoadingTargetCommits : controller.isLoadingBaseCommits }
    private var error: String? { targetSide ? controller.targetCommitsError : controller.baseCommitsError }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Only in \(targetSide ? "Target" : "Base") (\(total))")
                .font(.headline).padding(12)
            Divider()
            if total == 0 {
                EmptyStateView(icon: "checkmark.circle", message: "No unique commits", detail: "All commits on this side are reachable from the other branch.")
            } else {
                List {
                    ForEach(commits) { commit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(commit.message).lineLimit(2)
                            HStack {
                                Text(commit.shortHash).monospaced()
                                Text(commit.author).lineLimit(1)
                                Spacer()
                                Text(commit.date, style: .date)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .textSelection(.enabled)
                    }
                    if let error {
                        Text(error).foregroundStyle(.secondary)
                    }
                    if isLoading {
                        ProgressView("Loading commits…")
                    } else if commits.count < total {
                        Button(error == nil ? "Load more commits" : "Retry") {
                            controller.loadMoreCommits(targetSide: targetSide)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
    }
}
