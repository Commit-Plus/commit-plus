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

final class GitProviderSSHKeyStoreTests: XCTestCase {
    func testKeyStoreKeyUsesProviderAccountIdentity() {
        let account = makeProviderAccount()

        XCTAssertEqual(
            GitProviderSSHKeyStoreKey.key(for: account),
            "macgit-user-1:github:github.com:provider-user-42"
        )
    }

    func testSQLiteStoreSavesReadsAndDeletesKey() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()

        let store = SQLiteGitProviderSSHKeyStore(dataStore: fixture.store)
        let account = makeProviderAccount()
        let key = GitProviderSSHKey(path: "/Users/test/.ssh/id_ed25519")

        try await store.saveKey(key, for: account)

        XCTAssertEqual(try store.key(for: account), key)

        try await store.deleteKey(for: account)

        XCTAssertNil(try store.key(for: account))
    }

    func testDeletingMissingKeyIsIdempotent() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()

        let store = SQLiteGitProviderSSHKeyStore(dataStore: fixture.store)

        try await store.deleteKey(for: makeProviderAccount())
    }

    private func makeProviderAccount() -> GitProviderAccount {
        GitProviderAccount(
            id: "connection-1",
            macgitUID: "macgit-user-1",
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: "provider-user-42",
            username: "octocat",
            displayName: nil,
            avatarURL: nil,
            scopes: [],
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )
    }
}
