// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct HistoryRebaseAvailability: Sendable {
    var branch: String?
    var head: String?
    var ancestors: Set<String> = []
    var quickCommits: Set<String> = []
    var squashCommits: Set<String> = []

    func actions(for commit: Commit) -> [HistoryRebasePlan.Action] {
        guard quickCommits.contains(commit.hash) else { return [] }
        let drop: [HistoryRebasePlan.Action] = commit.parents.isEmpty && commit.hash == head ? [] : [.drop]
        return [.reword, .edit] + (squashCommits.contains(commit.hash) ? [.squash, .fixup] : []) + drop
    }
}
