// SPDX-License-Identifier: AGPL-3.0-or-later

/// A history table item keeps pagination UI separate from commit data.
enum HistoryTableRow: Identifiable {
    case commit(Commit)
    case loading

    var id: String {
        switch self {
        case .commit(let commit): commit.id
        case .loading: "history-loading-older"
        }
    }

    var commit: Commit? {
        guard case .commit(let commit) = self else { return nil }
        return commit
    }
}
