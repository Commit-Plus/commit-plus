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

import Combine
import XCTest
@testable import macgit

final class AppSettingsSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsOnlyApprovedSettings() throws {
        let value = AppSettingsSnapshot(
            appearance: .dark,
            showToolbarButtonText: false,
            showGitFlow: false,
            showWorkspaceReflog: false,
            showWorkspacePullRequests: true,
            showWorkspaceGitLFS: false,
            showSubmodules: true,
            showSubtrees: true,
            showHeaderBranchButton: false,
            showHeaderMergeButton: true,
            showHeaderStashButton: false,
            showHeaderUndoButton: true,
            showHeaderRemoteButton: true,
            showHeaderFinderButton: false,
            showHeaderEditorButton: false,
            showHeaderTerminalButton: true,
            showHeaderSettingsButton: false,
            historyBranchFilter: .branch("origin/feature/login"),
            historyIncludeRemotes: true,
            autoFetchEnabled: true,
            refreshOnAppActive: false
        )

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(
            Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys),
            [
                "schemaVersion",
                "appearance",
                "showToolbarButtonText",
                "showGitFlow",
                "showWorkspaceReflog",
                "showWorkspacePullRequests",
                "showWorkspaceGitLFS",
                "showSubmodules",
                "showSubtrees",
                "showHeaderBranchButton",
                "showHeaderMergeButton",
                "showHeaderStashButton",
                "showHeaderUndoButton",
                "showHeaderRemoteButton",
                "showHeaderFinderButton",
                "showHeaderEditorButton",
                "showHeaderTerminalButton",
                "showHeaderSettingsButton",
                "historyBranchFilter",
                "historyIncludeRemotes",
                "autoFetchEnabled",
                "refreshOnAppActive"
            ]
        )
    }

    func testSnapshotDecodingDefaultsMissingGitFlowVisibilityToTrue() throws {
        let snapshot = AppSettingsSnapshot(
            showToolbarButtonText: true,
            showGitFlow: false,
            showSubmodules: false,
            showSubtrees: false
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "showGitFlow")

        let decoded = try JSONDecoder().decode(
            AppSettingsSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(decoded.showGitFlow)
    }

    func testSnapshotDecodingDefaultsMissingWorkspaceVisibilityToTrue() throws {
        let snapshot = AppSettingsSnapshot(
            showToolbarButtonText: true,
            showWorkspaceReflog: false,
            showWorkspacePullRequests: false,
            showWorkspaceGitLFS: false,
            showSubmodules: false,
            showSubtrees: false
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "showWorkspaceReflog")
        object.removeValue(forKey: "showWorkspacePullRequests")
        object.removeValue(forKey: "showWorkspaceGitLFS")

        let decoded = try JSONDecoder().decode(
            AppSettingsSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(decoded.showWorkspaceReflog)
        XCTAssertTrue(decoded.showWorkspacePullRequests)
        XCTAssertTrue(decoded.showWorkspaceGitLFS)
    }

    func testAppStateApplyChangesOnlyApprovedSettings() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)

        state.apply(
            AppSettingsSnapshot(
                appearance: .dark,
                showToolbarButtonText: false,
                showGitFlow: false,
                showSubmodules: true,
                showSubtrees: true,
                showHeaderBranchButton: true,
                showHeaderMergeButton: true,
                showHeaderStashButton: true,
                showHeaderRemoteButton: true,
                showHeaderFinderButton: true,
                showHeaderTerminalButton: true
            )
        )

        XCTAssertEqual(
            state.snapshot,
            AppSettingsSnapshot(
                appearance: .dark,
                showToolbarButtonText: false,
                showGitFlow: false,
                showSubmodules: true,
                showSubtrees: true,
                showHeaderBranchButton: true,
                showHeaderMergeButton: true,
                showHeaderStashButton: true,
                showHeaderRemoteButton: true,
                showHeaderFinderButton: true,
                showHeaderTerminalButton: true
            )
        )
        XCTAssertEqual(state.appearance, .dark)
        XCTAssertFalse(state.showGitFlow)
        XCTAssertFalse(state.autoFetchEnabled)
        XCTAssertTrue(state.refreshOnAppActive)
    }

    func testSyncEnabledIsDeviceLocalAndPersisted() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertFalse(state.syncEnabled)

        state.syncEnabled = true

        XCTAssertTrue(AppState(userDefaults: defaults).syncEnabled)
        XCTAssertEqual(defaults.object(forKey: "settingsSyncEnabled") as? Bool, true)
    }

    func testGitFlowVisibilityDefaultsOnAndPersistsLocally() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertTrue(state.showGitFlow)

        state.showGitFlow = false

        XCTAssertFalse(AppState(userDefaults: defaults).showGitFlow)
        XCTAssertEqual(defaults.object(forKey: "showGitFlow") as? Bool, false)
    }

    func testWorkspaceVisibilityDefaultsOnAndPersistsLocally() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertTrue(state.showWorkspaceReflog)
        XCTAssertTrue(state.showWorkspacePullRequests)
        XCTAssertTrue(state.showWorkspaceGitLFS)

        state.showWorkspaceReflog = false
        state.showWorkspacePullRequests = false
        state.showWorkspaceGitLFS = false

        let reloaded = AppState(userDefaults: defaults)
        XCTAssertFalse(reloaded.showWorkspaceReflog)
        XCTAssertFalse(reloaded.showWorkspacePullRequests)
        XCTAssertFalse(reloaded.showWorkspaceGitLFS)
        XCTAssertFalse(reloaded.snapshot.showWorkspaceReflog)
        XCTAssertFalse(reloaded.snapshot.showWorkspacePullRequests)
        XCTAssertFalse(reloaded.snapshot.showWorkspaceGitLFS)
    }

    func testSearchFilterIsDeviceLocalAndPersisted() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertEqual(state.searchFilter, .all)

        state.searchFilter = .commit

        XCTAssertEqual(AppState(userDefaults: defaults).searchFilter, .commit)
        XCTAssertEqual(defaults.string(forKey: "searchFilter"), SearchFilter.commit.rawValue)
    }

    func testPreferredSearchFileApplicationIsDeviceLocalAndPersisted() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertNil(state.preferredSearchFileApplicationBundleIdentifier)

        state.preferredSearchFileApplicationBundleIdentifier = "com.microsoft.VSCode"

        XCTAssertEqual(
            AppState(userDefaults: defaults).preferredSearchFileApplicationBundleIdentifier,
            "com.microsoft.VSCode"
        )

        state.preferredSearchFileApplicationBundleIdentifier = nil
        XCTAssertNil(defaults.string(forKey: "preferredSearchFileApplication"))
    }

    func testHeaderButtonVisibilityDefaultsToTrueAndPersists() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertTrue(state.showHeaderBranchButton)
        XCTAssertTrue(state.showHeaderMergeButton)
        XCTAssertTrue(state.showHeaderStashButton)
        XCTAssertFalse(state.showHeaderUndoButton)
        XCTAssertTrue(state.showHeaderRemoteButton)
        XCTAssertTrue(state.showHeaderFinderButton)
        XCTAssertTrue(state.showHeaderEditorButton)
        XCTAssertTrue(state.showHeaderTerminalButton)
        XCTAssertFalse(state.showHeaderSettingsButton)

        state.showHeaderBranchButton = false
        state.showHeaderMergeButton = false
        state.showHeaderStashButton = false
        for shortcut in RepositoryToolbarShortcut.allCases {
            state.setRepositoryToolbarShortcut(shortcut, isPinned: false)
        }

        let reloaded = AppState(userDefaults: defaults)
        XCTAssertFalse(reloaded.showHeaderBranchButton)
        XCTAssertFalse(reloaded.showHeaderMergeButton)
        XCTAssertFalse(reloaded.showHeaderStashButton)
        XCTAssertFalse(reloaded.showHeaderUndoButton)
        XCTAssertFalse(reloaded.showHeaderRemoteButton)
        XCTAssertFalse(reloaded.showHeaderFinderButton)
        XCTAssertFalse(reloaded.showHeaderEditorButton)
        XCTAssertFalse(reloaded.showHeaderTerminalButton)
        XCTAssertFalse(reloaded.showHeaderSettingsButton)
    }

    func testRepositoryToolbarPinsEnforceLimitPersistAndUpdateSnapshot() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertEqual(
            state.pinnedRepositoryToolbarShortcuts,
            [.remote, .finder, .editor, .terminal]
        )
        XCTAssertFalse(state.setRepositoryToolbarShortcut(.undo, isPinned: true))

        XCTAssertTrue(state.setRepositoryToolbarShortcut(.terminal, isPinned: false))
        XCTAssertTrue(state.setRepositoryToolbarShortcut(.undo, isPinned: true))
        XCTAssertEqual(
            state.pinnedRepositoryToolbarShortcuts,
            [.undo, .remote, .finder, .editor]
        )
        XCTAssertTrue(state.snapshot.showHeaderUndoButton)
        XCTAssertFalse(state.snapshot.showHeaderTerminalButton)

        let reloaded = AppState(userDefaults: defaults)
        XCTAssertEqual(reloaded.pinnedRepositoryToolbarShortcuts, state.pinnedRepositoryToolbarShortcuts)
    }

    func testApplyingCloudSnapshotNormalizesRepositoryToolbarPinsToFour() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)

        state.apply(
            AppSettingsSnapshot(
                showToolbarButtonText: true,
                showSubmodules: false,
                showSubtrees: false,
                showHeaderUndoButton: true,
                showHeaderRemoteButton: true,
                showHeaderFinderButton: true,
                showHeaderEditorButton: true,
                showHeaderTerminalButton: true,
                showHeaderSettingsButton: true
            )
        )

        XCTAssertEqual(
            state.pinnedRepositoryToolbarShortcuts,
            [.undo, .remote, .finder, .editor]
        )
        XCTAssertEqual(state.snapshot.pinnedRepositoryToolbarShortcuts.count, 4)
    }

    func testHistoryFilterDefaultsAndPersistence() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertEqual(state.historyBranchFilter, .all)
        XCTAssertFalse(state.historyIncludeRemotes)

        state.historyBranchFilter = .branch("origin/feature/login")
        state.historyIncludeRemotes = true

        let reloaded = AppState(userDefaults: defaults)
        XCTAssertEqual(reloaded.historyBranchFilter, .branch("origin/feature/login"))
        XCTAssertTrue(reloaded.historyIncludeRemotes)
    }

    func testPullFetchDefaultsAndPersistence() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertFalse(state.autoFetchEnabled)
        XCTAssertTrue(state.refreshOnAppActive)

        state.autoFetchEnabled = true
        state.refreshOnAppActive = false

        let reloaded = AppState(userDefaults: defaults)
        XCTAssertTrue(reloaded.autoFetchEnabled)
        XCTAssertFalse(reloaded.refreshOnAppActive)
    }

    func testSettingsSnapshotPublisherDoesNotEmitOnDeviceLocalSettings() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)
        var emissions: [AppSettingsSnapshot] = []
        var cancellables = Set<AnyCancellable>()
        state.settingsSnapshotPublisher
            .sink { emissions.append($0) }
            .store(in: &cancellables)

        // The publisher emits the current snapshot on subscription; device-local settings should not add more.
        state.syncEnabled = true
        state.searchFilter = .commit

        XCTAssertEqual(emissions.count, 1)
    }

    func testSettingsSnapshotPublisherEmitsUpdatedSnapshot() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)
        var emissions: [AppSettingsSnapshot] = []
        var cancellables = Set<AnyCancellable>()
        state.settingsSnapshotPublisher
            .sink { emissions.append($0) }
            .store(in: &cancellables)

        state.autoFetchEnabled = true

        XCTAssertEqual(emissions.count, 2)
        XCTAssertEqual(emissions.last?.autoFetchEnabled, true)
        XCTAssertEqual(AppState(userDefaults: defaults).autoFetchEnabled, true)
    }

    func testApplyEmitsSingleSnapshot() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)
        var emissions: [AppSettingsSnapshot] = []
        var cancellables = Set<AnyCancellable>()
        state.settingsSnapshotPublisher
            .sink { emissions.append($0) }
            .store(in: &cancellables)

        let expected = AppSettingsSnapshot(
            appearance: .light,
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
        state.apply(expected)

        XCTAssertEqual(emissions.count, 2)
        XCTAssertEqual(emissions.last, expected)
    }

    func testRepositoryWindowScreenFitDefaultsOffAndPersistsLocally() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertFalse(state.fitRepositoryWindowsToScreen)
        let cloudSnapshot = state.snapshot

        state.fitRepositoryWindowsToScreen = true

        XCTAssertTrue(AppState(userDefaults: defaults).fitRepositoryWindowsToScreen)
        XCTAssertEqual(state.snapshot, cloudSnapshot)
    }
}
