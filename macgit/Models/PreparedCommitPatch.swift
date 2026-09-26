// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct PreparedCommitPatch: Identifiable, Sendable {
    let id = UUID()
    let request: CommitPatchRequest
    let repositoryURL: URL
    let parent: String
    let targetBranch: String
    let targetHead: String
    let paths: [String]
    var patch: String
    let fingerprint: String
    var reviewFiles: [CommitPatchReviewFile] = []

    var hasConflicts: Bool { reviewFiles.contains { $0.state == .conflict } }
    var hasChanges: Bool { !patch.isEmpty }

    mutating func rebuildPatch() {
        patch = reviewFiles.filter(\.appliesChanges).map(\.patch).joined()
    }
}
