// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import FirebaseCore

extension MainWindowView {
    func commitRulePreferenceChanged() {
        let settings = repoSettings
        let uid = accountController.cloudSyncUID
        Task {
            do {
                try await repoSettingsStore.update(for: repositoryURL.path, settings: settings, pendingCommitRuleUID: uid)
                await reconcileCommitRulePreference()
            } catch { syncState.showError(error.localizedDescription) }
        }
    }

    func reconcileCommitRulePreference() async {
        let uid = accountController.cloudSyncUID
        commitRuleSyncController.isCloudSyncAllowed = { [accountController] in accountController.cloudSyncUID == $0 }
        commitRuleSyncController.setSession(uid: uid, repositoryURL: repositoryURL)
        guard didPerformInitialLoad, uid != nil, FirebaseApp.app() != nil else { return }
        let warning = await commitRuleSyncController.reconcile(
            repositoryURL: repositoryURL,
            uid: uid,
            cloud: FirestoreRepositoryCommitRuleStore()
        ) { value in
            guard accountController.cloudSyncUID == uid else { return }
            repoSettings.skipProtectedBranchCommitWarnings = value
        }
        if let warning, accountController.cloudSyncUID == uid {
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

    var protectedBranchWarningOutsideCommit: Binding<ProtectedBranchCommitController.Warning?> {
        Binding(
            get: { showingCommitSheet ? nil : protectedBranchCommitController.warning },
            set: { protectedBranchCommitController.warning = $0 }
        )
    }
}
