// SPDX-License-Identifier: AGPL-3.0-or-later
import Observation

@Observable @MainActor
final class HistoryCommitSelectionSink {
    private(set) var commitHashes: [String] = []

    func update(_ hashes: [String]) {
        guard hashes != commitHashes else { return }
        commitHashes = hashes
    }
}
