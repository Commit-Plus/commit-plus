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

import Foundation

enum GitProviderCredentialError: LocalizedError, Equatable {
    case noConnectedAccount(host: String)
    case multipleMatchingAccounts(host: String)
    case tokenUnavailable(username: String)
    case sshKeyUnavailable(username: String)
    case sshKeyMissing(path: String)
    case unsupportedRemote

    var errorDescription: String? {
        switch self {
        case .noConnectedAccount(let host):
            return "No connected provider account is available for \(host)."
        case .multipleMatchingAccounts(let host):
            return "Multiple connected provider accounts match \(host). Choose a preferred account before using private repository credentials."
        case .tokenUnavailable(let username):
            return "The local provider token for \(username) is unavailable. Reconnect the account and try again."
        case .sshKeyUnavailable(let username):
            return "The SSH key for \(username) is unavailable. Choose a key and try again."
        case .sshKeyMissing:
            return "The selected SSH key file could not be found."
        case .unsupportedRemote:
            return "This remote is not supported for provider credentials."
        }
    }
}

struct GitProviderCredentialResolver {
    typealias TokenProvider = @MainActor (GitProviderAccount) async throws -> GitProviderToken?

    var accounts: [GitProviderAccount]
    var tokenVault: GitProviderTokenVault
    var sshKeyStore: GitProviderSSHKeyStore?
    var preferredAccountIDsByRemoteIdentity: [String: String]
    var tokenProvider: TokenProvider?

    init(
        accounts: [GitProviderAccount],
        tokenVault: GitProviderTokenVault,
        sshKeyStore: GitProviderSSHKeyStore? = nil,
        preferredAccountIDsByRemoteIdentity: [String: String] = [:],
        tokenProvider: TokenProvider? = nil
    ) {
        self.accounts = accounts
        self.tokenVault = tokenVault
        self.sshKeyStore = sshKeyStore
        self.preferredAccountIDsByRemoteIdentity = preferredAccountIDsByRemoteIdentity
        self.tokenProvider = tokenProvider
    }

    func credential(for remoteURLString: String, preferredAccountID: String? = nil) async throws -> GitCredential? {
        guard isHTTPSRemote(remoteURLString) else { return nil }
        guard let identity = GitRemoteIdentityResolver.identity(
            from: remoteURLString,
            knownGitLabHosts: connectedGitLabHosts,
            knownHosts: accounts.map { GitProviderHost(kind: $0.provider, baseURL: $0.hostURL) }
        ) else {
            return nil
        }

        let matchingAccounts = matchingAccounts(for: identity, requiresSSH: false)
        guard !matchingAccounts.isEmpty else { return nil }

        let account: GitProviderAccount
        if let preferredAccountID = preferredAccountID ?? storedPreferredAccountID(for: identity, matching: matchingAccounts) {
            guard let preferred = matchingAccounts.first(where: { $0.id == preferredAccountID }) else {
                throw GitProviderCredentialError.noConnectedAccount(host: normalizedHost(identity.hostURL))
            }
            account = preferred
        } else {
            guard matchingAccounts.count == 1, let onlyAccount = matchingAccounts.first else {
                throw GitProviderCredentialError.multipleMatchingAccounts(host: normalizedHost(identity.hostURL))
            }
            account = onlyAccount
        }

        let token = if let tokenProvider {
            try await tokenProvider(account)
        } else {
            try tokenVault.readToken(for: account)
        }
        guard let token, !token.accessToken.isEmpty else {
            throw GitProviderCredentialError.tokenUnavailable(username: account.username)
        }
        return GitCredential(username: account.username, token: token.accessToken)
    }

    func sshCredential(for remoteURLString: String, preferredAccountID: String? = nil) throws -> GitSSHCredential? {
        guard isSSHRemote(remoteURLString) else { return nil }
        guard let identity = GitRemoteIdentityResolver.identity(
            from: remoteURLString,
            knownGitLabHosts: connectedGitLabHosts,
            knownHosts: accounts.map { GitProviderHost(kind: $0.provider, baseURL: $0.hostURL) }
        ) else {
            return nil
        }

        let matchingAccounts = matchingAccounts(for: identity, requiresSSH: true)
        guard !matchingAccounts.isEmpty else { return nil }

        let account: GitProviderAccount
        if let preferredAccountID = preferredAccountID ?? storedPreferredAccountID(for: identity, matching: matchingAccounts) {
            guard let preferred = matchingAccounts.first(where: { $0.id == preferredAccountID }) else {
                throw GitProviderCredentialError.noConnectedAccount(host: normalizedHost(identity.hostURL))
            }
            account = preferred
        } else {
            guard matchingAccounts.count == 1, let onlyAccount = matchingAccounts.first else {
                throw GitProviderCredentialError.multipleMatchingAccounts(host: normalizedHost(identity.hostURL))
            }
            account = onlyAccount
        }

        guard let key = try sshKeyStore?.key(for: account), !key.path.isEmpty else {
            throw GitProviderCredentialError.sshKeyUnavailable(username: account.username)
        }

        return GitSSHCredential(username: sshUsername(from: remoteURLString), keyPath: key.path)
    }

    func matchingAccounts(for remoteURLString: String) -> [GitProviderAccount] {
        guard let identity = remoteIdentity(for: remoteURLString) else { return [] }
        return matchingAccounts(for: identity, requiresSSH: isSSHRemote(remoteURLString))
    }

    func remoteIdentity(for remoteURLString: String) -> GitRemoteIdentity? {
        GitRemoteIdentityResolver.identity(
            from: remoteURLString,
            knownGitLabHosts: connectedGitLabHosts,
            knownHosts: accounts.map { GitProviderHost(kind: $0.provider, baseURL: $0.hostURL) }
        )
    }

    func preferredAccountID(for remoteURLString: String) -> String? {
        guard let identity = remoteIdentity(for: remoteURLString) else { return nil }
        return storedPreferredAccountID(for: identity, matching: matchingAccounts(for: remoteURLString))
    }

    private func storedPreferredAccountID(
        for identity: GitRemoteIdentity,
        matching accounts: [GitProviderAccount]
    ) -> String? {
        let preferenceKey = GitProviderAccountPreferenceKey.make(for: identity)
        guard let accountID = preferredAccountIDsByRemoteIdentity[preferenceKey],
              accounts.contains(where: { $0.id == accountID }) else {
            return nil
        }
        return accountID
    }

    private func matchingAccounts(
        for identity: GitRemoteIdentity,
        requiresSSH: Bool
    ) -> [GitProviderAccount] {
        accounts.filter { account in
            account.provider == identity.provider
                && normalizedHost(account.hostURL) == normalizedHost(identity.hostURL)
                && (!requiresSSH || account.transportProtocol == .ssh)
        }
    }

    private func isHTTPSRemote(_ remoteURLString: String) -> Bool {
        guard let url = URL(string: remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "https"
    }

    private func isSSHRemote(_ remoteURLString: String) -> Bool {
        let trimmed = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@"), trimmed.contains(":") {
            return true
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "ssh"
    }

    private func sshUsername(from remoteURLString: String) -> String {
        let trimmed = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.lowercased() == "ssh", let user = url.user, !user.isEmpty {
            return user
        }
        if let atIndex = trimmed.firstIndex(of: "@") {
            let username = String(trimmed[..<atIndex])
            if !username.isEmpty {
                return username
            }
        }
        return "git"
    }

    private var connectedGitLabHosts: Set<String> {
        Set(accounts.compactMap { account in
            guard account.provider == .gitlab else { return nil }
            return normalizedHost(account.hostURL)
        })
    }

    private func normalizedHost(_ url: URL) -> String {
        GitProviderHost.identityKey(url)
    }
}
