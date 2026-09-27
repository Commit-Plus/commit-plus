// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSSnapshot: Sendable {
    let files: [GitLFSFile]
    let rules: String
    let branch: String
    let remotes: [String]
    let suggestedRemote: String?
    let setupIssue: String?
}
