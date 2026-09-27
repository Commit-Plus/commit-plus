// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

/// Starts optional cloud work after the first window is ready and keeps it
/// process-scoped even when several SwiftUI windows request the same session.
@MainActor
final class AppCloudLifecycleController: ObservableObject {
    private enum AccountRequest: Equatable {
        case notStarted
        case session(String?)
    }

    private let startFeaturePolicy: () -> Void
    private let synchronizeAccount: (AccountSnapshot?) async -> Void
    private var didStart = false
    private var accountRequest = AccountRequest.notStarted
    private var pendingAccount: (request: AccountRequest, account: AccountSnapshot?)?
    private var isSynchronizingAccount = false
    private var accountWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        startFeaturePolicy: @escaping () -> Void,
        synchronizeAccount: @escaping (AccountSnapshot?) async -> Void
    ) {
        self.startFeaturePolicy = startFeaturePolicy
        self.synchronizeAccount = synchronizeAccount
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        startFeaturePolicy()
    }

    func updateAccount(_ account: AccountSnapshot?) async {
        let request = AccountRequest.session(account?.uid)
        if accountRequest == request {
            if isSynchronizingAccount {
                await withCheckedContinuation { accountWaiters.append($0) }
            }
            return
        }

        accountRequest = request
        pendingAccount = (request, account)
        guard !isSynchronizingAccount else {
            await withCheckedContinuation { accountWaiters.append($0) }
            return
        }

        isSynchronizingAccount = true
        while let pendingAccount {
            self.pendingAccount = nil
            // Account reconciliation mutates shared local stores. Complete the
            // active session, then skip directly to the newest queued session.
            await synchronizeAccount(pendingAccount.account)
        }
        isSynchronizingAccount = false
        let waiters = accountWaiters
        accountWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
