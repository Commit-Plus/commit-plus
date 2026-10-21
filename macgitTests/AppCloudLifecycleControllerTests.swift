// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class AppCloudLifecycleControllerTests: XCTestCase {
    func testStartIsIdempotent() {
        var starts = 0
        let controller = AppCloudLifecycleController(
            startFeaturePolicy: { starts += 1 },
            synchronizeAccount: { _, _ in }
        )

        controller.start()
        controller.start()

        XCTAssertEqual(starts, 1)
    }

    func testSameSessionSynchronizesOnlyOnceAcrossWindows() async {
        var synchronizedUIDs: [String] = []
        let controller = AppCloudLifecycleController(
            startFeaturePolicy: {},
            synchronizeAccount: { account, _ in
                synchronizedUIDs.append(account?.uid ?? "guest")
            }
        )
        let account = account(uid: "user-one")

        let first = Task { await controller.updateAccount(account, cloudSyncEnabled: true) }
        await Task.yield()
        let second = Task { await controller.updateAccount(account, cloudSyncEnabled: true) }
        await first.value
        await second.value

        XCTAssertEqual(synchronizedUIDs, ["user-one"])
    }

    func testSessionChangesAreAppliedInOrderAndStaleQueuedWorkIsSkipped() async {
        var synchronizedUIDs: [String] = []
        var releaseFirst: CheckedContinuation<Void, Never>?
        let firstStarted = expectation(description: "First session synchronization started")
        let controller = AppCloudLifecycleController(
            startFeaturePolicy: {},
            synchronizeAccount: { account, _ in
                synchronizedUIDs.append(account?.uid ?? "guest")
                if account?.uid == "user-one" {
                    firstStarted.fulfill()
                    await withCheckedContinuation { releaseFirst = $0 }
                }
            }
        )

        let first = Task { await controller.updateAccount(account(uid: "user-one"), cloudSyncEnabled: true) }
        await fulfillment(of: [firstStarted])
        let second = Task { await controller.updateAccount(account(uid: "user-two"), cloudSyncEnabled: true) }
        await Task.yield()
        let guest = Task { await controller.updateAccount(nil, cloudSyncEnabled: true) }
        await Task.yield()
        releaseFirst?.resume()
        await first.value
        await second.value
        await guest.value

        XCTAssertEqual(synchronizedUIDs, ["user-one", "guest"])
    }

    func testCloudSyncToggleResynchronizesSameAccount() async {
        var sessions: [String] = []
        let controller = AppCloudLifecycleController(
            startFeaturePolicy: {},
            synchronizeAccount: { account, cloudSyncEnabled in
                sessions.append("\(account?.uid ?? "guest")|\(cloudSyncEnabled)")
            }
        )
        let account = account(uid: "user-one")

        await controller.updateAccount(account, cloudSyncEnabled: true)
        await controller.updateAccount(account, cloudSyncEnabled: false)
        await controller.updateAccount(nil, cloudSyncEnabled: true)

        XCTAssertEqual(sessions, ["user-one|true", "user-one|false", "guest|false"])
    }

    private func account(uid: String) -> AccountSnapshot {
        AccountSnapshot(uid: uid, email: nil, displayName: nil, providerIDs: [])
    }
}
