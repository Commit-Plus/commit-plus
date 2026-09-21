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

final class RepoSettingsStoreTests: XCTestCase {
    func testRepoSettingsDecodesMissingFieldsWithDefaults() throws {
        let data = #"{"defaultRemoteName":"origin","defaultPullBranch":"main"}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RepoSettings.self, from: data)

        XCTAssertEqual(decoded.defaultRemoteName, "origin")
        XCTAssertEqual(decoded.defaultPullBranch, "main")
        XCTAssertEqual(decoded.pullStrategy, .merge)
        XCTAssertNil(decoded.autoFetchOverride)
        XCTAssertNil(decoded.refreshOnAppActiveOverride)
        XCTAssertTrue(decoded.confirmDetachedHeadCheckout)
        XCTAssertTrue(decoded.confirmDestructiveStashActions)
        XCTAssertFalse(decoded.skipProtectedBranchCommitWarnings)
    }

    func testRepoSettingsStorePersistsSettingsPerRepositoryPath() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()

        let store = RepoSettingsStore(dataStore: fixture.store)
        let repoA = "/tmp/repo-a-\(UUID().uuidString)"
        let repoB = "/tmp/repo-b-\(UUID().uuidString)"

        var repoASettings = RepoSettings.defaults(currentBranch: "main", remotes: ["origin"])
        repoASettings.skipProtectedBranchCommitWarnings = true
        repoASettings.pullStrategy = .rebase
        repoASettings.autoFetchOverride = true
        repoASettings.refreshOnAppActiveOverride = false
        try await store.update(for: repoA, settings: repoASettings)

        let freshStore = RepoSettingsStore(dataStore: try await fixture.reopen())
        let loadedA = freshStore.settings(for: repoA, currentBranch: "main", remotes: ["origin"])
        let loadedB = freshStore.settings(for: repoB, currentBranch: nil, remotes: ["upstream"])

        XCTAssertEqual(loadedA, repoASettings)
        XCTAssertTrue(loadedA.skipProtectedBranchCommitWarnings)
        XCTAssertFalse(loadedB.skipProtectedBranchCommitWarnings)
        XCTAssertEqual(loadedB.defaultRemoteName, "upstream")
        XCTAssertEqual(loadedB.defaultPullBranch, "")
        XCTAssertEqual(loadedB.pullStrategy, .merge)
        XCTAssertNil(loadedB.autoFetchOverride)
        XCTAssertNil(loadedB.refreshOnAppActiveOverride)
        XCTAssertTrue(loadedB.confirmDetachedHeadCheckout)
        XCTAssertTrue(loadedB.confirmDestructiveStashActions)
    }

    func testRepoSettingsDecodesLegacyPullFetchValuesAsOverrides() throws {
        let data = """
        {
          "defaultPullBranch": "main",
          "autoFetchEnabled": true,
          "refreshOnAppActive": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RepoSettings.self, from: data)

        XCTAssertEqual(decoded.autoFetchOverride, true)
        XCTAssertEqual(decoded.refreshOnAppActiveOverride, false)
        XCTAssertTrue(decoded.resolvedAutoFetchEnabled(globalValue: false))
        XCTAssertFalse(decoded.resolvedRefreshOnAppActive(globalValue: true))
    }

    func testRepoSettingsWithoutOverridesUsesGlobalValues() {
        let settings = RepoSettings.defaults(currentBranch: "main", remotes: ["origin"])

        XCTAssertTrue(settings.resolvedAutoFetchEnabled(globalValue: true))
        XCTAssertFalse(settings.resolvedRefreshOnAppActive(globalValue: false))
    }
}
