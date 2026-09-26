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
    let patch: String
    let fingerprint: String
}
