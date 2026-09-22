// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

protocol RevisionBrowserServing: Sendable {
    func browserSnapshot(revision: String, in repositoryURL: URL) async throws -> RevisionBrowserSnapshot
    func browserEntries(treeID: String, parentPath: String, in repositoryURL: URL) async throws -> [RevisionTreeEntry]
    func browserPreview(entry: RevisionTreeEntry, in repositoryURL: URL) async throws -> RevisionFilePreview
}
