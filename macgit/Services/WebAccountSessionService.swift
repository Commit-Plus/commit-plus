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

import FirebaseFunctions
import Foundation

@MainActor
protocol WebAccountSessionProviding {
    func signInURL(for destination: WebAccountDestination) async throws -> URL
}

enum WebAccountSessionError: LocalizedError {
    case invalidBaseURL
    case invalidServerResponse
    case unableToOpenBrowser

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The Commit+ website URL is not configured correctly."
        case .invalidServerResponse:
            "Commit+ Cloud returned an invalid web sign-in response."
        case .unableToOpenBrowser:
            "Commit+ could not open your web browser."
        }
    }
}

enum CommitPlusWebConfiguration {
    nonisolated static func baseURL(bundle: Bundle = .main) throws -> URL {
        try configuredURL(forInfoDictionaryKey: "CommitPlusWebBaseURL", bundle: bundle)
    }

    nonisolated static func documentationURL(bundle: Bundle = .main) throws -> URL {
        try configuredURL(forInfoDictionaryKey: "CommitPlusDocsBaseURL", bundle: bundle)
    }

    nonisolated static func contactURL(bundle: Bundle = .main) throws -> URL {
        try baseURL(bundle: bundle).appending(path: "contact")
    }

    nonisolated static func reportIssueURL() throws -> URL {
        guard let url = URL(string: "https://github.com/Commit-Plus/commit-plus/issues/new") else {
            throw WebAccountSessionError.invalidBaseURL
        }
        return url
    }

    nonisolated private static func configuredURL(
        forInfoDictionaryKey key: String,
        bundle: Bundle
    ) throws -> URL {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: rawValue),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw WebAccountSessionError.invalidBaseURL
        }
        return url
    }
}

enum WebAccountSignInURLBuilder {
    nonisolated static func signInURL(
        baseURL: URL,
        customToken: String,
        destination: WebAccountDestination
    ) throws -> URL {
        guard !customToken.isEmpty,
              var components = URLComponents(
                url: baseURL.appending(path: "session"),
                resolvingAgainstBaseURL: false
              ) else {
            throw WebAccountSessionError.invalidServerResponse
        }

        components.queryItems = [
            URLQueryItem(name: "next", value: destination.path)
        ]
        components.fragment = "token=\(customToken)"
        guard let url = components.url else {
            throw WebAccountSessionError.invalidServerResponse
        }
        return url
    }
}

@MainActor
final class FirebaseWebAccountSessionService: WebAccountSessionProviding {
    private let functions: Functions
    private let baseURLProvider: () throws -> URL

    init(
        functions: Functions = .functions(),
        baseURLProvider: @escaping () throws -> URL = { try CommitPlusWebConfiguration.baseURL() }
    ) {
        self.functions = functions
        self.baseURLProvider = baseURLProvider
    }

    func signInURL(for destination: WebAccountDestination) async throws -> URL {
        let result = try await functions.httpsCallable("createWebSignInToken").call()
        guard let payload = result.data as? [String: Any],
              let customToken = payload["customToken"] as? String else {
            throw WebAccountSessionError.invalidServerResponse
        }

        return try WebAccountSignInURLBuilder.signInURL(
            baseURL: baseURLProvider(),
            customToken: customToken,
            destination: destination
        )
    }
}
