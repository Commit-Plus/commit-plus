// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct GitLocalBranchDeletionRequest {
    let branches: [String]
    let force: Bool
    let currentBranch: String
    /// Remote branches to delete after each local branch, keyed by local branch name.
    let remoteTargets: [String: RemoteBranchDeleteTarget]
}

struct GitDeletedLocalBranch: Equatable {
    let name: String
    let tip: String
    let upstream: String?
    let force: Bool
    let remoteTarget: RemoteBranchDeleteTarget?
}

struct GitBranchDeletionFailure: Equatable {
    let name: String
    let message: String
}

struct GitPendingRemoteBranchDeletion: Equatable {
    let target: RemoteBranchDeleteTarget
    /// The locally deleted branch whose undo entry depends on this remote deletion.
    let localBranch: GitDeletedLocalBranch?
}

struct GitRemoteBranchDeletionResult: Equatable {
    let pending: GitPendingRemoteBranchDeletion
    /// Remote hash before deletion, captured for undo when a local branch is attached.
    let remoteHash: String?
    let failure: GitBranchDeletionFailure?
}

extension GitStatusService {
    /// Deletes local branches only. Runs no network commands, so it stays fast under the blocking overlay.
    func deleteLocalBranches(
        _ request: GitLocalBranchDeletionRequest,
        validate: (@MainActor (String) async throws -> String)?,
        in repositoryURL: URL
    ) async -> (deleted: [GitDeletedLocalBranch], failures: [GitBranchDeletionFailure]) {
        let support = GitBranchUndoSupport()
        var deleted: [GitDeletedLocalBranch] = []
        var failures: [GitBranchDeletionFailure] = []
        for branch in request.branches {
            do {
                guard branch != request.currentBranch else {
                    throw GitError.commandFailed("Cannot delete the currently checked out branch. Please switch to another branch first.")
                }
                let validatedTip = try await validate?(branch)
                let tip = try await support.tip(of: "refs/heads/\(branch)", in: repositoryURL)
                if let validatedTip, validatedTip != tip {
                    throw GitError.commandFailed("The branch changed while its merge status was being verified. Refresh merge status and try again.")
                }
                let upstream = await support.upstream(of: branch, in: repositoryURL)
                if let validatedTip {
                    _ = try await deleteValidatedMergedBranch(name: branch, expectedTip: validatedTip, in: repositoryURL)
                } else {
                    _ = try await deleteBranch(name: branch, force: request.force, in: repositoryURL)
                }
                deleted.append(GitDeletedLocalBranch(
                    name: branch,
                    tip: tip,
                    upstream: upstream,
                    force: request.force,
                    remoteTarget: request.remoteTargets[branch]
                ))
            } catch {
                failures.append(GitBranchDeletionFailure(
                    name: branch,
                    message: Self.branchDeletionErrorMessage(error)
                ))
            }
        }
        return (deleted, failures)
    }

    /// Deletes each remote branch in order, continuing after failures.
    func deleteRemoteBranches(
        _ pending: [GitPendingRemoteBranchDeletion],
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async -> [GitRemoteBranchDeletionResult] {
        var results: [GitRemoteBranchDeletionResult] = []
        for item in pending {
            do {
                var remoteHash: String?
                if item.localBranch != nil {
                    remoteHash = try await remoteBranchHash(
                        remote: item.target.remote,
                        branch: item.target.branch,
                        in: repositoryURL,
                        credentialResolver: credentialResolver
                    )
                }
                _ = try await deleteRemoteBranch(
                    remote: item.target.remote,
                    name: item.target.branch,
                    in: repositoryURL,
                    credentialResolver: credentialResolver
                )
                results.append(GitRemoteBranchDeletionResult(pending: item, remoteHash: remoteHash, failure: nil))
            } catch {
                results.append(GitRemoteBranchDeletionResult(
                    pending: item,
                    remoteHash: nil,
                    failure: GitBranchDeletionFailure(
                        name: item.target.fullPath,
                        message: Self.branchDeletionErrorMessage(error)
                    )
                ))
            }
        }
        return results
    }

    nonisolated static func branchDeletionErrorMessage(_ error: Error) -> String {
        let description = error.localizedDescription
        let raw = description.lowercased()
        if raw.contains("cannot delete branch") && raw.contains("used by worktree") {
            if let range = description.range(of: "'", options: .backwards),
               let startRange = description.range(of: "'"),
               startRange.upperBound <= range.lowerBound {
                let branchName = String(description[startRange.upperBound..<range.lowerBound])
                return "Cannot delete branch '\(branchName)' because it is currently checked out. Please switch to another branch first."
            }
            return "Cannot delete the currently checked out branch. Please switch to another branch first."
        }
        if raw.contains("not fully merged") {
            return "This branch is not fully merged. Enable 'Force delete regardless of merge status' to delete it anyway."
        }
        if raw.contains("remote ref does not exist") {
            return "The remote branch does not exist or has already been deleted."
        }
        return description
    }

    nonisolated static func branchDeletionSummary(deletedCount: Int, failures: [GitBranchDeletionFailure]) -> String {
        let deletion = deletedCount == 1
            ? "Deleted 1 selected branch."
            : "Deleted \(deletedCount) selected branches."
        let skipped = failures.map { "• \($0.name): \($0.message)" }.joined(separator: "\n")
        return "\(deletion)\n\nCould not complete:\n\(skipped)"
    }

    /// First line counts failures so the background activity summary reads as an error.
    nonisolated static func remoteBranchDeletionFailureMessage(_ results: [GitRemoteBranchDeletionResult]) -> String? {
        let failures = results.compactMap(\.failure)
        guard !failures.isEmpty else { return nil }
        let noun = results.count == 1 ? "remote branch" : "remote branches"
        let lines = failures.map { "• \($0.name): \($0.message)" }.joined(separator: "\n")
        return "Could not delete \(failures.count) of \(results.count) \(noun).\n\n\(lines)"
    }

    nonisolated static func remoteBranchDeletionTitle(_ pending: [GitPendingRemoteBranchDeletion]) -> String {
        if pending.count == 1, let target = pending.first?.target {
            return "Deleting \(target.fullPath)"
        }
        return "Deleting \(pending.count) remote branches"
    }
}
