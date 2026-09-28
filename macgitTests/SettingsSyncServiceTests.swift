//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import XCTest
@testable import macgit

@MainActor
final class SettingsSyncServiceTests: XCTestCase {
    private let local = AppSettingsSnapshot(
        showToolbarButtonText: true,
        showSubmodules: false,
        showSubtrees: false,
        showHeaderBranchButton: true,
        showHeaderMergeButton: true,
        showHeaderStashButton: true,
        showHeaderRemoteButton: true,
        showHeaderFinderButton: true,
        showHeaderTerminalButton: true
    )
    private let cloud = AppSettingsSnapshot(
        appearance: .dark,
        showToolbarButtonText: false,
        showSubmodules: true,
        showSubtrees: true,
        showHeaderBranchButton: false,
        showHeaderMergeButton: false,
        showHeaderStashButton: false,
        showHeaderRemoteButton: false,
        showHeaderFinderButton: false,
        showHeaderTerminalButton: false
    )

    func testGuestIsOffAndDoesNotTouchCloud() async {
        let harness = makeHarness(cloud: cloud)

        await harness.service.updateEligibility(uid: nil, enabled: true)

        XCTAssertEqual(harness.service.status, .off)
        XCTAssertTrue(harness.store.loadedUIDs.isEmpty)
    }

    func testFreeAccountCanSync() async {
        let harness = makeHarness(cloud: cloud)

        await harness.service.updateEligibility(uid: "u1", enabled: true)

        XCTAssertEqual(harness.service.status, .needsInitialChoice(cloud))
        XCTAssertEqual(harness.store.loadedUIDs, ["u1"])
    }

    func testAuthenticatedAccountWithDeviceSyncDisabledIsOff() async {
        let harness = makeHarness(cloud: cloud)

        await harness.service.updateEligibility(uid: "u1", enabled: false)

        XCTAssertEqual(harness.service.status, .off)
        XCTAssertTrue(harness.store.loadedUIDs.isEmpty)
    }

    func testFirstEnableWithNoCloudSettingsUploadsLocalWithoutRealtimeObservation() async {
        let harness = makeHarness(cloud: nil)

        await harness.service.updateEligibility(uid: "u1", enabled: true)

        XCTAssertEqual(harness.store.saves, [.init(uid: "u1", snapshot: local)])
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)
        XCTAssertEqual(harness.service.status, .syncing)
    }

    func testEqualCloudSettingsStartSessionWithoutUploadOrRealtimeObservation() async {
        let harness = makeHarness(cloud: local)

        await harness.service.updateEligibility(uid: "u1", enabled: true)

        XCTAssertTrue(harness.store.saves.isEmpty)
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)
        XCTAssertEqual(harness.service.status, .syncing)
    }

    func testConflictingCloudSettingsRequireInitialChoice() async {
        let harness = makeHarness(cloud: cloud)

        await harness.service.updateEligibility(uid: "u1", enabled: true)

        XCTAssertEqual(harness.service.status, .needsInitialChoice(cloud))
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)
    }

    func testUseCloudChoiceAppliesCloudWithoutUploadingOrStartingRealtimeObservation() async {
        let harness = makeHarness(cloud: cloud)
        await harness.service.updateEligibility(uid: "u1", enabled: true)

        await harness.service.resolveInitialChoice(.useCloud)

        XCTAssertEqual(harness.local.value, cloud)
        XCTAssertTrue(harness.store.saves.isEmpty)
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)
        XCTAssertEqual(harness.service.status, .syncing)
    }

    func testKeepThisMacChoiceUploadsCurrentLocalWithoutStartingRealtimeObservation() async {
        let harness = makeHarness(cloud: cloud)
        await harness.service.updateEligibility(uid: "u1", enabled: true)

        await harness.service.resolveInitialChoice(.keepThisMac)

        XCTAssertEqual(harness.store.saves, [.init(uid: "u1", snapshot: local)])
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)
        XCTAssertEqual(harness.service.status, .syncing)
    }

    func testCancelChoiceTurnsDeviceSyncOff() async {
        let harness = makeHarness(cloud: cloud)
        await harness.service.updateEligibility(uid: "u1", enabled: true)

        await harness.service.resolveInitialChoice(.cancel)

        XCTAssertEqual(harness.syncEnabled.values, [false])
        XCTAssertEqual(harness.service.status, .off)
    }

    func testRemoteChangesDoNotApplyDuringActiveSession() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", enabled: true)

        harness.store.send(cloud)

        XCTAssertEqual(harness.local.value, local)
        XCTAssertTrue(harness.store.saves.isEmpty)
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)
    }

    func testRemoteChangesAreComparedWhenNextSessionStarts() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", enabled: true)

        harness.store.send(cloud)
        await harness.service.updateEligibility(uid: nil, enabled: true)
        await harness.service.updateEligibility(uid: "u1", enabled: true)

        XCTAssertEqual(harness.local.value, local)
        XCTAssertEqual(harness.service.status, .needsInitialChoice(cloud))
        XCTAssertEqual(harness.store.loadedUIDs, ["u1", "u1"])
    }

    func testLocalEditsAreDebouncedAndOnlyLatestSnapshotUploads() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", enabled: true)
        let first = AppSettingsSnapshot(
            appearance: .light,
            showToolbarButtonText: false,
            showSubmodules: false,
            showSubtrees: false,
            showHeaderBranchButton: true,
            showHeaderMergeButton: true,
            showHeaderStashButton: true,
            showHeaderRemoteButton: true,
            showHeaderFinderButton: true,
            showHeaderTerminalButton: true
        )

        harness.service.localSettingsDidChange(first)
        harness.service.localSettingsDidChange(cloud)
        await harness.scheduler.fireAll()

        XCTAssertEqual(harness.store.saves, [.init(uid: "u1", snapshot: cloud)])
    }

    func testCloudChangesDoNotOverrideLocalWhenUploadFails() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", enabled: true)
        var edited = local
        edited.showToolbarButtonText = false
        harness.local.value = edited
        harness.store.saveError = TestSettingsSyncError.saveFailed

        harness.service.localSettingsDidChange(edited)
        harness.store.send(local)
        XCTAssertEqual(harness.local.value, edited)

        await harness.scheduler.fireAll()
        harness.store.send(local)

        XCTAssertEqual(harness.local.value, edited)
        XCTAssertEqual(harness.service.status, .failed("Settings save failed."))
    }

    func testCloudChangesRemainDeferredAfterLocalUploadSucceeds() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", enabled: true)
        var edited = local
        edited.showHeaderMergeButton = false
        harness.local.value = edited

        harness.service.localSettingsDidChange(edited)
        harness.store.send(local)
        XCTAssertEqual(harness.local.value, edited)

        await harness.scheduler.fireAll()
        harness.store.send(cloud)

        XCTAssertEqual(harness.local.value, edited)
    }

    func testRevertingLocalEditBeforeUploadKeepsLatestLocalValue() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", enabled: true)
        var edited = local
        edited.showToolbarButtonText = false

        harness.service.localSettingsDidChange(edited)
        harness.service.localSettingsDidChange(local)
        await harness.scheduler.fireAll()

        XCTAssertEqual(harness.store.saves, [.init(uid: "u1", snapshot: local)])
    }

    func testSignOutAndDisableCancelPendingUploadAndActiveSession() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", enabled: true)
        harness.service.localSettingsDidChange(cloud)

        await harness.service.updateEligibility(uid: nil, enabled: true)
        XCTAssertEqual(harness.service.status, .off)

        await harness.service.updateEligibility(uid: "u1", enabled: true)
        await harness.service.updateEligibility(uid: "u1", enabled: false)
        XCTAssertEqual(harness.service.status, .off)
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)

        await harness.scheduler.fireAll()
        XCTAssertTrue(harness.store.saves.isEmpty)
    }

    func testAuthenticatedAccountResumesWhenDevicePreferenceIsReenabled() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", enabled: false)
        XCTAssertEqual(harness.service.status, .off)

        await harness.service.updateEligibility(uid: "u1", enabled: true)

        XCTAssertEqual(harness.store.loadedUIDs, ["u1"])
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)
        XCTAssertEqual(harness.service.status, .syncing)
    }

    func testRepeatedEligibilityUpdateRestartsAnUnfinishedStartup() async {
        let harness = makeHarness(cloud: local)
        harness.store.shouldSuspendLoads = true

        let firstUpdate = Task {
            await harness.service.updateEligibility(uid: "u1", enabled: true)
        }
        await Task.yield()
        XCTAssertEqual(harness.store.loadedUIDs, ["u1"])
        XCTAssertEqual(harness.service.status, .starting)

        firstUpdate.cancel()
        let replacementUpdate = Task {
            await harness.service.updateEligibility(uid: "u1", enabled: true)
        }
        await Task.yield()

        XCTAssertEqual(harness.store.loadedUIDs, ["u1", "u1"])

        harness.store.resumeSuspendedLoads()
        await firstUpdate.value
        await replacementUpdate.value
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)
        XCTAssertEqual(harness.service.status, .syncing)
    }

    private func makeHarness(cloud: AppSettingsSnapshot?) -> Harness {
        let store = FakeCloudSettingsStore(cloud: cloud)
        let localBox = SnapshotBox(local)
        let syncEnabled = BoolRecorder()
        let scheduler = ManualSettingsSyncScheduler()
        let service = SettingsSyncService(
            store: store,
            currentSnapshot: { localBox.value },
            applySnapshot: { localBox.value = $0 },
            setSyncEnabled: { syncEnabled.values.append($0) },
            debounceScheduler: scheduler
        )
        return Harness(
            service: service,
            store: store,
            local: localBox,
            syncEnabled: syncEnabled,
            scheduler: scheduler
        )
    }
}

@MainActor
private struct Harness {
    let service: SettingsSyncService
    let store: FakeCloudSettingsStore
    let local: SnapshotBox
    let syncEnabled: BoolRecorder
    let scheduler: ManualSettingsSyncScheduler
}

private final class SnapshotBox {
    var value: AppSettingsSnapshot
    init(_ value: AppSettingsSnapshot) { self.value = value }
}

private final class BoolRecorder {
    var values: [Bool] = []
}

@MainActor
private final class FakeCloudSettingsStore: CloudSettingsStore {
    struct Save: Equatable {
        let uid: String
        let snapshot: AppSettingsSnapshot
    }

    var cloud: AppSettingsSnapshot?
    var loadedUIDs: [String] = []
    var observedUIDs: [String] = []
    var saves: [Save] = []
    var tokens: [SyncFakeObservationToken] = []
    var shouldSuspendLoads = false
    var saveError: Error?
    private var onChange: ((Result<AppSettingsSnapshot, Error>) -> Void)?
    private var suspendedLoadContinuations: [CheckedContinuation<AppSettingsSnapshot?, Never>] = []

    init(cloud: AppSettingsSnapshot?) {
        self.cloud = cloud
    }

    func load(uid: String) async throws -> AppSettingsSnapshot? {
        loadedUIDs.append(uid)
        if shouldSuspendLoads {
            return await withCheckedContinuation { continuation in
                suspendedLoadContinuations.append(continuation)
            }
        }
        return cloud
    }

    func resumeSuspendedLoads() {
        let continuations = suspendedLoadContinuations
        suspendedLoadContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: cloud)
        }
    }

    func save(_ snapshot: AppSettingsSnapshot, uid: String) async throws {
        saves.append(.init(uid: uid, snapshot: snapshot))
        if let saveError {
            throw saveError
        }
        cloud = snapshot
    }

    func observe(
        uid: String,
        onChange: @escaping (Result<AppSettingsSnapshot, Error>) -> Void
    ) -> ObservationToken {
        observedUIDs.append(uid)
        self.onChange = onChange
        let token = SyncFakeObservationToken()
        tokens.append(token)
        return token
    }

    func send(_ snapshot: AppSettingsSnapshot) {
        cloud = snapshot
        onChange?(.success(snapshot))
    }
}

private enum TestSettingsSyncError: LocalizedError {
    case saveFailed

    var errorDescription: String? {
        "Settings save failed."
    }
}

private final class SyncFakeObservationToken: ObservationToken {
    private(set) var cancelCount = 0
    func cancel() { cancelCount += 1 }
}

@MainActor
private final class ManualSettingsSyncScheduler: SettingsSyncDebounceScheduling {
    private struct Scheduled {
        let token: SyncFakeObservationToken
        let operation: @MainActor () async -> Void
    }

    private var scheduled: [Scheduled] = []

    func schedule(_ operation: @escaping @MainActor () async -> Void) -> ObservationToken {
        let token = SyncFakeObservationToken()
        scheduled.append(.init(token: token, operation: operation))
        return token
    }

    func fireAll() async {
        let pending = scheduled
        scheduled.removeAll()
        for item in pending where item.token.cancelCount == 0 {
            await item.operation()
        }
    }
}
