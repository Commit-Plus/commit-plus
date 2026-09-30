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

final class GitProviderCredentialResolverTests: XCTestCase {
    func testReturnsCredentialForMatchingProviderAccount() async throws {
        let account = makeProviderAccount()
        let resolver = GitProviderCredentialResolver(
            accounts: [account],
            tokenVault: FakeCredentialTokenVault(tokensByAccountID: [account.id: makeToken("secret")])
        )

        let credential = try await resolver.credential(for: "https://github.com/octocat/Hello-World.git")

        XCTAssertEqual(credential, GitCredential(username: "octocat", token: "secret"))
    }

    func testReturnsCredentialForMatchingBitbucketAccount() async throws {
        let account = makeProviderAccount(provider: .bitbucket, username: "Trantienthanh2412")
        let resolver = GitProviderCredentialResolver(
            accounts: [account],
            tokenVault: FakeCredentialTokenVault(tokensByAccountID: [account.id: makeToken("api-token")])
        )

        let credential = try await resolver.credential(
            for: "https://Trantienthanh2412@bitbucket.org/workspace/project.git"
        )

        XCTAssertEqual(credential, GitCredential(username: "Trantienthanh2412", token: "api-token"))
    }

    func testUnsupportedRemoteReturnsNil() async throws {
        let resolver = GitProviderCredentialResolver(
            accounts: [makeProviderAccount()],
            tokenVault: FakeCredentialTokenVault()
        )

        let credential = try await resolver.credential(for: "https://example.com/octocat/Hello-World.git")
        XCTAssertNil(credential)
    }

    func testReturnsSSHCredentialForMatchingSSHRemote() throws {
        let account = makeProviderAccount(transportProtocol: .ssh)
        let resolver = GitProviderCredentialResolver(
            accounts: [account],
            tokenVault: FakeCredentialTokenVault(),
            sshKeyStore: FakeCredentialSSHKeyStore(keysByAccountID: [
                account.id: GitProviderSSHKey(path: "/Users/test/.ssh/id_ed25519")
            ])
        )

        let credential = try resolver.sshCredential(for: "git@github.com:octocat/Hello-World.git")

        XCTAssertEqual(credential, GitSSHCredential(username: "git", keyPath: "/Users/test/.ssh/id_ed25519"))
    }

    func testSSHRemoteWithoutConfiguredKeyThrows() {
        let account = makeProviderAccount(transportProtocol: .ssh)
        let resolver = GitProviderCredentialResolver(
            accounts: [account],
            tokenVault: FakeCredentialTokenVault(),
            sshKeyStore: FakeCredentialSSHKeyStore()
        )

        XCTAssertThrowsError(try resolver.sshCredential(for: "git@github.com:octocat/Hello-World.git")) { error in
            XCTAssertEqual(error as? GitProviderCredentialError, .sshKeyUnavailable(username: "octocat"))
        }
    }

    func testHTTPSRemoteStillReturnsTokenCredential() async throws {
        let account = makeProviderAccount(transportProtocol: .ssh)
        let resolver = GitProviderCredentialResolver(
            accounts: [account],
            tokenVault: FakeCredentialTokenVault(tokensByAccountID: [account.id: makeToken("secret")]),
            sshKeyStore: FakeCredentialSSHKeyStore(keysByAccountID: [
                account.id: GitProviderSSHKey(path: "/Users/test/.ssh/id_ed25519")
            ])
        )

        let credential = try await resolver.credential(for: "https://github.com/octocat/Hello-World.git")

        XCTAssertEqual(credential, GitCredential(username: "octocat", token: "secret"))
    }

    func testNoProviderAccountKeepsExistingBehavior() async throws {
        let resolver = GitProviderCredentialResolver(
            accounts: [],
            tokenVault: FakeCredentialTokenVault()
        )

        let credential = try await resolver.credential(for: "https://github.com/octocat/Hello-World.git")
        XCTAssertNil(credential)
    }

    func testMultipleMatchingAccountsThrows() async {
        let first = makeProviderAccount(id: "connection-1", username: "octocat")
        let second = makeProviderAccount(id: "connection-2", username: "monalisa")
        let resolver = GitProviderCredentialResolver(
            accounts: [first, second],
            tokenVault: FakeCredentialTokenVault()
        )

        do {
            _ = try await resolver.credential(for: "https://github.com/octocat/Hello-World.git")
            XCTFail("Expected multiple matching accounts to throw")
        } catch {
            XCTAssertEqual(error as? GitProviderCredentialError, .multipleMatchingAccounts(host: "github.com"))
        }
    }

    func testSavedRemotePreferenceChoosesMatchingAccount() async throws {
        let first = makeProviderAccount(id: "connection-1", username: "octocat")
        let second = makeProviderAccount(id: "connection-2", username: "monalisa")
        let remoteURL = "https://github.com/octocat/Hello-World.git"
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(from: remoteURL))
        let resolver = GitProviderCredentialResolver(
            accounts: [first, second],
            tokenVault: FakeCredentialTokenVault(tokensByAccountID: [
                first.id: makeToken("first-token"),
                second.id: makeToken("second-token"),
            ]),
            preferredAccountIDsByRemoteIdentity: [
                GitProviderAccountPreferenceKey.make(for: identity): second.id,
            ]
        )

        let credential = try await resolver.credential(for: remoteURL)

        XCTAssertEqual(credential, GitCredential(username: "monalisa", token: "second-token"))
    }

    func testMissingTokenReturnsUserFacingAuthenticationError() async {
        let account = makeProviderAccount()
        let resolver = GitProviderCredentialResolver(
            accounts: [account],
            tokenVault: FakeCredentialTokenVault()
        )

        do {
            _ = try await resolver.credential(for: "https://github.com/octocat/Hello-World.git")
            XCTFail("Expected missing token to throw")
        } catch {
            XCTAssertEqual(error as? GitProviderCredentialError, .tokenUnavailable(username: "octocat"))
        }
    }

    private func makeProviderAccount(
        id: String = "connection-1",
        provider: GitProviderKind = .github,
        username: String = "octocat",
        transportProtocol: GitProviderTransportProtocol = .https
    ) -> GitProviderAccount {
        GitProviderAccount(
            id: id,
            macgitUID: "macgit-user-1",
            provider: provider,
            hostURL: provider == .bitbucket
                ? URL(string: "https://bitbucket.org")!
                : URL(string: "https://github.com")!,
            providerUserID: id,
            username: username,
            displayName: nil,
            avatarURL: nil,
            scopes: [],
            permissions: [:],
            tokenStatus: .valid,
            transportProtocol: transportProtocol,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )
    }

    private func makeToken(_ accessToken: String) -> GitProviderToken {
        GitProviderToken(accessToken: accessToken, refreshToken: nil, expiresAt: nil, tokenType: "bearer")
    }
}

private final class FakeCredentialTokenVault: GitProviderTokenVault {
    private var tokensByAccountID: [String: GitProviderToken]

    init(tokensByAccountID: [String: GitProviderToken] = [:]) {
        self.tokensByAccountID = tokensByAccountID
    }

    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? {
        tokensByAccountID[account.id]
    }

    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {
        tokensByAccountID[account.id] = token
    }

    func deleteToken(for account: GitProviderAccount) throws {
        tokensByAccountID[account.id] = nil
    }
}

private final class FakeCredentialSSHKeyStore: GitProviderSSHKeyStore {
    private var keysByAccountID: [String: GitProviderSSHKey]

    init(keysByAccountID: [String: GitProviderSSHKey] = [:]) {
        self.keysByAccountID = keysByAccountID
    }

    func key(for account: GitProviderAccount) throws -> GitProviderSSHKey? {
        keysByAccountID[account.id]
    }

    func saveKey(_ key: GitProviderSSHKey, for account: GitProviderAccount) throws {
        keysByAccountID[account.id] = key
    }

    func deleteKey(for account: GitProviderAccount) throws {
        keysByAccountID[account.id] = nil
    }
}
