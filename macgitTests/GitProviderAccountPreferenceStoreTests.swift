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

final class GitProviderAccountPreferenceStoreTests: XCTestCase {
    func testPersistsAccountPreferenceForCanonicalRemoteIdentity() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()

        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "git@github.com:octocat/Hello-World.git"
        ))
        let store = GitProviderAccountPreferenceStore(dataStore: fixture.store)

        try await store.update(accountID: "connection-work", for: identity)

        let reloadedStore = GitProviderAccountPreferenceStore(dataStore: try await fixture.reopen())
        XCTAssertEqual(reloadedStore.accountID(for: identity), "connection-work")
    }

    func testRemovingPreferencePersistsAutomaticSelection() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()

        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://gitlab.com/group/project.git"
        ))
        let store = GitProviderAccountPreferenceStore(dataStore: fixture.store)
        try await store.update(accountID: "connection-work", for: identity)

        try await store.update(accountID: nil, for: identity)

        XCTAssertNil(store.accountID(for: identity))
        XCTAssertTrue(store.preferences.isEmpty)
    }
}
