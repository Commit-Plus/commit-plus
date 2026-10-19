// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

typealias RemoteBranchDeletionRunner = ([GitPendingRemoteBranchDeletion]) -> Void

extension MainWindowView {
    /// Remote phase of batch branch deletion. Runs in this window's background lane and
    /// registers undo for locally deleted branches once their remote deletion finishes.
    func runBackgroundRemoteBranchDeletion(_ pending: [GitPendingRemoteBranchDeletion]) {
        guard !pending.isEmpty else { return }
        var remotes: [String] = []
        for item in pending where !remotes.contains(item.target.remote) {
            remotes.append(item.target.remote)
        }
        runBackgroundRemoteOperation(
            GitStatusService.remoteBranchDeletionTitle(pending),
            remotes: remotes
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
