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
final class GitProviderAccountControllerTests: XCTestCase {
    func testFreeUserCannotConnectFirstSelfManagedAccountUsingPAT() async {
        let controller = GitProviderAccountController(store: FakeGitProviderAccountStore(), tokenVault: FakeGitProviderTokenVault())
        await controller.connectPersonalAccessToken(host: GitProviderHost(kind: .github, baseURL: URL(string: "https://source.company.test")!), accessToken: "test-token")
        XCTAssertFalse(controller.canConnectSelfHosted)
        XCTAssertTrue(controller.accounts.isEmpty)
        XCTAssertEqual(controller.errorMessage, GitProviderAccountAccessError.selfHostedRequiresPro.localizedDescription)
    }

    func testFreeUserCannotConnectSelfManagedGitLabUsingOAuth() async {
        let controller = GitProviderAccountController(store: FakeGitProviderAccountStore(), tokenVault: FakeGitProviderTokenVault())
        await controller.connectSelfHostedGitLab(hostURL: URL(string: "https://source.company.test")!)
        XCTAssertEqual(controller.errorMessage, GitProviderAccountAccessError.selfHostedRequiresPro.localizedDescription)
    }

    func testFreeUserCannotConnectSelfManagedSSHBeforeAuthentication() async {
        let ssh = FakeGitProviderSSHAuthService(username: "user")
        let controller = GitProviderAccountController(store: FakeGitProviderAccountStore(), tokenVault: FakeGitProviderTokenVault(), sshAuthService: ssh)
        await controller.connectSSH(host: GitProviderHost(kind: .gitlab, baseURL: URL(string: "https://source.company.test")!), key: GitProviderSSHKey(path: "/test/key"))
        XCTAssertTrue(ssh.requests.isEmpty)
        XCTAssertEqual(controller.errorMessage, GitProviderAccountAccessError.selfHostedRequiresPro.localizedDescription)
    }

    func testProUserCanConnectSelfManagedSSH() async {
        let ssh = FakeGitProviderSSHAuthService(username: "user")
        let controller = GitProviderAccountController(store: FakeGitProviderAccountStore(), tokenVault: FakeGitProviderTokenVault(), sshKeyStore: FakeGitProviderSSHKeyStore(), sshAuthService: ssh, hasProAccess: { true })
        await controller.connectSSH(host: GitProviderHost(kind: .gitlab, baseURL: URL(string: "https://source.company.test")!), key: GitProviderSSHKey(path: "/test/key"))
        XCTAssertEqual(ssh.requests.count, 1)
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.accounts.count, 1)
    }

    func testSelfManagedAccessTracksCurrentProEntitlement() {
        var hasPro = true
        let controller = GitProviderAccountController(store: FakeGitProviderAccountStore(), tokenVault: FakeGitProviderTokenVault(), hasProAccess: { hasPro })
        XCTAssertTrue(controller.canConnectSelfHosted)
        hasPro = false
        XCTAssertFalse(controller.canConnectSelfHosted)
    }


    func testSignedOutStateLoadsLocalProviderAccounts() async {
        let account = makeProviderAccount(macgitUID: "local-owner")
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [
            account.id: GitProviderToken(accessToken: "token", refreshToken: nil, tokenType: "bearer")
        ])
        let store = FakeGitProviderAccountStore(localAccounts: [account])
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: vault
        )

        await controller.updateMacgitAccount(nil)

        XCTAssertEqual(store.cloudUIDUpdates, [nil])
        XCTAssertEqual(controller.accounts, [account])
    }

    func testSignedInStateLoadsAccountsForCurrentMacgitUID() async {
        let account = makeProviderAccount(macgitUID: "macgit-user-1")
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [
            account.id: GitProviderToken(
                accessToken: "token",
                refreshToken: nil,
                expiresAt: nil,
                tokenType: "bearer"
            )
        ])
        let controller = GitProviderAccountController(store: store, tokenVault: vault)

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        XCTAssertEqual(store.cloudUIDUpdates, ["macgit-user-1"])
        XCTAssertEqual(controller.accounts, [account])
    }

    func testAccountWithoutLocalTokenIsMarkedUnavailableOnThisDevice() async {
        let account = makeProviderAccount(macgitUID: "macgit-user-1", tokenStatus: .valid)
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: FakeGitProviderTokenVault()
        )

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        XCTAssertEqual(controller.accounts.first?.tokenStatus, .unavailableOnThisDevice)
    }

    func testSSHAccountWithoutLocalTokenStaysAvailableWhenKeyExists() async {
        let account = makeProviderAccount(macgitUID: "macgit-user-1", tokenStatus: .valid, transportProtocol: .ssh)
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let sshKeyStore = FakeGitProviderSSHKeyStore(keysByAccountID: [
            account.id: GitProviderSSHKey(path: "/Users/test/.ssh/id_ed25519")
        ])
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: FakeGitProviderTokenVault(),
            sshKeyStore: sshKeyStore
        )

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        XCTAssertEqual(controller.accounts.first?.tokenStatus, .valid)
    }

    func testLegacyGitLabOAuthAccountRequiresReauthorizationForPushScope() async {
        let account = makeProviderAccount(macgitUID: "macgit-user-1", provider: .gitlab)
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [
            account.id: GitProviderToken(
                accessToken: "token",
                refreshToken: "refresh-token",
                expiresAt: .now.addingTimeInterval(7_200),
                tokenType: "Bearer"
            )
        ])
        let controller = GitProviderAccountController(store: store, tokenVault: vault)

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        XCTAssertEqual(controller.accounts.first?.tokenStatus, .reauthorizationRequired)
    }

    func testExpiredGitLabOAuthTokenRefreshesBeforeHTTPSCredentialUse() async throws {
        let account = makeProviderAccount(
            macgitUID: "macgit-user-1",
            provider: .gitlab,
            scopes: ["api", "read_user", "write_repository"]
        )
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [
            account.id: GitProviderToken(
                accessToken: "expired-token",
                refreshToken: "refresh-token",
                expiresAt: .now.addingTimeInterval(-60),
                tokenType: "Bearer"
            )
        ])
        let authService = FakeGitLabProviderAuthService(account: account)
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: vault,
            gitLabAuthService: authService
        )
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        let credential = try await controller.credentialResolver().credential(
            for: "https://gitlab.com/group/project.git"
        )

        XCTAssertEqual(credential?.token, "refreshed-gitlab-token")
        XCTAssertEqual(authService.refreshTokens, ["refresh-token"])
        XCTAssertEqual(try vault.readToken(for: account)?.refreshToken, "rotated-refresh-token")
    }

    func testDisconnectDeletesLocalTokenBeforeMetadata() async {
        let events = EventRecorder()
        let account = makeProviderAccount(macgitUID: "macgit-user-1")
        let store = FakeGitProviderAccountStore(
            accountsByUID: ["macgit-user-1": [account]],
            events: events
        )
        let vault = FakeGitProviderTokenVault(events: events)
        let sshKeyStore = FakeGitProviderSSHKeyStore(events: events)
        let controller = GitProviderAccountController(store: store, tokenVault: vault, sshKeyStore: sshKeyStore)
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))
        events.values.removeAll()

        await controller.disconnect(account)

        XCTAssertEqual(events.values, ["delete-token", "delete-ssh-key", "delete-metadata"])
        XCTAssertEqual(controller.accounts, [])
    }

    func testControllerSavesSSHTransportAndKeyReference() async throws {
        let account = makeProviderAccount(macgitUID: "macgit-user-1")
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [
            account.id: GitProviderToken(
                accessToken: "token",
                refreshToken: nil,
                expiresAt: nil,
                tokenType: "bearer"
            )
        ])
        let sshKeyStore = FakeGitProviderSSHKeyStore()
        let controller = GitProviderAccountController(store: store, tokenVault: vault, sshKeyStore: sshKeyStore)
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        await controller.saveConnectionSettings(
            account: account,
            transportProtocol: .ssh,
            sshKey: GitProviderSSHKey(path: "/Users/test/.ssh/id_ed25519")
        )

        XCTAssertEqual(controller.accounts.first?.transportProtocol, .ssh)
        XCTAssertEqual(try sshKeyStore.key(for: account), GitProviderSSHKey(path: "/Users/test/.ssh/id_ed25519"))
    }

    func testConnectGitHubRequestsDeviceCodeAndOpensVerificationURL() async throws {
        let authService = FakeGitProviderAuthService(
            account: makeProviderAccount(macgitUID: "macgit-user-1"),
            devicePollInterval: 5
        )
        var openedURLs: [URL] = []
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: FakeGitProviderTokenVault(),
            authService: authService,
            configuration: makeConfiguration(),
            openURL: { url in
                openedURLs.append(url)
                return true
            }
        )
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        let connectionTask = Task {
            await controller.connectGitHub()
        }
        await Task.yield()

        XCTAssertEqual(openedURLs, [try XCTUnwrap(URL(string: "https://github.com/login/device"))])
        XCTAssertEqual(controller.pendingDeviceAuthorization?.userCode, "ABCD-EFGH")
        connectionTask.cancel()
        await connectionTask.value
    }

    func testCancellingDeviceAuthorizationClearsLoadingStateWithoutError() async {
        let authService = FakeGitProviderAuthService(
            account: makeProviderAccount(macgitUID: "macgit-user-1"),
            devicePollInterval: 30
        )
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: FakeGitProviderTokenVault(),
            authService: authService,
            configuration: makeConfiguration(),
            openURL: { _ in true }
        )
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        let connectionTask = Task {
            await controller.connectGitHub()
        }
        while controller.pendingDeviceAuthorization == nil {
            await Task.yield()
        }

        connectionTask.cancel()
        await connectionTask.value

        XCTAssertFalse(controller.isLoading)
        XCTAssertNil(controller.pendingDeviceAuthorization)
        XCTAssertNil(controller.errorMessage)
    }

    func testDeviceAuthorizationSavesTokenBeforeMetadataAndPublishesAccount() async throws {
        let events = EventRecorder()
        let providerAccount = makeProviderAccount(macgitUID: "macgit-user-1")
        let authService = FakeGitProviderAuthService(account: providerAccount)
        let store = FakeGitProviderAccountStore(events: events)
        let vault = FakeGitProviderTokenVault(events: events)
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: vault,
            authService: authService,
            configuration: makeConfiguration(),
            openURL: { _ in true }
        )
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))
        events.values.removeAll()

        await controller.connectGitHub()

        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertEqual(controller.accounts, [providerAccount])
        XCTAssertNil(controller.pendingDeviceAuthorization)
    }

    func testConnectGitLabDotComRequestsDeviceCodeAndOpensVerificationURL() async throws {
        let gitLabAuthService = FakeGitLabProviderAuthService(
            account: makeProviderAccount(macgitUID: "macgit-user-1", provider: .gitlab),
            devicePollInterval: 5
        )
        var openedURLs: [URL] = []
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: FakeGitProviderTokenVault(),
            gitLabAuthService: gitLabAuthService,
            openURL: { url in
                openedURLs.append(url)
                return true
            }
        )
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        let connectionTask = Task {
            await controller.connectGitLabDotCom()
        }
        await Task.yield()

        XCTAssertEqual(openedURLs, [try XCTUnwrap(URL(string: "https://gitlab.com/oauth/device?user_code=GITLAB-CODE"))])
        XCTAssertEqual(controller.pendingDeviceAuthorization?.provider, .gitlab)
        XCTAssertEqual(controller.pendingDeviceAuthorization?.userCode, "GITLAB-CODE")
        XCTAssertTrue(gitLabAuthService.deviceAuthorizationHosts.contains(.gitlabDotCom))
        connectionTask.cancel()
        await connectionTask.value
    }

    func testGitLabConnectWithoutConfigurationPublishesGitLabSpecificError() async {
        var openedURLs: [URL] = []
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: FakeGitProviderTokenVault(),
            openURL: { url in
                openedURLs.append(url)
                return true
            }
        )
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        await controller.connectGitLabDotCom()

        XCTAssertEqual(controller.errorMessage, "GitLab account connection is not configured.")
        XCTAssertTrue(openedURLs.isEmpty)
    }

    func testGitLabDeviceAuthorizationSavesTokenBeforeMetadataAndPublishesAccount() async throws {
        let events = EventRecorder()
        let providerAccount = makeProviderAccount(macgitUID: "macgit-user-1", provider: .gitlab)
        let gitLabAuthService = FakeGitLabProviderAuthService(account: providerAccount)
        let store = FakeGitProviderAccountStore(events: events)
        let vault = FakeGitProviderTokenVault(events: events)
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: vault,
            gitLabAuthService: gitLabAuthService,
            openURL: { _ in true }
        )
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))
        events.values.removeAll()

        await controller.connectGitLabDotCom()

        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertEqual(controller.accounts, [providerAccount])
    }

    func testConnectBitbucketStoresAPITokenBeforeMetadataAndPublishesAccount() async throws {
        let events = EventRecorder()
        let store = FakeGitProviderAccountStore(events: events)
        let vault = FakeGitProviderTokenVault(events: events)
        let controller = GitProviderAccountController(store: store, tokenVault: vault)
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))
        events.values.removeAll()

        await controller.connectBitbucket(
            username: "Trantienthanh2412",
            apiToken: "bitbucket-api-token"
        )

        let account = try XCTUnwrap(controller.accounts.first)
        XCTAssertEqual(account.provider, .bitbucket)
        XCTAssertEqual(account.hostURL, GitProviderHost.bitbucketDotOrg.baseURL)
        XCTAssertEqual(account.username, "Trantienthanh2412")
        XCTAssertEqual(account.transportProtocol, .https)
        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        let credential = try await controller.credentialResolver().credential(
            for: "https://Trantienthanh2412@bitbucket.org/workspace/project.git"
        )
        XCTAssertEqual(
            credential,
            GitCredential(username: "Trantienthanh2412", token: "bitbucket-api-token")
        )
    }

    func testConnectBitbucketRejectsEmptyTokenWithoutSavingAccount() async {
        let events = EventRecorder()
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(events: events),
            tokenVault: FakeGitProviderTokenVault(events: events)
        )

        await controller.connectBitbucket(username: "Trantienthanh2412", apiToken: "  ")

        XCTAssertEqual(controller.errorMessage, "Enter a Bitbucket API token.")
        XCTAssertTrue(controller.accounts.isEmpty)
        XCTAssertTrue(events.values.isEmpty)
    }

    func testConnectSSHCreatesProviderAccountAndStoresKey() async throws {
        let events = EventRecorder()
        let store = FakeGitProviderAccountStore(events: events)
        let sshKeyStore = FakeGitProviderSSHKeyStore()
        let sshAuthService = FakeGitProviderSSHAuthService(username: "octocat")
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: FakeGitProviderTokenVault(),
            sshKeyStore: sshKeyStore,
            sshAuthService: sshAuthService
        )
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        await controller.connectSSH(
            host: .githubDotCom,
            key: GitProviderSSHKey(path: "/Users/test/.ssh/id_ed25519")
        )

        let account = try XCTUnwrap(controller.accounts.first)
        XCTAssertEqual(account.username, "octocat")
        XCTAssertEqual(account.providerUserID, "octocat")
        XCTAssertEqual(account.transportProtocol, .ssh)
        XCTAssertEqual(account.hostURL, GitProviderHost.githubDotCom.baseURL)
        XCTAssertEqual(try sshKeyStore.key(for: account), GitProviderSSHKey(path: "/Users/test/.ssh/id_ed25519"))
        XCTAssertEqual(events.values, ["save-metadata"])
        XCTAssertEqual(sshAuthService.requests, [
            GitProviderSSHAuthRequest(host: .githubDotCom, keyPath: "/Users/test/.ssh/id_ed25519")
        ])
    }

    func testFreePlanBlocksSecondAccountBeforeAuthentication() async {
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let authService = FakeGitProviderAuthService(
            account: makeProviderAccount(
                macgitUID: "local-owner",
                id: "connection-2",
                providerUserID: "provider-user-84"
            )
        )
        var openedURLs: [URL] = []
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount]),
            tokenVault: FakeGitProviderTokenVault(),
            authService: authService,
            configuration: makeConfiguration(),
            openURL: {
                openedURLs.append($0)
                return true
            },
            multipleAccountAccess: { .denied(.requiresPro) }
        )
        await controller.updateMacgitAccount(nil)

        await controller.connectGitHub()

        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertEqual(
            controller.errorMessage,
            "Free plan includes 1 Git provider account. Upgrade to Pro to add more."
        )
        XCTAssertEqual(controller.accounts.map(\.id), [existingAccount.id])
    }

    func testProAccessAllowsSecondAccount() async {
        let events = EventRecorder()
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let newAccount = makeProviderAccount(
            macgitUID: "local-owner",
            id: "connection-2",
            providerUserID: "provider-user-84"
        )
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount], events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            authService: FakeGitProviderAuthService(account: newAccount),
            configuration: makeConfiguration(),
            openURL: { _ in true },
            multipleAccountAccess: { .allowed }
        )
        await controller.updateMacgitAccount(nil)

        await controller.connectGitHub()

        XCTAssertEqual(Set(controller.accounts.map(\.id)), Set([existingAccount.id, newAccount.id]))
        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
    }

    func testQuotaIsRecheckedBeforeAuthorizedAccountPersistence() async {
        let events = EventRecorder()
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let newAccount = makeProviderAccount(
            macgitUID: "local-owner",
            id: "connection-2",
            providerUserID: "provider-user-84"
        )
        var accessDecisions: [FeatureAccessDecision] = [.allowed, .denied(.requiresPro)]
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount], events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            authService: FakeGitProviderAuthService(account: newAccount),
            configuration: makeConfiguration(),
            openURL: { _ in true },
            multipleAccountAccess: { accessDecisions.removeFirst() }
        )
        await controller.updateMacgitAccount(nil)

        await controller.connectGitHub()

        XCTAssertEqual(controller.accounts.map(\.id), [existingAccount.id])
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertEqual(
            controller.errorMessage,
            "Free plan includes 1 Git provider account. Upgrade to Pro to add more."
        )
    }

    func testReconnectExistingIdentityRemainsAllowedAtFreeLimit() async {
        let events = EventRecorder()
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount], events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            authService: FakeGitProviderAuthService(account: existingAccount),
            configuration: makeConfiguration(),
            openURL: { _ in true },
            multipleAccountAccess: { .denied(.requiresPro) }
        )
        await controller.updateMacgitAccount(nil)

        await controller.reconnect(existingAccount)

        XCTAssertEqual(controller.accounts.map(\.id), [existingAccount.id])
        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertNil(controller.errorMessage)
    }

    func testFreePlanBlocksSSHBeforeAuthentication() async {
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let sshAuthService = FakeGitProviderSSHAuthService(username: "another-user")
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount]),
            tokenVault: FakeGitProviderTokenVault(),
            sshAuthService: sshAuthService,
            multipleAccountAccess: { .denied(.requiresPro) }
        )
        await controller.updateMacgitAccount(nil)

        await controller.connectSSH(
            host: .githubDotCom,
            key: GitProviderSSHKey(path: "/Users/test/.ssh/id_ed25519")
        )

        XCTAssertTrue(sshAuthService.requests.isEmpty)
        XCTAssertEqual(controller.accounts.map(\.id), [existingAccount.id])
    }

    private func makeMacgitAccount(uid: String) -> AccountSnapshot {
        AccountSnapshot(uid: uid, email: nil, displayName: nil, providerIDs: ["password"])
    }

    private func makeProviderAccount(
        macgitUID: String,
        id: String = "connection-1",
        provider: GitProviderKind = .github,
        providerUserID: String = "provider-user-42",
        tokenStatus: GitProviderTokenStatus = .valid,
        transportProtocol: GitProviderTransportProtocol = .https,
        scopes: [String] = []
    ) -> GitProviderAccount {
        GitProviderAccount(
            id: id,
            macgitUID: macgitUID,
            provider: provider,
            hostURL: hostURL(for: provider),
            providerUserID: providerUserID,
            username: username(for: provider),
            displayName: nil,
            avatarURL: nil,
            scopes: scopes,
            permissions: [:],
            tokenStatus: tokenStatus,
            transportProtocol: transportProtocol,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )
    }

    private func hostURL(for provider: GitProviderKind) -> URL {
        switch provider {
        case .github: URL(string: "https://github.com")!
        case .gitlab: URL(string: "https://gitlab.com")!
        case .bitbucket: URL(string: "https://bitbucket.org")!
        }
    }

    private func username(for provider: GitProviderKind) -> String {
        switch provider {
        case .github: "octocat"
        case .gitlab: "tanuki"
        case .bitbucket: "Trantienthanh2412"
        }
    }

    private func makeConfiguration() -> GitHubProviderAuthConfiguration {
        GitHubProviderAuthConfiguration(
            clientID: "github-client-id",
            scopes: ["repo", "read:user"]
        )
    }
}

@MainActor
private final class FakeGitLabProviderAuthService: GitLabProviderOAuthAuthenticating {
    private let account: GitProviderAccount
    private let devicePollInterval: Int
    private(set) var deviceAuthorizationHosts: [GitProviderHost] = []
    private(set) var refreshTokens: [String] = []

    init(account: GitProviderAccount, devicePollInterval: Int = 0) {
        self.account = account
        self.devicePollInterval = devicePollInterval
    }

    func requestDeviceAuthorization(host: GitProviderHost) async throws -> GitProviderDeviceAuthorization {
        deviceAuthorizationHosts.append(host.normalized)
        return GitProviderDeviceAuthorization(
            provider: .gitlab,
            deviceCode: "gitlab-device-code",
            userCode: "GITLAB-CODE",
            verificationURI: host.normalized.baseURL
                .appendingPathComponent("oauth")
                .appendingPathComponent("device")
                .appending(queryItems: [URLQueryItem(name: "user_code", value: "GITLAB-CODE")]),
            expiresIn: 300,
            interval: devicePollInterval
        )
    }

    func pollDeviceAuthorization(
        _ authorization: GitProviderDeviceAuthorization,
        host: GitProviderHost
    ) async throws -> GitProviderToken {
        GitProviderToken(
            accessToken: "gitlab-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "Bearer"
        )
    }

    func authorizationURL(for session: GitProviderOAuthSession) throws -> URL {
        session.host.normalized.baseURL
            .appendingPathComponent("oauth")
            .appendingPathComponent("authorize")
    }

    func exchangeCallback(
        _ callback: GitProviderOAuthCallback,
        session: GitProviderOAuthSession
    ) async throws -> GitProviderToken {
        GitProviderToken(
            accessToken: "gitlab-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "Bearer"
        )
    }

    func refreshToken(
        _ refreshToken: String,
        host: GitProviderHost
    ) async throws -> GitProviderToken {
        refreshTokens.append(refreshToken)
        return GitProviderToken(
            accessToken: "refreshed-gitlab-token",
            refreshToken: "rotated-refresh-token",
            expiresAt: .now.addingTimeInterval(7_200),
            tokenType: "Bearer"
        )
    }

    func fetchAccount(
        token: GitProviderToken,
        macgitUID: String,
        host: GitProviderHost
    ) async throws -> GitProviderAccount {
        account
    }
}

@MainActor
private final class FakeGitProviderAccountStore: GitProviderAccountStore {
    let accountOwnerID: String
    private(set) var cloudUIDUpdates: [String?] = []
    private var localAccounts: [GitProviderAccount]
    private var accountsByUID: [String: [GitProviderAccount]]
    private let events: EventRecorder?

    init(
        accountOwnerID: String = "local-owner",
        localAccounts: [GitProviderAccount] = [],
        accountsByUID: [String: [GitProviderAccount]] = [:],
        events: EventRecorder? = nil
    ) {
        self.accountOwnerID = accountOwnerID
        self.localAccounts = localAccounts
        self.accountsByUID = accountsByUID
        self.events = events
    }

    func accounts() async throws -> [GitProviderAccount] {
        localAccounts
    }

    func updateCloudAccount(uid: String?) async throws {
        cloudUIDUpdates.append(uid)
        guard let uid else { return }
        for account in accountsByUID[uid] ?? [] where !localAccounts.contains(where: { $0.id == account.id }) {
            localAccounts.append(account)
        }
    }

    func save(_ account: GitProviderAccount) async throws {
        events?.values.append("save-metadata")
        localAccounts.removeAll { $0.id == account.id }
        localAccounts.append(account)
    }

    func delete(accountID: String) async throws {
        events?.values.append("delete-metadata")
        localAccounts.removeAll { $0.id == accountID }
    }
}

@MainActor
private final class FakeGitProviderTokenVault: GitProviderTokenVault {
    private var tokensByAccountID: [String: GitProviderToken]
    private let events: EventRecorder?

    init(
        tokensByAccountID: [String: GitProviderToken] = [:],
        events: EventRecorder? = nil
    ) {
        self.tokensByAccountID = tokensByAccountID
        self.events = events
    }

    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? {
        tokensByAccountID[account.id]
    }

    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {
        events?.values.append("save-token")
        tokensByAccountID[account.id] = token
    }

    func deleteToken(for account: GitProviderAccount) throws {
        events?.values.append("delete-token")
        tokensByAccountID.removeValue(forKey: account.id)
    }
}

@MainActor
private final class FakeGitProviderSSHKeyStore: GitProviderSSHKeyStore {
    private var keysByAccountID: [String: GitProviderSSHKey]
    private let events: EventRecorder?

    init(
        keysByAccountID: [String: GitProviderSSHKey] = [:],
        events: EventRecorder? = nil
    ) {
        self.keysByAccountID = keysByAccountID
        self.events = events
    }

    func key(for account: GitProviderAccount) throws -> GitProviderSSHKey? {
        keysByAccountID[account.id]
    }

    func saveKey(_ key: GitProviderSSHKey, for account: GitProviderAccount) throws {
        keysByAccountID[account.id] = key
    }

    func deleteKey(for account: GitProviderAccount) throws {
        events?.values.append("delete-ssh-key")
        keysByAccountID.removeValue(forKey: account.id)
    }
}

@MainActor
private final class FakeGitProviderSSHAuthService: GitProviderSSHAuthenticating {
    private let username: String
    private(set) var requests: [GitProviderSSHAuthRequest] = []

    init(username: String) {
        self.username = username
    }

    func authenticate(host: GitProviderHost, keyPath: String) async throws -> GitProviderSSHAuthentication {
        requests.append(GitProviderSSHAuthRequest(host: host, keyPath: keyPath))
        return GitProviderSSHAuthentication(username: username)
    }
}

@MainActor
private final class EventRecorder {
    var values: [String] = []
}

@MainActor
private final class FakeGitProviderAuthService: GitProviderAuthenticating {
    private let account: GitProviderAccount
    private let devicePollInterval: Int

    init(account: GitProviderAccount, devicePollInterval: Int = 0) {
        self.account = account
        self.devicePollInterval = devicePollInterval
    }

    func requestDeviceAuthorization() async throws -> GitProviderDeviceAuthorization {
        GitProviderDeviceAuthorization(
            deviceCode: "device-code",
            userCode: "ABCD-EFGH",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 900,
            interval: devicePollInterval
        )
    }

    func pollDeviceAuthorization(_ authorization: GitProviderDeviceAuthorization) async throws -> GitProviderToken {
        GitProviderToken(
            accessToken: "secret-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "bearer"
        )
    }

    func fetchAccount(
        token: GitProviderToken,
        macgitUID: String,
        host: GitProviderHost
    ) async throws -> GitProviderAccount {
        account
    }
}
