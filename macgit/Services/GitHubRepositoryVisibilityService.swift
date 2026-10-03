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

struct GitHubRepositoryVisibilityService: RepositoryVisibilityProviding {
    private let httpClient: GitProviderHTTPClient
    private let apiBaseURL: URL

    init(
        httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient(),
        apiBaseURL: URL = URL(string: "https://api.github.com")!
    ) {
        self.httpClient = httpClient
        self.apiBaseURL = apiBaseURL
    }

    func visibility(
        for repository: GitRepositoryIdentity,
        token: GitProviderToken?
    ) async throws -> RepositoryVisibility {
        guard repository.provider == .github else {
            throw RepositoryVisibilityProviderError.unsupportedProvider
        }

        let host = GitProviderHost(kind: .github, baseURL: repository.hostURL)
        let url = (host.normalized.baseURL == GitProviderHost.githubDotCom.baseURL ? apiBaseURL : host.apiURL)
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token, !token.accessToken.isEmpty {
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await httpClient.data(for: request)
        switch response.statusCode {
        case 200..<300:
            guard let payload = try? JSONDecoder().decode(GitHubRepositoryVisibilityPayload.self, from: data) else {
                throw RepositoryVisibilityProviderError.invalidResponse
            }
            return payload.isPrivate ? .private : .public
        case 401, 403:
            throw RepositoryVisibilityProviderError.authorizationRequired
        case 404:
            throw RepositoryVisibilityProviderError.repositoryUnavailable
        default:
            throw RepositoryVisibilityProviderError.invalidResponse
        }
    }
}

private struct GitHubRepositoryVisibilityPayload: Decodable {
    let isPrivate: Bool

    private enum CodingKeys: String, CodingKey {
        case isPrivate = "private"
    }
}
