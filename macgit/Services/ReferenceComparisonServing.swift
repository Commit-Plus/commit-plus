// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

protocol ReferenceComparisonServing: Sendable {
    func comparisonRevisions(in repositoryURL: URL) async throws -> [String]
    func pathComparisonSnapshot(base: String, target: ComparisonEndpoint, path: ComparisonPath,
                                in repositoryURL: URL) async throws -> ReferenceComparisonSnapshot
    func comparisonBranches(in repositoryURL: URL) async throws -> [ComparisonBranch]
    func comparisonSnapshot(base: String, target: String, branchesOnly: Bool, in repositoryURL: URL) async throws -> ReferenceComparisonSnapshot
    func comparisonFiles(snapshot: ReferenceComparisonSnapshot, mode: ReferenceComparisonMode, in repositoryURL: URL) async throws -> [CommitFileChange]
    func comparisonCommits(snapshot: ReferenceComparisonSnapshot, targetSide: Bool, skip: Int, limit: Int, in repositoryURL: URL) async throws -> [Commit]
    func comparisonPatch(file: CommitFileChange, snapshot: ReferenceComparisonSnapshot, mode: ReferenceComparisonMode, in repositoryURL: URL) async throws -> ReferenceComparisonPatch
}
