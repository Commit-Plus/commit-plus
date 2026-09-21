// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import FirebaseCore

extension MainWindowView {
    func commitRulePreferenceChanged() {
        let settings = repoSettings
        let uid = accountController.account?.uid
        Task {
            do {
                try await repoSettingsStore.update(for: repositoryURL.path, settings: settings, pendingCommitRuleUID: uid)
                await reconcileCommitRulePreference()
            } catch { syncState.showError(error.localizedDescription) }
        }
    }

    func reconcileCommitRulePreference() async {
        let uid = accountController.account?.uid
        commitRuleSyncController.setSession(uid: uid, repositoryURL: repositoryURL)
        guard didPerformInitialLoad, uid != nil, FirebaseApp.app() != nil else { return }
        let warning = await commitRuleSyncController.reconcile(
            repositoryURL: repositoryURL,
            uid: uid,
            cloud: FirestoreRepositoryCommitRuleStore()
        ) { value in
            guard accountController.account?.uid == uid else { return }
            repoSettings.skipProtectedBranchCommitWarnings = value
        }
        if let warning, accountController.account?.uid == uid {
            syncState.showInfo(warning)
        }
    }

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
