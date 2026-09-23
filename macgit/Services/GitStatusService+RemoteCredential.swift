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

extension GitStatusService {
    func runRemoteGit(
        arguments: [String],
        in repositoryURL: URL,
        injection: GitCredentialInjection?
    ) async throws -> String {
        if let injection {
            return try await runGit(
                arguments: arguments,
                in: repositoryURL,
                environment: injection.environment
            )
        }
        return try await runGit(arguments: arguments, in: repositoryURL)
    }

    func credentialInjection(
        for remote: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?,
        credentialInjector: GitCredentialInjecting,
        sshCredentialInjector: GitSSHCredentialInjecting
    ) async throws -> GitCredentialInjection? {
        guard let credentialResolver else { return nil }
        let remoteURLString: String
        if GitRemoteIdentityResolver.identity(
            from: remote,
            knownGitLabHosts: Set(credentialResolver.accounts.compactMap { account in
                guard account.provider == .gitlab else { return nil }
                return account.hostURL.host(percentEncoded: false)?.lowercased()
            })
        ) != nil {
            remoteURLString = remote
        } else {
            remoteURLString = await remoteURL(remote: remote, in: repositoryURL)
        }
        guard let credential = try remoteCredential(
            for: remoteURLString,
            credentialResolver: credentialResolver
        ) else {
            return nil
        }
        var result = try injection(
            for: credential,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
        if case .https = credential, let url = URLComponents(string: remoteURLString), let host = url.host {
            result.environment["MACGIT_GIT_CREDENTIAL_HOST"] = host + (url.port.map { ":\($0)" } ?? "")
            result.environment["MACGIT_GIT_CREDENTIAL_SCHEME"] = url.scheme ?? "https"
        }
        return result
    }

    func remoteCredential(
        for remoteURLString: String,
        credentialResolver: GitProviderCredentialResolver
    ) throws -> RemoteGitCredential? {
        if let credential = try credentialResolver.credential(for: remoteURLString) {
            return .https(credential)
        }
        if let credential = try credentialResolver.sshCredential(for: remoteURLString) {
            return .ssh(credential)
        }
        return nil
    }

    func injection(
        for credential: RemoteGitCredential,
        credentialInjector: GitCredentialInjecting,
        sshCredentialInjector: GitSSHCredentialInjecting
    ) throws -> GitCredentialInjection {
        switch credential {
        case .https(let credential):
            return try credentialInjector.injection(for: credential)
        case .ssh(let credential):
            return try sshCredentialInjector.injection(for: credential)
        }
    }
}

enum RemoteGitCredential: Equatable {
    case https(GitCredential)
    case ssh(GitSSHCredential)
}
