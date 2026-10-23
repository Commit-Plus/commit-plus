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

import CryptoKit
import Foundation

struct GitProviderOAuthSession: Equatable {
    /// Scene routing key for provider OAuth callbacks (`macgit://git-provider/...`).
    nonisolated static let externalEventIdentifier = "macgit://git-provider"

    var provider: GitProviderKind
    var host: GitProviderHost
    var state: String
    var codeVerifier: String
    /// The redirect URI sent to the provider and repeated in the token exchange.
    var redirectURI: URL
    /// Where the callback reaches the app when it differs from `redirectURI`,
    /// for example when a web page forwards the provider redirect to `macgit://`.
    var appCallbackURL: URL? = nil
    var startedAt = Date()

    var callbackURL: URL {
        appCallbackURL ?? redirectURI
    }
}

struct GitProviderOAuthCallback: Equatable {
    var code: String
    var state: String

    static func parse(_ url: URL, for session: GitProviderOAuthSession) throws -> GitProviderOAuthCallback {
        try parse(url, redirectURI: session.callbackURL, expectedState: session.state)
    }

    static func parse(_ url: URL, redirectURI: URL, expectedState: String) throws -> GitProviderOAuthCallback {
        guard matchesRedirect(url, redirectURI: redirectURI),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GitProviderOAuthError.unsupportedCallback
        }

        let queryItems = components.queryItems ?? []
        // Verify state before trusting an error, so a forged link cannot end a pending connection.
        guard let state = queryItems.first(where: { $0.name == "state" })?.value,
              !state.isEmpty else {
            throw GitProviderOAuthError.missingState
        }
        guard state == expectedState else {
            throw GitProviderOAuthError.stateMismatch
        }

        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            if error == "access_denied" {
                throw GitProviderOAuthError.accessDenied
            }
            throw GitProviderOAuthError.providerMessage(
                queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            )
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw GitProviderOAuthError.missingCode
        }

        return GitProviderOAuthCallback(code: code, state: state)
    }

    private static func matchesRedirect(_ callback: URL, redirectURI: URL) -> Bool {
        guard let callbackComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let redirectComponents = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false) else {
            return false
        }

        return callbackComponents.scheme?.lowercased() == redirectComponents.scheme?.lowercased()
            && callbackComponents.host?.lowercased() == redirectComponents.host?.lowercased()
            && callbackComponents.port == redirectComponents.port
            && callbackComponents.path == redirectComponents.path
    }
}

enum GitProviderOAuthError: LocalizedError, Equatable {
    case missingCode
    case missingState
    case stateMismatch
    case unsupportedCallback
    case accessDenied
    case providerMessage(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Authorization was cancelled."
        case .missingCode:
            "The provider callback did not include an authorization code."
        case .missingState:
            "The provider callback did not include the expected state."
        case .stateMismatch:
            "The provider callback could not be verified."
        case .unsupportedCallback:
            "This callback does not belong to the active provider connection."
        case .providerMessage(let message):
            message
        }
    }
}

enum GitProviderPKCE {
    static func generateVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        return base64URLEncoded(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncoded(Data(digest))
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
