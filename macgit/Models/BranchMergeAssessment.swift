// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated enum BranchMergeAssessmentState: String, Codable, Equatable, Sendable {
    case fullyMerged
    case notFullyMerged
    case unknown
}

nonisolated enum BranchMergeEvidenceKind: String, Codable, Equatable, Sendable {
    case gitAncestry
    case pullRequest
}

nonisolated struct BranchMergeEvidence: Codable, Equatable, Sendable {
    let kind: BranchMergeEvidenceKind
    let title: String
    let webURL: URL?
    let targetBranch: String?
    let mergedAt: Date?
}

nonisolated struct BranchMergeAssessment: Codable, Equatable, Sendable, Identifiable {
    let branch: String
    let tipSHA: String
    let state: BranchMergeAssessmentState
    let evidence: [BranchMergeEvidence]
    let detail: String
    let checkedAt: Date

    var id: String { "\(branch)|\(tipSHA)" }

    // An ancestry relationship alone also holds for an untouched branch created
    // from main. Only a merged PR/MR covering this tip is actionable evidence.
    var isFullyMerged: Bool {
        state == .fullyMerged && !tipSHA.isEmpty && evidence.contains {
            $0.kind == .pullRequest && $0.webURL?.host != nil
        }
    }
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

