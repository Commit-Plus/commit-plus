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

protocol PullRequestProviding {
    func pullRequestParticipants(
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> [PullRequestParticipant]

    func listPullRequests(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        filter: PullRequestListFilter,
        page: Int,
        perPage: Int
    ) async throws -> PullRequestListPage

    func openPullRequest(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        sourceBranch: String
    ) async throws -> PullRequestSummary?

    func pullRequestDetail(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> PullRequestDetail

    func pullRequestChanges(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> [PullRequestChangedFile]

    func createPullRequest(
        _ draft: PullRequestDraft,
        token: GitProviderToken
    ) async throws -> PullRequestCreationResult

    func createComment(
        body: String,
        on pullRequest: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws

    func mergePullRequest(
        _ pullRequest: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws
}

extension PullRequestProviding {
    func pullRequestParticipants(
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> [PullRequestParticipant] {
        _ = repository
        _ = token
        return []
    }

    func openPullRequest(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        sourceBranch: String
    ) async throws -> PullRequestSummary? {
        var page = 1
        while true {
            let result = try await listPullRequests(
                repository: repository,
                token: token,
                filter: .all,
                page: page,
                perPage: 100
            )
            if let pullRequest = result.items.filter({ $0.source.ref == sourceBranch }).preferringOpenPullRequest {
                return pullRequest
            }
            guard result.hasNextPage else { return nil }
            page += 1
        }
    }
}

extension Array where Element == PullRequestSummary {
    /// The first open or draft pull request, falling back to the first one (most recently updated
    /// when the provider sorts by update time) so a branch's active PR wins over closed/merged ones.
    var preferringOpenPullRequest: PullRequestSummary? {
        first { PullRequestListFilter.open.includes($0.state) } ?? first
    }
}

enum PullRequestProviderError: LocalizedError, Equatable {
    case reauthorizationRequired
    case permissionDenied
    case repositoryUnavailable
    case unsupportedProvider
    case providerMessage(String)

    var errorDescription: String? {
        switch self {
        case .reauthorizationRequired:
            "The Git provider account needs to be connected again."
        case .permissionDenied:
            "The connected account does not have permission to read pull requests."
        case .repositoryUnavailable:
            "The repository is unavailable from the connected provider account."
        case .unsupportedProvider:
            "This provider does not support pull request loading yet."
        case .providerMessage(let message):
            message
        }
    }
}
