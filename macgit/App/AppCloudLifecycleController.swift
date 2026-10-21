// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

/// Starts optional cloud work after the first window is ready and keeps it
/// process-scoped even when several SwiftUI windows request the same session.
@MainActor
final class AppCloudLifecycleController: ObservableObject {
    private enum AccountRequest: Equatable {
        case notStarted
        case session(uid: String?, cloudSyncEnabled: Bool)
    }

    private let startFeaturePolicy: () -> Void
    private let synchronizeAccount: (AccountSnapshot?, Bool) async -> Void
    private var didStart = false
    private var accountRequest = AccountRequest.notStarted
    private var pendingAccount: (request: AccountRequest, account: AccountSnapshot?, cloudSyncEnabled: Bool)?
    private var isSynchronizingAccount = false
    private var accountWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        startFeaturePolicy: @escaping () -> Void,
        synchronizeAccount: @escaping (AccountSnapshot?, Bool) async -> Void
    ) {
        self.startFeaturePolicy = startFeaturePolicy
        self.synchronizeAccount = synchronizeAccount
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        startFeaturePolicy()
    }

    /// `cloudSyncEnabled` mirrors the account's "Sync app settings" toggle; when it is off,
    /// account-scoped data stays local and no cloud reads or writes are started.
    func updateAccount(_ account: AccountSnapshot?, cloudSyncEnabled: Bool) async {
        let cloudSyncEnabled = cloudSyncEnabled && account != nil
        let request = AccountRequest.session(uid: account?.uid, cloudSyncEnabled: cloudSyncEnabled)
        if accountRequest == request {
            if isSynchronizingAccount {
                await withCheckedContinuation { accountWaiters.append($0) }
            }
            return
        }

        accountRequest = request
        pendingAccount = (request, account, cloudSyncEnabled)
        guard !isSynchronizingAccount else {
            await withCheckedContinuation { accountWaiters.append($0) }
            return
        }

        isSynchronizingAccount = true
        while let pendingAccount {
            self.pendingAccount = nil
            // Account reconciliation mutates shared local stores. Complete the
            // active session, then skip directly to the newest queued session.
            await synchronizeAccount(pendingAccount.account, pendingAccount.cloudSyncEnabled)
        }
        isSynchronizingAccount = false
        let waiters = accountWaiters
        accountWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
