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

import XCTest
@testable import macgit

@MainActor
final class RepositoryAIPullRequestContextServiceTests: XCTestCase {
    func testContextIsBoundedAndNeverIncludesCredentials() async throws {
        let provider = ReadOnlyPullRequestProvider()
        let repository = GitRepositoryIdentity(
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            owner: "octocat",
            name: "Hello-World"
        )
        let token = GitProviderToken(accessToken: "secret-token", refreshToken: "refresh-secret", expiresAt: nil, tokenType: "bearer")
        let context = try await RepositoryAIPullRequestContextService(provider: provider).load(
            repository: repository,
            token: token,
            number: 12
        )
        let result = context.toolResult(characterBudget: 1_500)

        XCTAssertEqual(provider.detailNumber, 12)
        XCTAssertEqual(provider.changesNumber, 12)
        XCTAssertEqual(result.toolName, "pull_request_context")
        XCTAssertTrue(result.content.contains("Number: #12"))
        XCTAssertFalse(result.content.contains("secret-token"))
        XCTAssertFalse(result.content.contains("refresh-secret"))
        XCTAssertFalse(result.content.contains("Authorization"))
    }
}

@MainActor
private final class ReadOnlyPullRequestProvider: PullRequestProviding {
    private(set) var detailNumber: Int?
    private(set) var changesNumber: Int?

    func pullRequestParticipants(repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> [PullRequestParticipant] { [] }
    func listPullRequests(repository: GitRepositoryIdentity, token: GitProviderToken, filter: PullRequestListFilter, page: Int, perPage: Int) async throws -> PullRequestListPage {
        PullRequestListPage(items: [], page: page, perPage: perPage, hasPreviousPage: false, hasNextPage: false)
    }
    func pullRequestDetail(repository: GitRepositoryIdentity, token: GitProviderToken, number: Int) async throws -> PullRequestDetail {
        detailNumber = number
        return PullRequestDetail(
            summary: summary(number: number),
            body: "Provider supplied body",
            assignees: [],
            comments: [],
            changesURL: URL(string: "https://github.com/octocat/Hello-World/pull/\(number)/files")!
        )
    }
    func pullRequestChanges(repository: GitRepositoryIdentity, token: GitProviderToken, number: Int) async throws -> [PullRequestChangedFile] {
        changesNumber = number
        return [PullRequestChangedFile(path: "Example.swift", previousPath: nil, status: .modified, additions: 2, deletions: 1, patch: "@@ -1 +1 @@", patchUnavailableReason: nil)]
    }
    func createPullRequest(_ draft: PullRequestDraft, token: GitProviderToken) async throws -> PullRequestCreationResult { fatalError("Not used") }
    func createComment(body: String, on pullRequest: PullRequestSummary, repository: GitRepositoryIdentity, token: GitProviderToken) async throws { fatalError("Not used") }
    func mergePullRequest(_ pullRequest: PullRequestSummary, repository: GitRepositoryIdentity, token: GitProviderToken) async throws { fatalError("Not used") }

    private func summary(number: Int) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Read-only PR",
            state: .open,
            author: PullRequestAuthor(username: "octocat", avatarURL: nil),
            source: PullRequestBranchRef(label: "feature", ref: "feature", sha: "head-sha"),
            target: PullRequestBranchRef(label: "main", ref: "main", sha: "base-sha"),
            webURL: URL(string: "https://github.com/octocat/Hello-World/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }
}
