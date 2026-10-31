// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Maps a remote to a provider repository and picks the connected account whose token
/// can call that provider's API. Shared by pull requests and hosted issues.
@MainActor
struct GitProviderAPICredentialResolver {
    let accounts: () -> [GitProviderAccount]
    let tokenVault: GitProviderTokenVault

    init(providerAccountController: GitProviderAccountController, tokenVault: GitProviderTokenVault) {
        self.init(accounts: { [weak providerAccountController] in providerAccountController?.accounts ?? [] },
                  tokenVault: tokenVault)
    }

    init(accounts: @escaping () -> [GitProviderAccount], tokenVault: GitProviderTokenVault) {
        self.accounts = accounts
        self.tokenVault = tokenVault
    }

    func repository(forRemoteURL remoteURLString: String) -> GitRepositoryIdentity? {
        let accounts = accounts()
        guard let identity = GitRemoteIdentityResolver.identity(
            from: remoteURLString,
            knownGitLabHosts: Set(accounts.compactMap { account in
                account.provider == .gitlab ? Self.normalizedHost(account.hostURL) : nil
            }),
            knownHosts: accounts.map { GitProviderHost(kind: $0.provider, baseURL: $0.hostURL) }
        ) else { return nil }
        return GitRepositoryIdentity(
            provider: identity.provider,
            hostURL: identity.hostURL,
            owner: identity.ownerPath,
            name: identity.repositoryName
        )
    }

    func matchingAccounts(for repository: GitRepositoryIdentity) -> [GitProviderAccount] {
        let repositoryHost = Self.normalizedHost(repository.hostURL)
        return accounts().filter { account in
            account.provider == repository.provider && Self.normalizedHost(account.hostURL) == repositoryHost
        }
    }

    /// The first usable account, trying `preferredAccountID` first.
    func credential(
        for accounts: [GitProviderAccount],
        preferredAccountID: String? = nil
    ) -> (account: GitProviderAccount, token: GitProviderToken)? {
        var prioritized = accounts
        if let preferredAccountID, let selected = accounts.first(where: { $0.id == preferredAccountID }) {
            prioritized = [selected] + accounts.filter { $0.id != selected.id }
        }
        for account in prioritized {
            guard Self.supportsProviderAPI(account) else { continue }
            guard let token = try? tokenVault.readToken(for: account), !token.accessToken.isEmpty else { continue }
            return (account, token)
        }
        return nil
    }

    static func supportsProviderAPI(_ account: GitProviderAccount) -> Bool {
        account.transportProtocol == .https || account.permissions["authentication"] == "personalAccessToken" || !account.scopes.isEmpty
    }

    static func normalizedHost(_ url: URL) -> String {
        GitProviderHost.identityKey(url)
    }
}
