// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct HistoryRebaseAvailability: Sendable {
    var branch: String?
    var head: String?
    /// First-parent history of HEAD: the commits the current branch can be rebased onto in place.
    var ancestors: Set<String> = []
    /// Every commit reachable from HEAD, including commits brought in by merges.
    var reachable: Set<String> = []
    var quickCommits: Set<String> = []
    var squashCommits: Set<String> = []

    func actions(for commit: Commit) -> [HistoryRebasePlan.Action] {
        guard quickCommits.contains(commit.hash) else { return [] }
        let drop: [HistoryRebasePlan.Action] = commit.parents.isEmpty && commit.hash == head ? [] : [.drop]
        return [.reword, .edit] + (squashCommits.contains(commit.hash) ? [.squash, .fixup] : []) + drop
    }

    /// Commits already on the current branch get in-place rewrite actions instead of merge/rebase.
    func isOnCurrentBranch(_ commit: Commit) -> Bool {
        reachable.contains(commit.hash)
    }

    func canInteractivelyRebase(to commit: Commit) -> Bool {
        branch != nil && commit.hash != head && (ancestors.contains(commit.hash) || !isOnCurrentBranch(commit))
    }
}
