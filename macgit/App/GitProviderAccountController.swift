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
import Foundation

@MainActor
final class GitProviderAccountController: ObservableObject {
    @Published private(set) var accounts: [GitProviderAccount] = []
    @Published private(set) var isLoading = false
    @Published private(set) var pendingDeviceAuthorization: GitProviderDeviceAuthorization?
    @Published var errorMessage: String?

    private let store: GitProviderAccountStore
    private let tokenVault: GitProviderTokenVault
    private let sshKeyStore: GitProviderSSHKeyStore
    private let sshAuthService: GitProviderSSHAuthenticating
    private let authService: GitProviderAuthenticating?
    private let configuration: GitHubProviderAuthConfiguration?
    private let gitLabAuthService: (any GitLabProviderOAuthAuthenticating)?
    private let gitLabRedirectURI: URL
    private let openURL: (URL) -> Bool
    private let hasProAccess: () -> Bool
    private let multipleAccountAccess: () -> FeatureAccessDecision
    private let accountAccessPolicy = GitProviderAccountAccessPolicy()
    private var cacheOwnerUID: String?
    private var pendingOAuthSession: GitProviderOAuthSession?
    private var gitLabRefreshTasks: [String: Task<GitProviderToken, Error>] = [:]

    private var accountOwnerID: String { store.accountOwnerID }

    init(
        store: GitProviderAccountStore,
        tokenVault: GitProviderTokenVault,
        sshKeyStore: GitProviderSSHKeyStore? = nil,
        sshAuthService: GitProviderSSHAuthenticating = GitProviderSSHAuthService(),
        authService: GitProviderAuthenticating? = nil,
        configuration: GitHubProviderAuthConfiguration? = nil,
        gitLabAuthService: (any GitLabProviderOAuthAuthenticating)? = nil,
        gitLabRedirectURI: URL = GitLabProviderAuthConfiguration.appConfiguration().redirectURI,
        openURL: @escaping (URL) -> Bool = { _ in false },
        hasProAccess: @escaping () -> Bool = { false },
        multipleAccountAccess: @escaping () -> FeatureAccessDecision = {
            .denied(.requiresPro)
        }
    ) {
        self.store = store
        self.tokenVault = tokenVault
        self.sshKeyStore = sshKeyStore ?? SQLiteGitProviderSSHKeyStore()
        self.sshAuthService = sshAuthService
        self.authService = authService
        self.configuration = configuration
        self.gitLabAuthService = gitLabAuthService
        self.gitLabRedirectURI = gitLabRedirectURI
        self.openURL = openURL
        self.multipleAccountAccess = multipleAccountAccess
        self.hasProAccess = hasProAccess
    }

    var canConnectSelfHosted: Bool { hasProAccess() }

    func refreshConnectionAccess() { objectWillChange.send() }

    var accountCreationDecision: GitProviderAccountCreationDecision {
        accountAccessPolicy.creationDecision(
            existingAccountCount: accounts.count,
            multipleAccountAccess: multipleAccountAccess()
        )
    }

    func updateMacgitAccount(_ account: AccountSnapshot?) async {
        let previousAccounts = accounts
        // Initial auth restoration (nil -> uid) should retain valid disk cache.
        if let previousUID = cacheOwnerUID, previousUID != account?.uid {
            accounts = []
            await PullRequestDiskCache.shared.remove()
        }
        cacheOwnerUID = account?.uid
        if account == nil {
            pendingDeviceAuthorization = nil
            pendingOAuthSession = nil
        }
        do {
            try await store.updateCloudAccount(uid: account?.uid)
        } catch {
            errorMessage = error.localizedDescription
        }
        await reload()
        for previousAccount in previousAccounts where !accounts.contains(where: {
            hasSameProviderIdentity($0, previousAccount)
        }) {
            try? tokenVault.deleteToken(for: previousAccount)
            try? await sshKeyStore.deleteKey(for: previousAccount)
        }
    }

    func connectGitHub() async {
        guard authorizeNewAccountCreation() else { return }
        await startGitHubDeviceAuthorization()
    }

    func connectGitLabDotCom() async {
        guard authorizeNewAccountCreation() else { return }
        await startGitLabDeviceAuthorization(host: .gitlabDotCom)
    }

    func connectSelfHostedGitLab(hostURL: URL) async {
        guard authorizeConnection(to: GitProviderHost(kind: .gitlab, baseURL: hostURL)) else { return }
        guard authorizeNewAccountCreation() else { return }
        await startGitLabDeviceAuthorization(host: GitProviderHost(kind: .gitlab, baseURL: hostURL).normalized)
    }

    func connectPersonalAccessToken(host: GitProviderHost, accessToken: String, replacing existingAccount: GitProviderAccount? = nil) async {
        errorMessage = nil
        let accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let validatedHost = GitProviderHost.configured(kind: host.kind, value: host.baseURL.absoluteString),
              validatedHost.kind != .bitbucket, !accessToken.isEmpty else {
            errorMessage = "Enter a valid HTTPS server URL and personal access token."
            return
        }
        guard authorizeConnection(to: validatedHost) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let token = GitProviderToken(accessToken: accessToken, tokenType: "Bearer")
            var account: GitProviderAccount
            switch validatedHost.kind {
            case .github:
                account = try await GitHubProviderAuthService(configuration: .appConfiguration()).fetchAccount(token: token, macgitUID: accountOwnerID, host: validatedHost)
            case .gitlab:
                account = try await GitLabProviderAuthService(configuration: .appConfiguration()).fetchAccount(token: token, macgitUID: accountOwnerID, host: validatedHost)
            case .bitbucket: return
            }
            try Task.checkCancellation()
            if let existingAccount, !hasSameProviderIdentity(existingAccount, account) {
                throw GitProviderAuthError.providerMessage("This token belongs to a different account. Add it as a new account instead.")
            }
            // PAT scope validation happens on each Git/API operation; OAuth scopes are not applicable.
            account.permissions["authentication"] = "personalAccessToken"
            account.scopes = []
            try await saveAuthorizedAccount(account, token: token)
        } catch {
            errorMessage = GitProviderAuthError.connectionMessage(error)
        }
    }

    func connectBitbucket(
        username: String,
        apiToken: String,
        replacing existingAccount: GitProviderAccount? = nil
    ) async {
        errorMessage = nil
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty else {
            errorMessage = "Enter your case-sensitive Bitbucket username."
            return
        }
        guard !normalizedToken.isEmpty else {
            errorMessage = "Enter a Bitbucket API token."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let account = GitProviderAccount(
            id: existingAccount?.id ?? sshAccountID(
                macgitUID: accountOwnerID,
                provider: .bitbucket,
                hostURL: GitProviderHost.bitbucketDotOrg.baseURL,
                username: normalizedUsername
            ),
            macgitUID: accountOwnerID,
            provider: .bitbucket,
            hostURL: GitProviderHost.bitbucketDotOrg.baseURL,
            providerUserID: normalizedUsername,
            username: normalizedUsername,
            displayName: nil,
            avatarURL: nil,
            scopes: ["read:repository:bitbucket", "write:repository:bitbucket"],
            permissions: [:],
            tokenStatus: .valid,
            transportProtocol: .https,
            connectedAt: existingAccount?.connectedAt ?? .now,
            lastValidatedAt: nil
        )

        do {
            try validateAccountCreation(for: account)
            try await saveAuthorizedAccount(
                account,
                token: GitProviderToken(
                    accessToken: normalizedToken,
                    refreshToken: nil,
                    expiresAt: nil,
                    tokenType: "Basic"
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reconnect(_ account: GitProviderAccount) async {
        guard authorizeConnection(to: GitProviderHost(kind: account.provider, baseURL: account.hostURL)) else { return }
        if account.provider != .bitbucket {
            let publicHost = account.provider == .github ? GitProviderHost.githubDotCom : GitProviderHost.gitlabDotCom
            if GitProviderHost(kind: account.provider, baseURL: account.hostURL).normalized != publicHost {
                errorMessage = "Edit this self-hosted account and enter a new personal access token or test its SSH key."
                return
            }
        }
        switch account.provider {
        case .github:
            await startGitHubDeviceAuthorization()
        case .gitlab:
            await startGitLabDeviceAuthorization(host: GitProviderHost(kind: .gitlab, baseURL: account.hostURL))
        case .bitbucket:
            errorMessage = "Enter a new Bitbucket API token to reconnect this account."
        }
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let storedAccounts = try await store.accounts()
            accounts = try storedAccounts.map { account in
                if account.transportProtocol == .ssh {
                    guard try sshKeyStore.key(for: account) != nil else {
                        var unavailableAccount = account
                        unavailableAccount.tokenStatus = .unavailableOnThisDevice
                        return unavailableAccount
                    }
                    return account
                }
                try tokenVault.migrateLegacyToken(for: account, among: storedAccounts)
                guard try tokenVault.readToken(for: account) != nil else {
                    var unavailableAccount = account
                    unavailableAccount.tokenStatus = .unavailableOnThisDevice
                    return unavailableAccount
                }
                if account.provider == .gitlab,
                   account.transportProtocol == .https,
                   account.permissions["authentication"] != "personalAccessToken",
                   !account.scopes.contains("write_repository") {
                    var accountRequiringAuthorization = account
                    accountRequiringAuthorization.tokenStatus = .reauthorizationRequired
                    return accountRequiringAuthorization
                }
                return account
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect(_ account: GitProviderAccount) async {
        errorMessage = nil
        do {
            try tokenVault.deleteToken(for: account)
            accounts.removeAll { $0.id == account.id }
            await PullRequestDiskCache.shared.remove(accountID: account.id)
            try await sshKeyStore.deleteKey(for: account)
            try await store.delete(accountID: account.id)
            accounts.removeAll { $0.id == account.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openPendingDeviceVerification() {
        guard let pendingDeviceAuthorization else { return }
        _ = openURL(pendingDeviceAuthorization.verificationURI)
    }

    func handleProviderOAuthCallback(_ url: URL) async -> Bool {
        guard let session = pendingOAuthSession else { return false }

        let callback: GitProviderOAuthCallback
        do {
            callback = try GitProviderOAuthCallback.parse(url, for: session)
        } catch GitProviderOAuthError.unsupportedCallback {
            return false
        } catch {
            errorMessage = error.localizedDescription
            pendingOAuthSession = nil
            return true
        }

        guard let gitLabAuthService else {
            errorMessage = GitProviderAuthError.invalidConfiguration.localizedDescription
            pendingOAuthSession = nil
            return true
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            pendingOAuthSession = nil
        }

        do {
            let token = try await gitLabAuthService.exchangeCallback(callback, session: session)
            let account = try await gitLabAuthService.fetchAccount(
                token: token,
                macgitUID: accountOwnerID,
                host: session.host
            )
            try await saveAuthorizedAccount(account, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        return true
    }

    func credentialResolver(
        preferredAccountIDsByRemoteIdentity: [String: String] = [:]
    ) -> GitProviderCredentialResolver {
        GitProviderCredentialResolver(
            accounts: accounts,
            tokenVault: tokenVault,
            sshKeyStore: sshKeyStore,
            preferredAccountIDsByRemoteIdentity: preferredAccountIDsByRemoteIdentity,
            tokenProvider: { [weak self] account in
                try await self?.validToken(for: account)
            }
        )
    }

    private func validToken(for account: GitProviderAccount) async throws -> GitProviderToken? {
        guard let token = try tokenVault.readToken(for: account) else { return nil }
        guard account.provider == .gitlab, account.transportProtocol == .https else {
            return token
        }

        guard account.permissions["authentication"] == "personalAccessToken" || account.scopes.contains("write_repository") else {
            await markReauthorizationRequired(account)
            throw GitProviderAuthError.reauthorizationRequired
        }

        guard let expiresAt = token.expiresAt,
              expiresAt <= Date.now.addingTimeInterval(60) else {
            return token
        }
        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            await markReauthorizationRequired(account)
            throw GitProviderAuthError.reauthorizationRequired
        }
        guard let gitLabAuthService else {
            throw GitProviderAuthError.invalidConfiguration
        }

        if let existingTask = gitLabRefreshTasks[account.id] {
            return try await existingTask.value
        }

        let task = Task {
            try await gitLabAuthService.refreshToken(
                refreshToken,
                host: GitProviderHost(kind: .gitlab, baseURL: account.hostURL)
            )
        }
        gitLabRefreshTasks[account.id] = task
        defer { gitLabRefreshTasks[account.id] = nil }

        do {
            let refreshedToken = try await task.value
            try tokenVault.saveToken(refreshedToken, for: account)
            return refreshedToken
        } catch GitProviderAuthError.reauthorizationRequired {
            await markReauthorizationRequired(account)
            throw GitProviderAuthError.reauthorizationRequired
        }
    }

    private func markReauthorizationRequired(_ account: GitProviderAccount) async {
        var updatedAccount = account
        updatedAccount.tokenStatus = .reauthorizationRequired
        publish(updatedAccount)
        do {
            try await store.save(updatedAccount)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sshKey(for account: GitProviderAccount) throws -> GitProviderSSHKey? {
        try sshKeyStore.key(for: account)
    }

    func saveConnectionSettings(
        account: GitProviderAccount,
        transportProtocol: GitProviderTransportProtocol,
        sshKey: GitProviderSSHKey?
    ) async {
        errorMessage = nil
        var updatedAccount = account
        updatedAccount.transportProtocol = transportProtocol

        do {
            if transportProtocol == .ssh, let sshKey {
                try await sshKeyStore.saveKey(sshKey, for: updatedAccount)
            } else {
                try await sshKeyStore.deleteKey(for: updatedAccount)
            }
            try await store.save(updatedAccount)
            publish(updatedAccount)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connectSSH(
        host: GitProviderHost,
        key: GitProviderSSHKey,
        username usernameOverride: String? = nil,
        replacing existingAccount: GitProviderAccount? = nil
    ) async {
        guard authorizeConnection(to: host) else { return }
        if existingAccount == nil, !authorizeNewAccountCreation() {
            return
        }
        let macgitUID = accountOwnerID

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let normalizedHost = host.normalized
        do {
            let authentication = try await sshAuthService.authenticate(host: normalizedHost, keyPath: key.path)
            let username = usernameOverride?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let resolvedUsername = username?.isEmpty == false ? username : authentication.username,
                  !resolvedUsername.isEmpty else {
                throw GitProviderCredentialError.sshKeyUnavailable(username: "Bitbucket")
            }
            let account = GitProviderAccount(
                id: existingAccount?.id ?? sshAccountID(
                    macgitUID: macgitUID,
                    provider: normalizedHost.kind,
                    hostURL: normalizedHost.baseURL,
                    username: resolvedUsername
                ),
                macgitUID: macgitUID,
                provider: normalizedHost.kind,
                hostURL: normalizedHost.baseURL,
                providerUserID: resolvedUsername,
                username: resolvedUsername,
                displayName: nil,
                avatarURL: nil,
                scopes: [],
                permissions: [:],
                tokenStatus: .valid,
                transportProtocol: .ssh,
                connectedAt: existingAccount?.connectedAt ?? .now,
                lastValidatedAt: .now
            )

            try validateAccountCreation(for: account)
            try await sshKeyStore.saveKey(key, for: account)
            do {
                try await store.save(account)
            } catch {
                try? await sshKeyStore.deleteKey(for: account)
                throw error
            }

            publish(account)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startGitHubDeviceAuthorization() async {
        guard let authService,
              let configuration,
              !configuration.clientID.isEmpty else {
            errorMessage = GitProviderAuthError.invalidConfiguration.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        pendingDeviceAuthorization = nil
        defer {
            isLoading = false
            pendingDeviceAuthorization = nil
        }

        do {
            let authorization = try await authService.requestDeviceAuthorization()
            pendingDeviceAuthorization = authorization
            guard openURL(authorization.verificationURI) else {
                errorMessage = "Commit+ could not open the GitHub device authorization page."
                return
            }

            let token = try await waitForGitHubDeviceAuthorization(authorization, authService: authService)
            let account = try await authService.fetchAccount(
                token: token,
                macgitUID: accountOwnerID,
                host: .githubDotCom
            )
            try await saveAuthorizedAccount(account, token: token)
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func waitForGitHubDeviceAuthorization(
        _ authorization: GitProviderDeviceAuthorization,
        authService: GitProviderAuthenticating
    ) async throws -> GitProviderToken {
        let startedAt = Date()
        var interval = authorization.interval

        while Date().timeIntervalSince(startedAt) < TimeInterval(authorization.expiresIn) {
            if interval > 0 {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } else {
                await Task.yield()
            }

            do {
                return try await authService.pollDeviceAuthorization(authorization)
            } catch GitProviderAuthError.authorizationPending {
                continue
            } catch GitProviderAuthError.slowDown(let nextInterval) {
                interval = nextInterval
                continue
            }
        }

        throw GitProviderAuthError.deviceCodeExpired
    }

    private func startGitLabDeviceAuthorization(host: GitProviderHost) async {
        guard let gitLabAuthService else {
            errorMessage = gitLabInvalidConfigurationMessage
            return
        }

        isLoading = true
        errorMessage = nil
        pendingDeviceAuthorization = nil
        defer {
            isLoading = false
            pendingDeviceAuthorization = nil
        }

        let normalizedHost = host.normalized
        do {
            let authorization = try await gitLabAuthService.requestDeviceAuthorization(host: normalizedHost)
            pendingDeviceAuthorization = authorization
            guard openURL(authorization.verificationURI) else {
                errorMessage = "Commit+ could not open the GitLab device authorization page."
                return
            }

            let token = try await waitForGitLabDeviceAuthorization(
                authorization,
                host: normalizedHost,
                authService: gitLabAuthService
            )
            let account = try await gitLabAuthService.fetchAccount(
                token: token,
                macgitUID: accountOwnerID,
                host: normalizedHost
            )
            try await saveAuthorizedAccount(account, token: token)
        } catch is CancellationError {
            errorMessage = nil
        } catch GitProviderAuthError.invalidConfiguration {
            errorMessage = gitLabInvalidConfigurationMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func waitForGitLabDeviceAuthorization(
        _ authorization: GitProviderDeviceAuthorization,
        host: GitProviderHost,
        authService: any GitLabProviderOAuthAuthenticating
    ) async throws -> GitProviderToken {
        let startedAt = Date()
        var interval = authorization.interval

        while Date().timeIntervalSince(startedAt) < TimeInterval(authorization.expiresIn) {
            if interval > 0 {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } else {
                await Task.yield()
            }

            do {
                return try await authService.pollDeviceAuthorization(authorization, host: host)
            } catch GitProviderAuthError.authorizationPending {
                continue
            } catch GitProviderAuthError.slowDown(let nextInterval) {
                interval = nextInterval
                continue
            }
        }

        throw GitProviderAuthError.deviceCodeExpired
    }

    private func startGitLabOAuth(host: GitProviderHost) async {
        guard let gitLabAuthService else {
            errorMessage = gitLabInvalidConfigurationMessage
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let session = GitProviderOAuthSession(
            provider: .gitlab,
            host: host.normalized,
            state: UUID().uuidString,
            codeVerifier: GitProviderPKCE.generateVerifier(),
            redirectURI: gitLabRedirectURI
        )

        do {
            let authorizationURL = try gitLabAuthService.authorizationURL(for: session)
            guard openURL(authorizationURL) else {
                errorMessage = "Commit+ could not open the GitLab authorization page."
                pendingOAuthSession = nil
                return
            }
            pendingOAuthSession = session
        } catch GitProviderAuthError.invalidConfiguration {
            errorMessage = gitLabInvalidConfigurationMessage
            pendingOAuthSession = nil
        } catch {
            errorMessage = error.localizedDescription
            pendingOAuthSession = nil
        }
    }

    private var gitLabInvalidConfigurationMessage: String {
        "GitLab account connection is not configured."
    }

    private func sshAccountID(
        macgitUID: String,
        provider: GitProviderKind,
        hostURL: URL,
        username: String
    ) -> String {
        let hostIdentifier = GitProviderHost.accountHostIdentifier(hostURL)
        return "\(macgitUID):\(provider.rawValue):\(hostIdentifier):\(username)"
    }

    private func saveAuthorizedAccount(_ account: GitProviderAccount, token: GitProviderToken) async throws {
        try validateAccountCreation(for: account)
        let previousToken = try tokenVault.readToken(for: account)
        try tokenVault.saveToken(token, for: account)
        do {
            try await store.save(account)
        } catch {
            if let previousToken { try? tokenVault.saveToken(previousToken, for: account) }
            else { try? tokenVault.deleteToken(for: account) }
            throw error
        }

        publish(account)
    }

    private func publish(_ account: GitProviderAccount) {
        accounts.removeAll {
            $0.id == account.id || hasSameProviderIdentity($0, account)
        }
        accounts.append(account)
    }

    private func hasSameProviderIdentity(
        _ lhs: GitProviderAccount,
        _ rhs: GitProviderAccount
    ) -> Bool {
        lhs.provider == rhs.provider
            && GitProviderHost.identityKey(lhs.hostURL) == GitProviderHost.identityKey(rhs.hostURL)
            && lhs.providerUserID == rhs.providerUserID
    }

    private func authorizeNewAccountCreation() -> Bool {
        errorMessage = nil
        do {
            try validateAccountCreation()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func authorizeConnection(to host: GitProviderHost) -> Bool {
        guard !host.isSelfHosted || canConnectSelfHosted else {
            errorMessage = GitProviderAccountAccessError.selfHostedRequiresPro.localizedDescription
            return false
        }
        return true
    }

    private func validateAccountCreation(for candidate: GitProviderAccount? = nil) throws {
        if let candidate, GitProviderHost(kind: candidate.provider, baseURL: candidate.hostURL).isSelfHosted, !canConnectSelfHosted {
            throw GitProviderAccountAccessError.selfHostedRequiresPro
        }
        if let candidate,
           accounts.contains(where: { hasSameProviderIdentity($0, candidate) }) {
            return
        }

        switch accountCreationDecision {
        case .allowed:
            return
        case .denied(.requiresPro(let freeLimit)):
            throw GitProviderAccountAccessError.freeAccountLimitReached(limit: freeLimit)
        case .denied(.featureDisabled):
            throw GitProviderAccountAccessError.featureDisabled
        }
    }
}
