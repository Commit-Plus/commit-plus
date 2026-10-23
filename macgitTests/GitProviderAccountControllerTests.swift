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

        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

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

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

        XCTAssertEqual(store.cloudUIDUpdates, ["macgit-user-1"])
        XCTAssertEqual(controller.accounts, [account])
    }

    func testSignedInStateWithCloudSyncOffKeepsProviderAccountsLocal() async {
        let account = makeProviderAccount(macgitUID: "local-owner")
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [
            account.id: GitProviderToken(accessToken: "token", refreshToken: nil, tokenType: "bearer")
        ])
        let store = FakeGitProviderAccountStore(localAccounts: [account])
        let controller = GitProviderAccountController(store: store, tokenVault: vault)

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: false)

        XCTAssertEqual(store.cloudUIDUpdates, [nil])
        XCTAssertEqual(controller.accounts, [account])
    }

    func testAccountWithoutLocalTokenIsMarkedUnavailableOnThisDevice() async {
        let account = makeProviderAccount(macgitUID: "macgit-user-1", tokenStatus: .valid)
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: FakeGitProviderTokenVault()
        )

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

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

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

        XCTAssertEqual(controller.accounts.first?.tokenStatus, .valid)
    }

    func testGitLabPersonalAccessTokenRemainsValidAfterReload() async {
        var account = makeProviderAccount(macgitUID: "macgit-user-1", provider: .gitlab)
        account.permissions["authentication"] = "personalAccessToken"
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [
            account.id: GitProviderToken(accessToken: "token", tokenType: "Bearer")
        ])
        let controller = GitProviderAccountController(store: store, tokenVault: vault)

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

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

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)
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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

        let connectionTask = Task {
            await controller.connectGitHubWithDeviceCode()
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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

        let connectionTask = Task {
            await controller.connectGitHubWithDeviceCode()
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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)
        events.values.removeAll()

        await controller.connectGitHubWithDeviceCode()

        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertEqual(controller.accounts, [providerAccount])
        XCTAssertNil(controller.pendingDeviceAuthorization)
    }

    func testGitLabDeviceCodeFallbackRequestsDeviceCodeAndOpensVerificationURL() async throws {
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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

        let connectionTask = Task {
            await controller.connectGitLabWithDeviceCode()
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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)
        events.values.removeAll()

        await controller.connectGitLabWithDeviceCode()

        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertEqual(controller.accounts, [providerAccount])
    }

    func testConnectBitbucketStoresAPITokenBeforeMetadataAndPublishesAccount() async throws {
        let events = EventRecorder()
        let store = FakeGitProviderAccountStore(events: events)
        let vault = FakeGitProviderTokenVault(events: events)
        let controller = GitProviderAccountController(store: store, tokenVault: vault)
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)
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

    func testConnectAzureDevOpsValidatesTokenAndSuppliesOrganizationCredential() async throws {
        let events = EventRecorder()
        let client = AzureConnectionHTTPClient(userIDs: ["azure-user-1"])
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            azureDevOpsAuthService: AzureDevOpsProviderAuthService(httpClient: client)
        )

        await controller.connectAzureDevOps(
            organization: "https://dev.azure.com/Trantienthanh1998/ChatApp",
            accessToken: " azure-pat "
        )

        XCTAssertNil(controller.errorMessage)
        let account = try XCTUnwrap(controller.accounts.first)
        XCTAssertEqual(account.provider, .azureDevOps)
        XCTAssertEqual(account.hostURL.absoluteString, "https://dev.azure.com/trantienthanh1998")
        XCTAssertEqual(account.username, "azure-user-1@example.com")
        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertEqual(client.requests.first?.url?.absoluteString, "https://dev.azure.com/trantienthanh1998/_apis/connectionData")

        let resolver = controller.credentialResolver()
        let expected = GitCredential(username: "azure-user-1@example.com", token: "azure-pat")
        for remote in [
            "https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp",
            "https://dev.azure.com/trantienthanh1998/Other%20Project/_git/Other",
            "https://trantienthanh1998.visualstudio.com/DefaultCollection/ChatApp/_git/ChatApp",
        ] {
            let credential = try await resolver.credential(for: remote)
            XCTAssertEqual(credential, expected, remote)
        }
        let otherOrganization = try await resolver.credential(for: "https://dev.azure.com/contoso/Web/_git/Site")
        XCTAssertNil(otherOrganization)
    }

    func testConnectAzureDevOpsRejectedTokenSavesNothing() async {
        let events = EventRecorder()
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            azureDevOpsAuthService: AzureDevOpsProviderAuthService(httpClient: AzureConnectionHTTPClient(status: 401))
        )

        await controller.connectAzureDevOps(organization: "contoso", accessToken: "expired")

        XCTAssertEqual(controller.errorMessage, AzureDevOpsProviderAuthService.rejectedTokenMessage)
        XCTAssertTrue(controller.accounts.isEmpty)
        XCTAssertTrue(events.values.isEmpty)
    }

    func testConnectAzureDevOpsRejectsInvalidOrganizationWithoutRequest() async {
        let client = AzureConnectionHTTPClient(userIDs: ["azure-user-1"])
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: FakeGitProviderTokenVault(),
            azureDevOpsAuthService: AzureDevOpsProviderAuthService(httpClient: client)
        )

        await controller.connectAzureDevOps(organization: "https://github.com/octocat", accessToken: "azure-pat")

        XCTAssertEqual(controller.errorMessage, "Enter an Azure DevOps organization name or URL.")
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testConnectAzureDevOpsRejectsDuplicateAndAllowsSecondOrganization() async {
        let client = AzureConnectionHTTPClient(userIDs: ["azure-user-1", "azure-user-1", "azure-user-1"])
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: FakeGitProviderTokenVault(),
            azureDevOpsAuthService: AzureDevOpsProviderAuthService(httpClient: client),
            multipleAccountAccess: { .allowed }
        )

        await controller.connectAzureDevOps(organization: "contoso", accessToken: "first")
        await controller.connectAzureDevOps(organization: "Contoso", accessToken: "again")

        XCTAssertEqual(
            controller.errorMessage,
            GitProviderAccountAccessError.accountAlreadyConnected(username: "azure-user-1@example.com").localizedDescription
        )
        XCTAssertEqual(controller.accounts.count, 1)

        await controller.connectAzureDevOps(organization: "fabrikam", accessToken: "second-org")

        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(
            Set(controller.accounts.map(\.hostURL.absoluteString)),
            ["https://dev.azure.com/contoso", "https://dev.azure.com/fabrikam"]
        )
    }

    func testReconnectAzureDevOpsReplacesTokenForSameUserOnly() async throws {
        let client = AzureConnectionHTTPClient(userIDs: ["azure-user-1", "azure-user-1", "azure-user-2"])
        let vault = FakeGitProviderTokenVault()
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: vault,
            azureDevOpsAuthService: AzureDevOpsProviderAuthService(httpClient: client)
        )
        await controller.connectAzureDevOps(organization: "contoso", accessToken: "old-token")
        let account = try XCTUnwrap(controller.accounts.first)

        await controller.connectAzureDevOps(organization: "contoso", accessToken: "new-token", replacing: account)

        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.accounts.map(\.id), [account.id])
        XCTAssertEqual(try vault.readToken(for: account)?.accessToken, "new-token")

        await controller.connectAzureDevOps(organization: "contoso", accessToken: "someone-else", replacing: account)

        XCTAssertEqual(controller.errorMessage, GitProviderAccountAccessError.differentAccount.localizedDescription)
        XCTAssertEqual(try vault.readToken(for: account)?.accessToken, "new-token")
    }

    func testConnectAzureDevOpsRespectsFreeAccountLimitBeforeRequest() async {
        let client = AzureConnectionHTTPClient(userIDs: ["azure-user-1"])
        let existing = makeProviderAccount(macgitUID: "local-owner")
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existing]),
            tokenVault: FakeGitProviderTokenVault(tokensByAccountID: [
                existing.id: GitProviderToken(accessToken: "github-token", tokenType: "bearer")
            ]),
            azureDevOpsAuthService: AzureDevOpsProviderAuthService(httpClient: client)
        )
        await controller.reload()

        await controller.connectAzureDevOps(organization: "contoso", accessToken: "azure-pat")

        XCTAssertEqual(
            controller.errorMessage,
            GitProviderAccountAccessError.freeAccountLimitReached(limit: GitProviderAccountAccessPolicy.freeAccountLimit).localizedDescription
        )
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testConnectAzureDevOpsSSHUsesOrganizationAndSuppliesKey() async throws {
        let ssh = FakeGitProviderSSHAuthService(username: "git")
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: FakeGitProviderTokenVault(),
            sshKeyStore: FakeGitProviderSSHKeyStore(),
            sshAuthService: ssh
        )
        let host = GitProviderHost(kind: .azureDevOps, baseURL: AzureReposRemote.organizationURL("Trantienthanh1998"))

        await controller.connectSSH(host: host, key: GitProviderSSHKey(path: "/test/id_rsa"), username: "Trantienthanh1998")

        XCTAssertNil(controller.errorMessage)
        let account = try XCTUnwrap(controller.accounts.first)
        XCTAssertEqual(account.username, "Trantienthanh1998")
        XCTAssertEqual(account.transportProtocol, .ssh)
        XCTAssertEqual(ssh.requests.first?.host.kind, .azureDevOps)
        let credential = try controller.credentialResolver()
            .sshCredential(for: "git@ssh.dev.azure.com:v3/Trantienthanh1998/ChatApp/ChatApp")
        XCTAssertEqual(credential, GitSSHCredential(username: "git", keyPath: "/test/id_rsa"))
        let otherOrganization = try controller.credentialResolver()
            .sshCredential(for: "git@ssh.dev.azure.com:v3/contoso/Web/Site")
        XCTAssertNil(otherOrganization)
    }

    func testAzureDevOpsPATSurvivesSwitchingToSSHAndBack() async throws {
        let vault = FakeGitProviderTokenVault()
        let sshKeyStore = FakeGitProviderSSHKeyStore()
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: vault,
            sshKeyStore: sshKeyStore,
            sshAuthService: FakeGitProviderSSHAuthService(username: "git"),
            azureDevOpsAuthService: AzureDevOpsProviderAuthService(httpClient: AzureConnectionHTTPClient(userIDs: ["azure-user-1"]))
        )
        await controller.connectAzureDevOps(organization: "Trantienthanh1998", accessToken: "azure-pat")
        let httpsAccount = try XCTUnwrap(controller.accounts.first)
        let host = GitProviderHost(kind: .azureDevOps, baseURL: httpsAccount.hostURL)

        await controller.connectSSH(
            host: host,
            key: GitProviderSSHKey(path: "/test/id_rsa"),
            username: "Trantienthanh1998",
            replacing: httpsAccount
        )
        let sshAccount = try XCTUnwrap(controller.accounts.first)
        await controller.saveConnectionSettings(account: sshAccount, transportProtocol: .ssh, sshKey: GitProviderSSHKey(path: "/test/id_rsa"))

        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.accounts.map(\.id), [httpsAccount.id])
        XCTAssertEqual(controller.accounts.first?.transportProtocol, .ssh)
        XCTAssertEqual(controller.accounts.first?.username, httpsAccount.username)
        XCTAssertTrue(controller.hasStoredToken(for: sshAccount))

        await controller.saveConnectionSettings(account: sshAccount, transportProtocol: .https, sshKey: nil)

        XCTAssertEqual(controller.accounts.first?.transportProtocol, .https)
        XCTAssertEqual(try vault.readToken(for: httpsAccount)?.accessToken, "azure-pat")
        let credential = try await controller.credentialResolver()
            .credential(for: "https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp")
        XCTAssertEqual(credential, GitCredential(username: httpsAccount.username, token: "azure-pat"))
    }

    func testAzureDevOpsSSHOnlyAccountHasNoStoredToken() async throws {
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(),
            tokenVault: FakeGitProviderTokenVault(),
            sshKeyStore: FakeGitProviderSSHKeyStore(),
            sshAuthService: FakeGitProviderSSHAuthService(username: "git")
        )
        let host = GitProviderHost(kind: .azureDevOps, baseURL: AzureReposRemote.organizationURL("contoso"))

        await controller.connectSSH(host: host, key: GitProviderSSHKey(path: "/test/id_rsa"), username: "contoso")

        let account = try XCTUnwrap(controller.accounts.first)
        XCTAssertFalse(controller.hasStoredToken(for: account))
    }

    func testTestingSSHKeyForHTTPSAccountKeepsItsIdentityAndToken() async throws {
        var existingAccount = makeProviderAccount(macgitUID: "local-owner")
        existingAccount.permissions["authentication"] = "personalAccessToken"
        let token = GitProviderToken(accessToken: "existing-token", refreshToken: nil, tokenType: "bearer")
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [existingAccount.id: token])
        let sshKeyStore = FakeGitProviderSSHKeyStore()
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount]),
            tokenVault: vault,
            sshKeyStore: sshKeyStore,
            sshAuthService: FakeGitProviderSSHAuthService(username: "octocat")
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.connectSSH(host: .githubDotCom, key: GitProviderSSHKey(path: "/test/key"), replacing: existingAccount)

        XCTAssertNil(controller.errorMessage)
        let account = try XCTUnwrap(controller.accounts.first)
        XCTAssertEqual(controller.accounts.count, 1)
        XCTAssertEqual(account.id, existingAccount.id)
        XCTAssertEqual(account.providerUserID, existingAccount.providerUserID)
        XCTAssertEqual(account.permissions, existingAccount.permissions)
        XCTAssertEqual(account.transportProtocol, .ssh)
        XCTAssertEqual(try sshKeyStore.key(for: account), GitProviderSSHKey(path: "/test/key"))
        XCTAssertEqual(try vault.readToken(for: account), token)
    }

    func testTestingSSHKeyOfDifferentUserForExistingAccountIsRejected() async {
        let events = EventRecorder()
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount], events: events),
            tokenVault: FakeGitProviderTokenVault(),
            sshKeyStore: FakeGitProviderSSHKeyStore(),
            sshAuthService: FakeGitProviderSSHAuthService(username: "someone-else")
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.connectSSH(host: .githubDotCom, key: GitProviderSSHKey(path: "/test/key"), replacing: existingAccount)

        XCTAssertEqual(controller.errorMessage, GitProviderAccountAccessError.differentAccount.localizedDescription)
        XCTAssertEqual(controller.accounts.map(\.id), [existingAccount.id])
        XCTAssertEqual(controller.accounts.map(\.transportProtocol), [.https])
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
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)

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
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

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
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.connectGitHub()
        _ = await controller.handleProviderOAuthCallback(gitHubCallback())

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
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.connectGitHub()
        _ = await controller.handleProviderOAuthCallback(gitHubCallback())

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
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.reconnect(existingAccount)
        _ = await controller.handleProviderOAuthCallback(gitHubCallback())

        XCTAssertEqual(controller.accounts.map(\.id), [existingAccount.id])
        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertNil(controller.errorMessage)
    }

    // MARK: Duplicate accounts

    func testAddingAlreadyConnectedAccountIsRejectedWithoutOverwritingIt() async {
        let events = EventRecorder()
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let existingToken = GitProviderToken(accessToken: "existing-token", refreshToken: nil, tokenType: "bearer")
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [existingAccount.id: existingToken], events: events)
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount], events: events),
            tokenVault: vault,
            authService: FakeGitProviderAuthService(account: existingAccount),
            configuration: makeConfiguration(),
            openURL: { _ in true },
            multipleAccountAccess: { .allowed }
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.connectGitHub()
        _ = await controller.handleProviderOAuthCallback(gitHubCallback())

        XCTAssertEqual(controller.errorMessage, "octocat is already connected. Edit that account to update its sign-in.")
        XCTAssertEqual(controller.accounts, [existingAccount])
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertEqual(try vault.readToken(for: existingAccount), existingToken)
    }

    func testReconnectWithDifferentProviderUserIsRejected() async {
        let events = EventRecorder()
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let otherAccount = makeProviderAccount(macgitUID: "local-owner", id: "connection-2", providerUserID: "provider-user-84")
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount], events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            authService: FakeGitProviderAuthService(account: otherAccount),
            configuration: makeConfiguration(),
            openURL: { _ in true },
            multipleAccountAccess: { .allowed }
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.reconnect(existingAccount)
        _ = await controller.handleProviderOAuthCallback(gitHubCallback())

        XCTAssertEqual(controller.errorMessage, GitProviderAccountAccessError.differentAccount.localizedDescription)
        XCTAssertEqual(controller.accounts.map(\.id), [existingAccount.id])
        XCTAssertTrue(events.values.isEmpty)
    }

    func testAddingSSHAccountForUserConnectedOverHTTPSIsRejected() async {
        let events = EventRecorder()
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let sshKeyStore = FakeGitProviderSSHKeyStore()
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount], events: events),
            tokenVault: FakeGitProviderTokenVault(),
            sshKeyStore: sshKeyStore,
            sshAuthService: FakeGitProviderSSHAuthService(username: "OctoCat"),
            multipleAccountAccess: { .allowed }
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.connectSSH(host: .githubDotCom, key: GitProviderSSHKey(path: "/test/key"))

        XCTAssertEqual(controller.errorMessage, "octocat is already connected. Edit that account to update its sign-in.")
        XCTAssertEqual(controller.accounts.map(\.id), [existingAccount.id])
        XCTAssertTrue(events.values.isEmpty)
    }

    func testAddingHTTPSAccountForUserConnectedOverSSHIsRejected() async {
        let events = EventRecorder()
        let sshAccount = makeProviderAccount(
            macgitUID: "local-owner",
            id: "local-owner:github:github.com:octocat",
            providerUserID: "octocat",
            transportProtocol: .ssh
        )
        let sshKeyStore = FakeGitProviderSSHKeyStore(keysByAccountID: [sshAccount.id: GitProviderSSHKey(path: "/test/key")])
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [sshAccount], events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            sshKeyStore: sshKeyStore,
            authService: FakeGitProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner")),
            configuration: makeConfiguration(),
            openURL: { _ in true },
            multipleAccountAccess: { .allowed }
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.connectGitHub()
        _ = await controller.handleProviderOAuthCallback(gitHubCallback())

        XCTAssertEqual(controller.errorMessage, "octocat is already connected. Edit that account to update its sign-in.")
        XCTAssertEqual(controller.accounts.map(\.id), [sshAccount.id])
        XCTAssertTrue(events.values.isEmpty)
    }

    func testAddingSameBitbucketUserTwiceIsRejected() async {
        let events = EventRecorder()
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            multipleAccountAccess: { .allowed }
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)
        await controller.connectBitbucket(username: "Trantienthanh2412", apiToken: "first-token")
        events.values.removeAll()

        await controller.connectBitbucket(username: "Trantienthanh2412", apiToken: "second-token")

        XCTAssertEqual(controller.errorMessage, "Trantienthanh2412 is already connected. Edit that account to update its sign-in.")
        XCTAssertEqual(controller.accounts.count, 1)
        XCTAssertTrue(events.values.isEmpty)
    }

    // MARK: GitHub browser authorization

    func testConnectGitHubOpensBrowserAndCompletesFromCallback() async throws {
        let events = EventRecorder()
        let providerAccount = makeProviderAccount(macgitUID: "macgit-user-1")
        let authService = FakeGitProviderAuthService(account: providerAccount)
        var openedURLs: [URL] = []
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            authService: authService,
            configuration: makeConfiguration(),
            openURL: { openedURLs.append($0); return true }
        )
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"), cloudSyncEnabled: true)
        events.values.removeAll()

        await controller.connectGitHub()

        XCTAssertEqual(openedURLs.map(\.host), ["github.com"])
        XCTAssertEqual(controller.awaitingBrowserAuthorizationProvider, .github)
        XCTAssertNil(controller.pendingDeviceAuthorization)

        let handled = await controller.handleProviderOAuthCallback(gitHubCallback())

        XCTAssertTrue(handled)
        XCTAssertEqual(authService.exchangedCodes, ["web-code"])
        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertEqual(controller.accounts, [providerAccount])
        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertNil(controller.errorMessage)
    }

    func testRepeatedCallbackDeliveryExchangesOnce() async {
        let authService = FakeGitProviderAuthService(account: makeProviderAccount(macgitUID: "macgit-user-1"))
        let controller = makeWebFlowController(authService: authService)
        await controller.connectGitHub()

        async let first = controller.handleProviderOAuthCallback(gitHubCallback())
        async let second = controller.handleProviderOAuthCallback(gitHubCallback())
        _ = await (first, second)

        XCTAssertEqual(authService.exchangedCodes, ["web-code"])
    }

    func testDeniedOnGitHubEndsSilently() async {
        let authService = FakeGitProviderAuthService(account: makeProviderAccount(macgitUID: "macgit-user-1"))
        let controller = makeWebFlowController(authService: authService)
        await controller.connectGitHub()

        let handled = await controller.handleProviderOAuthCallback(
            URL(string: "macgit://git-provider/oauth/github/callback?error=access_denied&state=web-state")!
        )

        XCTAssertTrue(handled)
        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(authService.exchangedCodes.isEmpty)
        XCTAssertTrue(controller.accounts.isEmpty)
    }

    func testCallbackAfterCancelIsIgnored() async {
        let authService = FakeGitProviderAuthService(account: makeProviderAccount(macgitUID: "macgit-user-1"))
        let controller = makeWebFlowController(authService: authService)
        await controller.connectGitHub()

        controller.cancelBrowserAuthorization()
        let handled = await controller.handleProviderOAuthCallback(gitHubCallback())

        XCTAssertFalse(handled)
        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertTrue(authService.exchangedCodes.isEmpty)
        XCTAssertTrue(controller.accounts.isEmpty)
    }

    func testForgedStateIsIgnoredAndKeepsWaiting() async {
        let authService = FakeGitProviderAuthService(account: makeProviderAccount(macgitUID: "macgit-user-1"))
        let controller = makeWebFlowController(authService: authService)
        await controller.connectGitHub()

        let handled = await controller.handleProviderOAuthCallback(gitHubCallback(state: "forged"))

        XCTAssertTrue(handled)
        XCTAssertTrue(authService.exchangedCodes.isEmpty)
        XCTAssertEqual(controller.awaitingBrowserAuthorizationProvider, .github)
        XCTAssertNil(controller.errorMessage)

        _ = await controller.handleProviderOAuthCallback(gitHubCallback())
        XCTAssertEqual(authService.exchangedCodes, ["web-code"])
    }

    func testStaleCallbackIsRejectedWithoutExchange() async {
        let authService = FakeGitProviderAuthService(account: makeProviderAccount(macgitUID: "macgit-user-1"))
        authService.sessionStartedAt = Date().addingTimeInterval(-601)
        let controller = makeWebFlowController(authService: authService)
        await controller.connectGitHub()

        _ = await controller.handleProviderOAuthCallback(gitHubCallback())

        XCTAssertTrue(authService.exchangedCodes.isEmpty)
        XCTAssertEqual(controller.errorMessage, "The authorization expired. Try connecting again.")
        XCTAssertTrue(controller.accounts.isEmpty)
    }

    func testPendingAuthorizationExpiresWithoutCallback() async throws {
        let authService = FakeGitProviderAuthService(account: makeProviderAccount(macgitUID: "macgit-user-1"))
        let controller = makeWebFlowController(authService: authService)
        controller.oauthAuthorizationLifetime = 0.05
        await controller.connectGitHub()

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertEqual(controller.errorMessage, "The authorization expired. Try connecting again.")
    }

    func testExchangeFailureSavesNothingAndOffersDeviceCode() async {
        let events = EventRecorder()
        let authService = FakeGitProviderAuthService(account: makeProviderAccount(macgitUID: "macgit-user-1"))
        authService.exchangeError = GitProviderAuthError.connectionServiceUnavailable
        let controller = makeWebFlowController(authService: authService, events: events)
        await controller.connectGitHub()

        _ = await controller.handleProviderOAuthCallback(gitHubCallback())

        XCTAssertTrue(events.values.isEmpty)
        XCTAssertTrue(controller.accounts.isEmpty)
        XCTAssertEqual(controller.errorMessage, GitProviderAuthError.connectionServiceUnavailable.localizedDescription)
        XCTAssertTrue(controller.errorMessage?.contains("device code") == true)
    }

    func testDeviceCodeFallbackCancelsBrowserAuthorization() async {
        let authService = FakeGitProviderAuthService(account: makeProviderAccount(macgitUID: "macgit-user-1"))
        let controller = makeWebFlowController(authService: authService)
        await controller.connectGitHub()

        await controller.connectGitHubWithDeviceCode()
        let lateCallback = await controller.handleProviderOAuthCallback(gitHubCallback())

        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertEqual(controller.accounts.map(\.id), ["connection-1"])
        XCTAssertFalse(lateCallback)
        XCTAssertTrue(authService.exchangedCodes.isEmpty)
    }

    private func makeWebFlowController(
        authService: FakeGitProviderAuthService,
        events: EventRecorder? = nil
    ) -> GitProviderAccountController {
        let events = events ?? EventRecorder()
        return GitProviderAccountController(
            store: FakeGitProviderAccountStore(events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            authService: authService,
            configuration: makeConfiguration(),
            openURL: { _ in true }
        )
    }

    private func gitHubCallback(code: String = "web-code", state: String = "web-state") -> URL {
        URL(string: "macgit://git-provider/oauth/github/callback?code=\(code)&state=\(state)")!
    }

    // MARK: GitLab browser authorization

    func testConnectGitLabOpensBrowserAndCompletesFromCallback() async throws {
        let events = EventRecorder()
        let providerAccount = makeProviderAccount(macgitUID: "local-owner", provider: .gitlab)
        let gitLabAuthService = FakeGitLabProviderAuthService(account: providerAccount)
        let vault = FakeGitProviderTokenVault(events: events)
        var openedURLs: [URL] = []
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(events: events),
            tokenVault: vault,
            gitLabAuthService: gitLabAuthService,
            openURL: { openedURLs.append($0); return true }
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.connectGitLabDotCom()

        XCTAssertEqual(openedURLs.map(\.host), ["gitlab.com"])
        XCTAssertEqual(controller.awaitingBrowserAuthorizationProvider, .gitlab)
        XCTAssertNil(controller.pendingDeviceAuthorization)
        XCTAssertTrue(gitLabAuthService.deviceAuthorizationHosts.isEmpty)

        let handled = await controller.handleProviderOAuthCallback(gitLabCallback())

        XCTAssertTrue(handled)
        XCTAssertEqual(gitLabAuthService.exchangedCodes, ["gitlab-code"])
        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertEqual(controller.accounts, [providerAccount])
        XCTAssertEqual(try vault.readToken(for: providerAccount)?.refreshToken, "gitlab-web-refresh")
        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertNil(controller.errorMessage)
    }

    func testDeniedOnGitLabEndsSilently() async {
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        let controller = makeGitLabWebFlowController(gitLabAuthService: gitLabAuthService)
        await controller.connectGitLabDotCom()

        let handled = await controller.handleProviderOAuthCallback(URL(
            string: "macgit://git-provider/oauth/gitlab/callback?error=access_denied&error_description=The%20resource%20owner%20denied&state=gitlab-web-state"
        )!)

        XCTAssertTrue(handled)
        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(gitLabAuthService.exchangedCodes.isEmpty)
        XCTAssertTrue(controller.accounts.isEmpty)
    }

    func testGitLabCallbackAfterCancelIsIgnored() async {
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        let controller = makeGitLabWebFlowController(gitLabAuthService: gitLabAuthService)
        await controller.connectGitLabDotCom()

        controller.cancelBrowserAuthorization()
        let handled = await controller.handleProviderOAuthCallback(gitLabCallback())

        XCTAssertFalse(handled)
        XCTAssertTrue(gitLabAuthService.exchangedCodes.isEmpty)
        XCTAssertTrue(controller.accounts.isEmpty)
    }

    func testGitLabAuthorizationExpires() async throws {
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        let controller = makeGitLabWebFlowController(gitLabAuthService: gitLabAuthService)
        controller.oauthAuthorizationLifetime = 0.05
        await controller.connectGitLabDotCom()

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertEqual(controller.errorMessage, "The authorization expired. Try connecting again.")
    }

    func testStaleGitLabCallbackIsRejectedWithoutExchange() async {
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        gitLabAuthService.sessionStartedAt = Date().addingTimeInterval(-601)
        let controller = makeGitLabWebFlowController(gitLabAuthService: gitLabAuthService)
        await controller.connectGitLabDotCom()

        _ = await controller.handleProviderOAuthCallback(gitLabCallback())

        XCTAssertTrue(gitLabAuthService.exchangedCodes.isEmpty)
        XCTAssertEqual(controller.errorMessage, "The authorization expired. Try connecting again.")
    }

    func testForgedGitLabStateIsIgnoredAndKeepsWaiting() async {
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        let controller = makeGitLabWebFlowController(gitLabAuthService: gitLabAuthService)
        await controller.connectGitLabDotCom()

        let handled = await controller.handleProviderOAuthCallback(gitLabCallback(state: "forged"))

        XCTAssertTrue(handled)
        XCTAssertTrue(gitLabAuthService.exchangedCodes.isEmpty)
        XCTAssertEqual(controller.awaitingBrowserAuthorizationProvider, .gitlab)
        XCTAssertNil(controller.errorMessage)
    }

    func testGitHubCallbackWhileGitLabIsPendingIsIgnored() async {
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        let controller = makeGitLabWebFlowController(gitLabAuthService: gitLabAuthService)
        await controller.connectGitLabDotCom()

        let handled = await controller.handleProviderOAuthCallback(gitHubCallback(state: "gitlab-web-state"))

        XCTAssertFalse(handled)
        XCTAssertTrue(gitLabAuthService.exchangedCodes.isEmpty)
        XCTAssertEqual(controller.awaitingBrowserAuthorizationProvider, .gitlab)
    }

    func testGitLabExchangeFailureSavesNothing() async {
        let events = EventRecorder()
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        gitLabAuthService.exchangeError = GitProviderAuthError.providerMessage("The provided authorization grant is invalid.")
        let controller = makeGitLabWebFlowController(gitLabAuthService: gitLabAuthService, events: events)
        await controller.connectGitLabDotCom()

        _ = await controller.handleProviderOAuthCallback(gitLabCallback())

        XCTAssertTrue(events.values.isEmpty)
        XCTAssertTrue(controller.accounts.isEmpty)
        XCTAssertEqual(controller.errorMessage, "The provided authorization grant is invalid.")
    }

    func testFreePlanLimitBlocksGitLabBrowserBeforeOpening() async {
        let existingAccount = makeProviderAccount(macgitUID: "local-owner")
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        var openedURLs: [URL] = []
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount]),
            tokenVault: FakeGitProviderTokenVault(),
            gitLabAuthService: gitLabAuthService,
            openURL: { openedURLs.append($0); return true },
            multipleAccountAccess: { .denied(.requiresPro) }
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.connectGitLabDotCom()

        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertEqual(controller.errorMessage, "Free plan includes 1 Git provider account. Upgrade to Pro to add more.")
    }

    func testReconnectGitLabReplacesTokenWithoutDuplicate() async throws {
        let events = EventRecorder()
        let existingAccount = makeProviderAccount(macgitUID: "local-owner", provider: .gitlab, tokenStatus: .reauthorizationRequired)
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        let vault = FakeGitProviderTokenVault(
            tokensByAccountID: [existingAccount.id: GitProviderToken(accessToken: "old", refreshToken: nil, expiresAt: nil, tokenType: "Bearer")],
            events: events
        )
        var openedURLs: [URL] = []
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount], events: events),
            tokenVault: vault,
            gitLabAuthService: gitLabAuthService,
            openURL: { openedURLs.append($0); return true },
            multipleAccountAccess: { .denied(.requiresPro) }
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)
        events.values.removeAll()

        await controller.reconnect(existingAccount)
        XCTAssertEqual(openedURLs.map(\.host), ["gitlab.com"])
        _ = await controller.handleProviderOAuthCallback(gitLabCallback())

        XCTAssertEqual(controller.accounts.map(\.id), [existingAccount.id])
        XCTAssertEqual(try vault.readToken(for: existingAccount)?.accessToken, "gitlab-web-token")
        XCTAssertEqual(events.values, ["save-token", "save-metadata"])
        XCTAssertNil(controller.errorMessage)
    }

    func testReconnectSelfHostedGitLabDoesNotOpenBrowser() async {
        var existingAccount = makeProviderAccount(macgitUID: "local-owner", provider: .gitlab)
        existingAccount.hostURL = URL(string: "https://gitlab.company.test")!
        let gitLabAuthService = FakeGitLabProviderAuthService(account: existingAccount)
        var openedURLs: [URL] = []
        let controller = GitProviderAccountController(
            store: FakeGitProviderAccountStore(localAccounts: [existingAccount]),
            tokenVault: FakeGitProviderTokenVault(),
            gitLabAuthService: gitLabAuthService,
            openURL: { openedURLs.append($0); return true },
            hasProAccess: { true }
        )
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

        await controller.reconnect(existingAccount)

        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertEqual(
            controller.errorMessage,
            "Edit this self-hosted account and enter a new personal access token or test its SSH key."
        )
    }

    func testGitLabDeviceCodeFallbackCancelsBrowserAuthorization() async {
        let gitLabAuthService = FakeGitLabProviderAuthService(account: makeProviderAccount(macgitUID: "local-owner", provider: .gitlab))
        let controller = makeGitLabWebFlowController(gitLabAuthService: gitLabAuthService)
        await controller.connectGitLabDotCom()

        await controller.connectGitLabWithDeviceCode()
        let lateCallback = await controller.handleProviderOAuthCallback(gitLabCallback())

        XCTAssertNil(controller.awaitingBrowserAuthorizationProvider)
        XCTAssertEqual(gitLabAuthService.deviceAuthorizationHosts, [.gitlabDotCom])
        XCTAssertEqual(controller.accounts.map(\.id), ["connection-1"])
        XCTAssertFalse(lateCallback)
        XCTAssertTrue(gitLabAuthService.exchangedCodes.isEmpty)
    }

    private func makeGitLabWebFlowController(
        gitLabAuthService: FakeGitLabProviderAuthService,
        events: EventRecorder? = nil
    ) -> GitProviderAccountController {
        let events = events ?? EventRecorder()
        return GitProviderAccountController(
            store: FakeGitProviderAccountStore(events: events),
            tokenVault: FakeGitProviderTokenVault(events: events),
            gitLabAuthService: gitLabAuthService,
            openURL: { _ in true }
        )
    }

    private func gitLabCallback(code: String = "gitlab-code", state: String = "gitlab-web-state") -> URL {
        URL(string: "macgit://git-provider/oauth/gitlab/callback?code=\(code)&state=\(state)")!
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
        await controller.updateMacgitAccount(nil, cloudSyncEnabled: true)

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
        case .azureDevOps: URL(string: "https://dev.azure.com/contoso")!
        }
    }

    private func username(for provider: GitProviderKind) -> String {
        switch provider {
        case .github: "octocat"
        case .gitlab: "tanuki"
        case .bitbucket: "Trantienthanh2412"
        case .azureDevOps: "dev@contoso.com"
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

    var sessionStartedAt = Date()
    var exchangeError: Error?
    private(set) var exchangedCodes: [String] = []

    func makeOAuthSession(host: GitProviderHost) -> GitProviderOAuthSession {
        GitProviderOAuthSession(
            provider: .gitlab,
            host: host.normalized,
            state: "gitlab-web-state",
            codeVerifier: "gitlab-web-verifier",
            redirectURI: URL(string: "https://commitplus.app/oauth/gitlab/callback")!,
            appCallbackURL: URL(string: "macgit://git-provider/oauth/gitlab/callback")!,
            startedAt: sessionStartedAt
        )
    }

    func authorizationURL(for session: GitProviderOAuthSession) throws -> URL {
        URL(string: "https://gitlab.com/oauth/authorize?state=\(session.state)")!
    }

    func exchangeCallback(
        _ callback: GitProviderOAuthCallback,
        session: GitProviderOAuthSession
    ) async throws -> GitProviderToken {
        exchangedCodes.append(callback.code)
        if let exchangeError { throw exchangeError }
        return GitProviderToken(
            accessToken: "gitlab-web-token",
            refreshToken: "gitlab-web-refresh",
            expiresAt: .now.addingTimeInterval(7_200),
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

    var sessionStartedAt = Date()
    var exchangeError: Error?
    private(set) var exchangedCodes: [String] = []

    func makeOAuthSession() -> GitProviderOAuthSession {
        GitProviderOAuthSession(
            provider: .github,
            host: .githubDotCom,
            state: "web-state",
            codeVerifier: "web-verifier",
            redirectURI: URL(string: "https://commitplus.app/oauth/github/callback")!,
            appCallbackURL: URL(string: "macgit://git-provider/oauth/github/callback")!,
            startedAt: sessionStartedAt
        )
    }

    func authorizationURL(for session: GitProviderOAuthSession) throws -> URL {
        URL(string: "https://github.com/login/oauth/authorize?state=\(session.state)")!
    }

    func exchangeCallback(
        _ callback: GitProviderOAuthCallback,
        session: GitProviderOAuthSession
    ) async throws -> GitProviderToken {
        exchangedCodes.append(callback.code)
        if let exchangeError { throw exchangeError }
        return GitProviderToken(accessToken: "web-token", refreshToken: nil, expiresAt: nil, tokenType: "bearer")
    }

    func fetchAccount(
        token: GitProviderToken,
        macgitUID: String,
        host: GitProviderHost
    ) async throws -> GitProviderAccount {
        account
    }
}

private final class AzureConnectionHTTPClient: GitProviderHTTPClient {
    private(set) var requests: [URLRequest] = []
    private var userIDs: [String]
    private let status: Int

    init(userIDs: [String] = [], status: Int = 200) {
        self.userIDs = userIDs
        self.status = status
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let userID = userIDs.isEmpty ? "unexpected" : userIDs.removeFirst()
        let body = #"{"authenticatedUser":{"id":"\#(userID)","providerDisplayName":"Azure User","properties":{"Account":{"$value":"\#(userID)@example.com"}}}}"#
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}
