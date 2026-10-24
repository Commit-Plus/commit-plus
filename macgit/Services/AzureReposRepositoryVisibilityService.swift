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

/// Reads `project.visibility` from the repository API, which needs only the Code (Read)
/// scope; the projects API would need Project & Team (Read).
struct AzureReposRepositoryVisibilityService: RepositoryVisibilityProviding {
    private let httpClient: GitProviderHTTPClient

    init(httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient()) {
        self.httpClient = httpClient
    }

    func visibility(
        for repository: GitRepositoryIdentity,
        token: GitProviderToken?
    ) async throws -> RepositoryVisibility {
        guard repository.provider == .azureDevOps else {
            throw RepositoryVisibilityProviderError.unsupportedProvider
        }
        let url: URL
        do {
            url = try AzureReposPullRequestService().repositoryURL(repository, path: [])
        } catch {
            throw RepositoryVisibilityProviderError.invalidResponse
        }

        var request: URLRequest
        if let token, !token.accessToken.isEmpty {
            request = AzureDevOpsProviderAuthService.apiRequest(url: url, token: token)
        } else {
            request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Suppress", forHTTPHeaderField: "X-TFS-FedAuthRedirect")
        }

        let (data, response) = try await httpClient.data(for: request)
        if response.statusCode == 404 {
            throw RepositoryVisibilityProviderError.repositoryUnavailable
        }
        // A private project answers anonymous calls with 401, 203, or a sign-in page.
        if AzureDevOpsProviderAuthService.isRejected(response) || response.statusCode == 403 {
            throw RepositoryVisibilityProviderError.authorizationRequired
        }
        guard (200..<300).contains(response.statusCode),
              let payload = try? JSONDecoder().decode(AzureRepositoryVisibilityPayload.self, from: data) else {
            throw RepositoryVisibilityProviderError.invalidResponse
        }
        switch payload.project.visibility.lowercased() {
        case "public":
            return .public
        case "private", "organization":
            return .private
        default:
            throw RepositoryVisibilityProviderError.invalidResponse
        }
    }
}

private struct AzureRepositoryVisibilityPayload: Decodable {
    struct Project: Decodable {
        let visibility: String
    }

    let project: Project
}
