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

struct GitLabRepositoryVisibilityService: RepositoryVisibilityProviding {
    private let httpClient: GitProviderHTTPClient

    init(httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient()) {
        self.httpClient = httpClient
    }

    func visibility(
        for repository: GitRepositoryIdentity,
        token: GitProviderToken?
    ) async throws -> RepositoryVisibility {
        guard repository.provider == .gitlab else {
            throw RepositoryVisibilityProviderError.unsupportedProvider
        }

        let projectPath = "\(repository.owner)/\(repository.name)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encodedPath = projectPath.addingPercentEncoding(withAllowedCharacters: allowed),
              var components = URLComponents(url: repository.hostURL, resolvingAgainstBaseURL: false) else {
            throw RepositoryVisibilityProviderError.invalidResponse
        }
        components.percentEncodedPath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? "/api/v4/projects/\(encodedPath)"
            : "/" + components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v4/projects/\(encodedPath)"
        guard let url = components.url else {
            throw RepositoryVisibilityProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.accessToken.isEmpty {
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await httpClient.data(for: request)
        switch response.statusCode {
        case 200..<300:
            guard let payload = try? JSONDecoder().decode(GitLabRepositoryVisibilityPayload.self, from: data) else {
                throw RepositoryVisibilityProviderError.invalidResponse
            }
            switch payload.visibility {
            case "public":
                return .public
            case "private", "internal":
                return .private
            default:
                throw RepositoryVisibilityProviderError.invalidResponse
            }
        case 401, 403:
            throw RepositoryVisibilityProviderError.authorizationRequired
        case 404:
            throw RepositoryVisibilityProviderError.repositoryUnavailable
        default:
            throw RepositoryVisibilityProviderError.invalidResponse
        }
    }
}

private struct GitLabRepositoryVisibilityPayload: Decodable {
    let visibility: String
}
