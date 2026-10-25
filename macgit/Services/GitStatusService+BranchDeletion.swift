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
    /// Deletes local branches only and runs no network commands. Unvalidated branches are
    /// deleted with one `git branch` call; validated (merged cleanup) branches keep their
    /// per-branch tip checks.
    func deleteLocalBranches(
        _ request: GitLocalBranchDeletionRequest,
        validate: (@MainActor (String) async throws -> String)?,
        in repositoryURL: URL
    ) async -> (deleted: [GitDeletedLocalBranch], failures: [GitBranchDeletionFailure]) {
        var deleted: [String: GitDeletedLocalBranch] = [:]
        var failures: [String: GitBranchDeletionFailure] = [:]
        func fail(_ branch: String, _ error: Error) {
            failures[branch] = GitBranchDeletionFailure(name: branch, message: Self.branchDeletionErrorMessage(error))
        }

        var candidates: [String] = []
        for branch in request.branches where !candidates.contains(branch) {
            if branch == request.currentBranch {
                fail(branch, GitError.commandFailed("Cannot delete the currently checked out branch. Please switch to another branch first."))
            } else {
                candidates.append(branch)
            }
        }

        let refs = await localBranchRefs(candidates, in: repositoryURL)
        var batch: [String] = []
        for branch in candidates {
            guard let ref = refs[branch] else {
                fail(branch, GitError.commandFailed("Branch '\(branch)' not found."))
                continue
            }
            guard let validate else {
                batch.append(branch)
                continue
            }
            do {
                let validatedTip = try await validate(branch)
                let tip = try await GitBranchUndoSupport().tip(of: "refs/heads/\(branch)", in: repositoryURL)
                guard validatedTip == tip else {
                    throw GitError.commandFailed("The branch changed while its merge status was being verified. Refresh merge status and try again.")
                }
                _ = try await deleteValidatedMergedBranch(name: branch, expectedTip: validatedTip, in: repositoryURL)
                deleted[branch] = GitDeletedLocalBranch(
                    name: branch,
                    tip: tip,
                    upstream: ref.upstream,
                    force: request.force,
                    remoteTarget: request.remoteTargets[branch]
                )
            } catch {
                fail(branch, error)
            }
        }

        if !batch.isEmpty {
            // `git branch -d` keeps going after a failed name, so the refs left behind
            // tell which deletions failed and stderr explains why.
            var errorOutput: String?
            do {
                _ = try await runGit(arguments: ["branch", request.force ? "-D" : "-d"] + batch, in: repositoryURL)
            } catch {
                errorOutput = error.localizedDescription
            }
            await invalidateBranchListCache(in: repositoryURL)
            let remaining = errorOutput == nil ? [:] : await localBranchRefs(batch, in: repositoryURL)
            for branch in batch {
                if remaining[branch] != nil {
                    fail(branch, GitError.commandFailed(Self.branchDeletionErrorLine(for: branch, in: errorOutput ?? "")))
                } else if let ref = refs[branch] {
                    deleted[branch] = GitDeletedLocalBranch(
                        name: branch,
                        tip: ref.tip,
                        upstream: ref.upstream,
                        force: request.force,
                        remoteTarget: request.remoteTargets[branch]
                    )
                }
            }
        }

        return (
            candidates.compactMap { deleted[$0] },
            request.branches.reduce(into: [GitBranchDeletionFailure]()) { result, branch in
                if let failure = failures[branch], !result.contains(failure) { result.append(failure) }
            }
        )
    }

    /// Tips and upstreams of the given local branches in one `for-each-ref` call.
    /// Branches that do not exist are missing from the result.
    private func localBranchRefs(
        _ branches: [String],
        in repositoryURL: URL
    ) async -> [String: (tip: String, upstream: String?)] {
        guard !branches.isEmpty else { return [:] }
        let wanted = Set(branches)
        let output = (try? await runGit(
            arguments: ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(upstream:short)"]
                + branches.map { "refs/heads/\($0)" },
            in: repositoryURL
        )) ?? ""
        var refs: [String: (tip: String, upstream: String?)] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, fields[0].hasPrefix("refs/heads/") else { continue }
            // for-each-ref patterns also match refs nested under a selected name.
            let name = String(fields[0].dropFirst("refs/heads/".count))
            guard wanted.contains(name) else { continue }
            refs[name] = (fields[1], fields[2].isEmpty ? nil : fields[2])
        }
        return refs
    }

    /// The `error:` line git printed for one branch of a multi-branch `git branch -d`.
    nonisolated static func branchDeletionErrorLine(for branch: String, in output: String) -> String {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if let line = lines.first(where: { $0.hasPrefix("error:") && $0.contains("'\(branch)'") }) {
            return String(line.dropFirst("error:".count)).trimmingCharacters(in: .whitespaces)
        }
        return output.isEmpty ? "Could not delete branch '\(branch)'." : output
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

    /// Failure message for a background batch deletion. The first line counts failures so
    /// the background activity summary reads as an error.
    nonisolated static func branchDeletionFailureMessage(
        localDeletedCount: Int,
        localFailures: [GitBranchDeletionFailure],
        remoteResults: [GitRemoteBranchDeletionResult]
    ) -> String? {
        let failures = localFailures + remoteResults.compactMap(\.failure)
        guard !failures.isEmpty else { return nil }
        let total = localDeletedCount + localFailures.count + remoteResults.count
        let noun = total == 1 ? "branch" : "branches"
        let lines = failures.map { "• \($0.name): \($0.message)" }.joined(separator: "\n")
        return "Could not delete \(failures.count) of \(total) \(noun).\n\n\(lines)"
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
