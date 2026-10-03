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

final class GitProviderTokenVaultTests: XCTestCase {
    func testInMemoryVaultSavesReadsAndDeletesToken() throws {
        let vault = InMemoryGitProviderTokenVault()
        let account = makeAccount()
        let token = GitProviderToken(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            tokenType: "bearer"
        )

        try vault.saveToken(token, for: account)
        XCTAssertEqual(try vault.readToken(for: account), token)

        try vault.deleteToken(for: account)
        XCTAssertNil(try vault.readToken(for: account))
    }

    func testKeychainAccountKeyIncludesMacgitUIDProviderHostAndProviderUserID() {
        let account = makeAccount(
            macgitUID: "macgit-user-1",
            hostURL: URL(string: "https://GitHub.com/path")!,
            providerUserID: "provider-user-42"
        )

        XCTAssertEqual(
            GitProviderTokenVaultKey.key(for: account),
            "macgit-user-1:github:github.com/path:provider-user-42"
        )
    }

    func testMissingTokenReturnsNil() throws {
        let vault = KeychainGitProviderTokenVault()
        let account = makeAccount(
            id: UUID().uuidString,
            macgitUID: UUID().uuidString,
            providerUserID: UUID().uuidString
        )

        XCTAssertNil(try vault.readToken(for: account))
    }

    private func makeAccount(
        id: String = "connection-1",
        macgitUID: String = "macgit-user-1",
        hostURL: URL = URL(string: "https://github.com")!,
        providerUserID: String = "provider-user-42"
    ) -> GitProviderAccount {
        GitProviderAccount(
            id: id,
            macgitUID: macgitUID,
            provider: .github,
            hostURL: hostURL,
            providerUserID: providerUserID,
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

private final class InMemoryGitProviderTokenVault: GitProviderTokenVault {
    private var tokens: [String: GitProviderToken] = [:]

    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? {
        tokens[GitProviderTokenVaultKey.key(for: account)]
    }

    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {
        tokens[GitProviderTokenVaultKey.key(for: account)] = token
    }

    func deleteToken(for account: GitProviderAccount) throws {
        tokens.removeValue(forKey: GitProviderTokenVaultKey.key(for: account))
    }
}
