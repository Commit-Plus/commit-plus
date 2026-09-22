// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService {
    func comparisonRevisions(in repositoryURL: URL) async throws -> [String] {
        let output = try await runGit(arguments: [
            "for-each-ref", "--sort=refname", "--format=%(refname)%00%(symref)",
            "refs/heads/", "refs/remotes/", "refs/tags/"
        ], in: repositoryURL)
        try Task.checkCancellation()
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[1].isEmpty else { return nil }
            return String(fields[0])
        }
    }

    func pathComparisonSnapshot(base: String, target: ComparisonEndpoint, path: ComparisonPath,
                                in repositoryURL: URL) async throws -> ReferenceComparisonSnapshot {
        try path.validate()
        let baseSHA = try await resolveComparisonRef(base, branchesOnly: false, in: repositoryURL)
        let resolvedTarget: ComparisonEndpoint
        let targetSHA: String
        switch target {
        case .revision(let ref):
            targetSHA = try await resolveComparisonRef(ref, branchesOnly: false, in: repositoryURL)
            resolvedTarget = .revision(targetSHA)
        case .workingTree, .index:
            targetSHA = ""
            resolvedTarget = target
        }
        try Task.checkCancellation()
        return ReferenceComparisonSnapshot(base: baseSHA, target: targetSHA, mergeBases: [],
            baseOnlyCount: 0, targetOnlyCount: 0, path: path, targetEndpoint: resolvedTarget)
    }
}
