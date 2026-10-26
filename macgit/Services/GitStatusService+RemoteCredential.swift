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
        guard let injection else {
            return try await runGit(arguments: arguments, in: repositoryURL)
        }
        do {
            return try await runGit(
                arguments: arguments,
                in: repositoryURL,
                environment: injection.environment
            )
        } catch {
            guard let host = injection.connectedAccountHost,
                  Self.isRemoteAuthenticationRejection(error.localizedDescription) else {
                throw error
            }
            guard userDefaults.object(forKey: Self.credentialHelperFallbackKey) as? Bool ?? true else {
                throw GitError.commandFailed(
                    error.localizedDescription + "\n\n" + Self.connectedAccountAccessHint(host: host, fallbackEnabled: false)
                )
            }
            // Git rejects credentials before transferring anything, so retrying with the user's own helpers is safe.
            do {
                return try await runGit(
                    arguments: arguments,
                    in: repositoryURL,
                    environment: GitCredentialInjection.configuredGitHelpers().environment
                )
            } catch let fallbackError {
                guard Self.isRemoteAuthenticationRejection(fallbackError.localizedDescription) else {
                    throw fallbackError
                }
                throw GitError.commandFailed(
                    fallbackError.localizedDescription + "\n\n" + Self.connectedAccountAccessHint(host: host, fallbackEnabled: true)
                )
            }
        }
    }

    nonisolated static func isRemoteAuthenticationRejection(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return [
            "repository not found",
            "authentication failed",
            "invalid username or password",
            "terminal prompts disabled",
            "could not read username",
            "the requested url returned error: 401",
            "the requested url returned error: 403",
            "permission to ",
        ].contains { lowercased.contains($0) }
    }

    nonisolated static func connectedAccountAccessHint(host: String, fallbackEnabled: Bool) -> String {
        var hint = fallbackEnabled
            ? "Commit+ tried your connected \(host) account and your Git credential helpers, but neither can access this repository. "
            : "Commit+ used your connected \(host) account, which cannot access this repository. "
        hint += "If it is private, check that the connected account has access to it."
        if host.lowercased() == "github.com" {
            hint += " For organization repositories, the organization may restrict third-party apps: open GitHub Settings → Applications → Authorized OAuth Apps → Commit+, then grant or request access for the organization."
        }
        if !fallbackEnabled {
            hint += "\n\nTo retry with your Git credential helpers (such as GitHub CLI or macOS Keychain), turn on “Fall back to Git credential helpers” in Settings → Git."
        }
        return hint
    }

    func credentialInjection(
        for remote: String,
        in repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver?,
        credentialInjector: GitCredentialInjecting,
        sshCredentialInjector: GitSSHCredentialInjecting
    ) async throws -> GitCredentialInjection? {
        guard let credentialResolver else { return .configuredGitHelpers() }
        let remoteURLString: String
        if credentialResolver.remoteIdentity(for: remote) != nil {
            remoteURLString = remote
        } else {
            remoteURLString = await remoteURL(remote: remote, in: repositoryURL)
        }
        guard let credential = try await remoteCredential(
            for: remoteURLString,
            credentialResolver: credentialResolver
        ) else {
            return .configuredGitHelpers()
        }
        var result = try injection(
            for: credential,
            credentialInjector: credentialInjector,
            sshCredentialInjector: sshCredentialInjector
        )
        if case .https = credential, let url = URLComponents(string: remoteURLString), let host = url.host {
            result.environment["MACGIT_GIT_CREDENTIAL_HOST"] = host + (url.port.map { ":\($0)" } ?? "")
            result.environment["MACGIT_GIT_CREDENTIAL_SCHEME"] = url.scheme ?? "https"
            result.connectedAccountHost = host
        }
        return result
    }

    func remoteCredential(
        for remoteURLString: String,
        credentialResolver: GitProviderCredentialResolver
    ) async throws -> RemoteGitCredential? {
        if let credential = try await credentialResolver.credential(for: remoteURLString) {
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
