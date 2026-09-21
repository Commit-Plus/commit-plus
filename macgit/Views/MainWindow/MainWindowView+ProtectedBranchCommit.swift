// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

extension MainWindowView {
    func authorizeProtectedBranchCommit() async -> Bool {
        await protectedBranchCommitController.authorize(
            repositoryURL: repositoryURL,
            settings: repoSettingsStore.settings(for: repositoryURL.path, currentBranch: nil, remotes: []),
            credentials: providerCredentialResolver,
            syncState: syncState,
            undoManager: undoManager
        )
    }

    func performPendingToolbarCommit() {
        guard let pending = pendingToolbarCommit else { return }
        pendingToolbarCommit = nil
        runRepositoryOperation("Committing changes...") {
            await commitFromToolbar(message: pending.message, commitAllChanges: pending.commitAllChanges)
        }
    }
}
