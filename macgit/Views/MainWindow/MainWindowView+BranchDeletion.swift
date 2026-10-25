// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

typealias RemoteBranchDeletionRunner = ([GitPendingRemoteBranchDeletion]) -> Void
typealias BranchDeletionRunner = (GitBranchDeletionJob) -> Void

/// A batch deletion from the Delete Branches sheet, run in the window's background lane.
struct GitBranchDeletionJob {
    let local: GitLocalBranchDeletionRequest
    let validate: (@MainActor (String) async throws -> String)?
    /// Remote branches selected directly, deleted after the local phase.
    let remoteTargets: [RemoteBranchDeleteTarget]
    /// Runs on the main actor after any branch was deleted.
    let onDeleted: @MainActor () -> Void

    var remotes: [String] {
        var remotes: [String] = []
        for target in local.remoteTargets.values.sorted(by: { $0.fullPath < $1.fullPath }) + remoteTargets
        where !remotes.contains(target.remote) {
            remotes.append(target.remote)
        }
        return remotes
    }

    var title: String {
        let names = local.branches + remoteTargets.map(\.fullPath)
        if names.count == 1, let name = names.first {
            return "Deleting \(name)"
        }
        return "Deleting \(names.count) branches"
    }
}

extension MainWindowView {
    /// Deletes the selected local branches, then their matching and directly selected
    /// remote branches, without blocking the window. Undo is registered per local branch
    /// once its remote phase is known.
    func runBackgroundBranchDeletion(_ job: GitBranchDeletionJob) {
        runBackgroundRemoteOperation(job.title, remotes: job.remotes) { credentialResolver in
            let local = await GitStatusService.shared.deleteLocalBranches(
                job.local,
                validate: job.validate,
                in: repositoryURL
            )

            // Remote targets of failed local deletes are skipped; directly selected remotes always run.
            var pending = local.deleted.compactMap { deleted in
                deleted.remoteTarget.map { GitPendingRemoteBranchDeletion(target: $0, localBranch: deleted) }
            }
            let pendingTargets = Set(pending.map(\.target))
            for target in job.remoteTargets where !pendingTargets.contains(target) {
                pending.append(GitPendingRemoteBranchDeletion(target: target, localBranch: nil))
            }
            let remoteResults = pending.isEmpty ? [] : await GitStatusService.shared.deleteRemoteBranches(
                pending,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )

            await MainActor.run {
                let remoteResultByLocal = Dictionary(
                    remoteResults.compactMap { result in result.pending.localBranch.map { ($0.name, result) } },
                    uniquingKeysWith: { first, _ in first }
                )
                for deleted in local.deleted {
                    let remote = remoteResultByLocal[deleted.name].flatMap { $0.failure == nil ? $0 : nil }
                    undoManager.register(
                        GitBranchUndoSupport.deletedBranchUndoEntry(
                            repositoryURL: repositoryURL,
                            branch: deleted.name,
                            force: deleted.force,
                            tip: deleted.tip,
                            upstream: deleted.upstream,
                            remoteTarget: remote?.pending.target,
                            remoteHash: remote?.remoteHash
                        )
                    )
                }
            }

            let didDelete = !local.deleted.isEmpty || remoteResults.contains { $0.failure == nil }
            if didDelete {
                await syncState.refresh(repositoryURL: repositoryURL)
                await MainActor.run {
                    for result in remoteResults where result.failure == nil && result.pending.localBranch == nil {
                        if selectedItem == .remoteBranch(result.pending.target.fullPath) {
                            selectedItem = .item(.history)
                        }
                    }
                    if !remoteResults.isEmpty {
                        NotificationCenter.default.post(
                            name: .repositoryRemoteRefsDidRefresh,
                            object: nil,
                            userInfo: ["repositoryURL": repositoryURL, "userInitiated": true]
                        )
                    }
                    NotificationCenter.default.post(
                        name: .repositoryDidChange,
                        object: nil,
                        userInfo: ["repositoryURL": repositoryURL]
                    )
                    job.onDeleted()
                }
            }

            if let message = GitStatusService.branchDeletionFailureMessage(
                localDeletedCount: local.deleted.count,
                localFailures: local.failures,
                remoteResults: remoteResults
            ) {
                return .failed(message)
            }
            return .succeeded
        }
    }

    /// Remote phase of batch branch deletion. Runs in this window's background lane and
    /// registers undo for locally deleted branches once their remote deletion finishes.
    /// If the remote phase never runs (credential prompt cancelled, window closed), the
    /// locally deleted branches still get local-only undo entries.
    func runBackgroundRemoteBranchDeletion(_ pending: [GitPendingRemoteBranchDeletion]) {
        guard !pending.isEmpty else { return }
        var remotes: [String] = []
        for item in pending where !remotes.contains(item.target.remote) {
            remotes.append(item.target.remote)
        }
        runBackgroundRemoteOperation(
            GitStatusService.remoteBranchDeletionTitle(pending),
            remotes: remotes,
            onNotQueued: {
                for item in pending {
                    guard let local = item.localBranch else { continue }
                    undoManager.register(
                        GitBranchUndoSupport.deletedBranchUndoEntry(
                            repositoryURL: repositoryURL,
                            branch: local.name,
                            force: local.force,
                            tip: local.tip,
                            upstream: local.upstream,
                            remoteTarget: nil,
                            remoteHash: nil
                        )
                    )
                }
            }
        ) { credentialResolver in
            let results = await GitStatusService.shared.deleteRemoteBranches(
                pending,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await MainActor.run {
                for result in results {
                    guard let local = result.pending.localBranch else { continue }
                    let deletedRemote = result.failure == nil
                    undoManager.register(
                        GitBranchUndoSupport.deletedBranchUndoEntry(
                            repositoryURL: repositoryURL,
                            branch: local.name,
                            force: local.force,
                            tip: local.tip,
                            upstream: local.upstream,
                            remoteTarget: deletedRemote ? result.pending.target : nil,
                            remoteHash: deletedRemote ? result.remoteHash : nil
                        )
                    )
                }
            }
            await syncState.refresh(repositoryURL: repositoryURL)
            await MainActor.run {
                for result in results where result.failure == nil && result.pending.localBranch == nil {
                    if selectedItem == .remoteBranch(result.pending.target.fullPath) {
                        selectedItem = .item(.history)
                    }
                }
                NotificationCenter.default.post(
                    name: .repositoryRemoteRefsDidRefresh,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL, "userInitiated": true]
                )
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
            if let message = GitStatusService.remoteBranchDeletionFailureMessage(results) {
                return .failed(message)
            }
            return .succeeded
        }
    }
}
