// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum BranchMergeAssessmentState: String, Codable, Equatable, Sendable {
    case fullyMerged
    case notFullyMerged
    case unknown
}

enum BranchMergeEvidenceKind: String, Codable, Equatable, Sendable {
    case gitAncestry
    case pullRequest
}

struct BranchMergeEvidence: Codable, Equatable, Sendable {
    let kind: BranchMergeEvidenceKind
    let title: String
    let webURL: URL?
    let targetBranch: String?
    let mergedAt: Date?
}

struct BranchMergeAssessment: Codable, Equatable, Sendable {
    let branch: String
    let tipSHA: String
    let state: BranchMergeAssessmentState
    let evidence: [BranchMergeEvidence]
    let detail: String
    let checkedAt: Date

    var isFullyMerged: Bool { state == .fullyMerged }
}

struct ProviderMergedChange: Equatable, Sendable {
    let number: Int
    let title: String
    let sourceRepository: GitRepositoryIdentity
    let sourceBranch: String
    let sourceSHA: String
    let targetRepository: GitRepositoryIdentity
    let targetBranch: String
    let webURL: URL
    let mergedAt: Date?
}

protocol BranchMergeEvidenceProviding: Sendable {
    func mergedChanges(
        targetRepository: GitRepositoryIdentity,
        sourceRepository: GitRepositoryIdentity,
        sourceBranch: String,
        token: GitProviderToken
    ) async throws -> [ProviderMergedChange]
}

