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

final class GitHubPullRequestServiceTests: XCTestCase {
    func testListPullRequestsDecodesOpenGitHubPRs() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "number": 12,
                "title": "Add provider-backed pull request read",
                "state": "open",
                "draft": false,
                "html_url": "https://github.com/octocat/Hello-World/pull/12",
                "created_at": "2026-07-01T09:10:11Z",
                "updated_at": "2026-07-06T10:11:12Z",
                "merged_at": null,
                "user": {
                  "login": "octocat",
                  "avatar_url": "https://avatars.githubusercontent.com/u/1"
                },
                "head": {
                  "label": "octocat:feature/pr-read",
                  "ref": "feature/pr-read",
                  "sha": "abc123"
                },
                "base": {
                  "label": "octocat:main",
                  "ref": "main",
                  "sha": "def456"
                }
              }
            ]
            """, headers: [
                "Link": "<https://api.github.com/repos/octocat/Hello-World/pulls?state=open&per_page=30&page=2>; rel=\"next\""
            ]),
            .json(statusCode: 200, body: #"{"state":"success","total_count":2}"#),
            .json(statusCode: 200, body: #"{"mergeable":true}"#)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let page = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken(),
            filter: .open,
            page: 1,
            perPage: 30
        )
        let pullRequests = page.items

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/octocat/Hello-World/pulls?state=open&per_page=30&page=1"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(pullRequests.count, 1)
        XCTAssertEqual(pullRequests[0].number, 12)
        XCTAssertEqual(pullRequests[0].title, "Add provider-backed pull request read")
        XCTAssertEqual(pullRequests[0].state, .open)
        XCTAssertEqual(pullRequests[0].author.username, "octocat")
        XCTAssertEqual(pullRequests[0].author.avatarURL?.absoluteString, "https://avatars.githubusercontent.com/u/1")
        XCTAssertEqual(pullRequests[0].source.ref, "feature/pr-read")
        XCTAssertEqual(pullRequests[0].target.ref, "main")
        XCTAssertEqual(pullRequests[0].webURL.absoluteString, "https://github.com/octocat/Hello-World/pull/12")
        XCTAssertEqual(pullRequests[0].createdAt, ISO8601DateFormatter().date(from: "2026-07-01T09:10:11Z"))
        XCTAssertEqual(pullRequests[0].updatedAt, ISO8601DateFormatter().date(from: "2026-07-06T10:11:12Z"))
        XCTAssertEqual(pullRequests[0].checkState, .success)
        XCTAssertEqual(pullRequests[0].mergeReadiness, .ready)
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.perPage, 30)
        XCTAssertFalse(page.hasPreviousPage)
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            [
                "https://api.github.com/repos/octocat/Hello-World/pulls?state=open&per_page=30&page=1",
                "https://api.github.com/repos/octocat/Hello-World/commits/abc123/status",
                "https://api.github.com/repos/octocat/Hello-World/pulls/12",
            ]
        )
    }

    func testClosedMergedGitHubPRDecodesAsMergedState() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "number": 14,
                "title": "Merged pull request",
                "state": "closed",
                "draft": false,
                "html_url": "https://github.com/octocat/Hello-World/pull/14",
                "created_at": "2026-07-01T09:10:11Z",
                "updated_at": "2026-07-06T10:11:12Z",
                "merged_at": "2026-07-06T10:11:12Z",
                "user": { "login": "octocat", "avatar_url": null },
                "head": { "label": "octocat:merged", "ref": "merged", "sha": null },
                "base": { "label": "octocat:main", "ref": "main", "sha": "def456" }
              }
            ]
            """)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let page = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken(),
            filter: .closed,
            page: 2,
            perPage: 25
        )
        let pullRequests = page.items

        XCTAssertEqual(pullRequests[0].state, .merged)
        XCTAssertEqual(pullRequests[0].mergedAt, ISO8601DateFormatter().date(from: "2026-07-06T10:11:12Z"))
        XCTAssertEqual(
            client.requests.first?.url?.absoluteString,
            "https://api.github.com/repos/octocat/Hello-World/pulls?state=closed&per_page=25&page=2"
        )
        XCTAssertEqual(page.page, 2)
        XCTAssertTrue(page.hasPreviousPage)
    }

    func testCheckRunsProvideBuildStateWhenCommitStatusesAreEmpty() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "number": 15,
                "title": "GitHub Actions pull request",
                "state": "open",
                "draft": false,
                "html_url": "https://github.com/octocat/Hello-World/pull/15",
                "created_at": "2026-07-01T09:10:11Z",
                "updated_at": "2026-07-06T10:11:12Z",
                "merged_at": null,
                "user": { "login": "octocat", "avatar_url": null },
                "head": { "label": "octocat:checks", "ref": "checks", "sha": "fed789" },
                "base": { "label": "octocat:main", "ref": "main", "sha": "def456" }
              }
            ]
            """),
            .json(statusCode: 200, body: #"{"state":"pending","total_count":0}"#),
            .json(statusCode: 200, body: #"{"total_count":1,"check_runs":[{"status":"completed","conclusion":"failure"}]}"#),
            .json(statusCode: 200, body: #"{"mergeable":false}"#)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let page = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken(),
            filter: .all,
            page: 3,
            perPage: 30
        )
        let pullRequests = page.items

        XCTAssertEqual(pullRequests[0].checkState, .failure)
        XCTAssertEqual(pullRequests[0].mergeReadiness, .blocked)
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            [
                "https://api.github.com/repos/octocat/Hello-World/pulls?state=all&per_page=30&page=3",
                "https://api.github.com/repos/octocat/Hello-World/commits/fed789/status",
                "https://api.github.com/repos/octocat/Hello-World/commits/fed789/check-runs",
                "https://api.github.com/repos/octocat/Hello-World/pulls/15",
            ]
        )
    }

    func testPullRequestDetailDecodesBodyAssigneesCommentsAndChangesURL() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            {
              "number": 12,
              "title": "Add provider-backed pull request read",
              "state": "open",
              "draft": false,
              "html_url": "https://github.com/octocat/Hello-World/pull/12",
              "body": "Adds the pull request list and detail view.",
              "created_at": "2026-07-01T09:10:11Z",
              "updated_at": "2026-07-06T10:11:12Z",
              "merged_at": null,
              "user": { "login": "octocat", "avatar_url": null },
              "head": { "label": "octocat:feature/pr-read", "ref": "feature/pr-read", "sha": "abc123" },
              "base": { "label": "octocat:main", "ref": "main", "sha": "def456" },
              "assignees": [
                { "login": "teammate", "avatar_url": "https://avatars.githubusercontent.com/u/2" }
              ],
              "requested_reviewers": [
                { "login": "reviewer", "avatar_url": "https://avatars.githubusercontent.com/u/3" }
              ]
            }
            """),
            .json(statusCode: 200, body: """
            [
              {
                "id": 101,
                "body": "Looks good to me.",
                "created_at": "2026-07-06T11:00:00Z",
                "updated_at": "2026-07-06T11:00:00Z",
                "html_url": "https://github.com/octocat/Hello-World/pull/12#issuecomment-101",
                "user": { "login": "reviewer", "avatar_url": null }
              }
            ]
            """),
            .json(statusCode: 200, body: """
            [
              {
                "id": 4646369306,
                "body": "Please update this section.",
                "submitted_at": "2026-07-06T11:30:00Z",
                "html_url": "https://github.com/octocat/Hello-World/pull/12#pullrequestreview-4646369306",
                "user": { "login": "reviewer", "avatar_url": null }
              }
            ]
            """),
            .json(statusCode: 200, body: """
            [
              {
                "id": 202,
                "body": "Inline note on the implementation.",
                "created_at": "2026-07-06T11:45:00Z",
                "updated_at": "2026-07-06T11:45:00Z",
                "html_url": "https://github.com/octocat/Hello-World/pull/12#discussion_r202",
                "user": { "login": "reviewer", "avatar_url": null }
              }
            ]
            """)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let detail = try await service.pullRequestDetail(
            repository: makeRepository(),
            token: makeToken(),
            number: 12
        )

        XCTAssertEqual(detail.summary.number, 12)
        XCTAssertEqual(detail.body, "Adds the pull request list and detail view.")
        XCTAssertEqual(detail.reviewers.map(\.username), ["reviewer"])
        XCTAssertEqual(detail.assignees.map(\.username), ["teammate"])
        XCTAssertEqual(detail.comments.map(\.body), [
            "Looks good to me.",
            "Please update this section.",
            "Inline note on the implementation.",
        ])
        XCTAssertEqual(detail.changesURL.absoluteString, "https://github.com/octocat/Hello-World/pull/12/files")
        XCTAssertEqual(
            client.requests.map { $0.url?.absoluteString },
            [
                "https://api.github.com/repos/octocat/Hello-World/pulls/12",
                "https://api.github.com/repos/octocat/Hello-World/issues/12/comments",
                "https://api.github.com/repos/octocat/Hello-World/pulls/12/reviews",
                "https://api.github.com/repos/octocat/Hello-World/pulls/12/comments",
            ]
        )
    }

    func testDraftGitHubPRDecodesAsDraftState() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "number": 13,
                "title": "Draft pull request",
                "state": "open",
                "draft": true,
                "html_url": "https://github.com/octocat/Hello-World/pull/13",
                "created_at": "2026-07-01T09:10:11Z",
                "updated_at": "2026-07-06T10:11:12Z",
                "merged_at": null,
                "user": { "login": "octocat", "avatar_url": null },
                "head": { "label": "octocat:draft", "ref": "draft", "sha": null },
                "base": { "label": "octocat:main", "ref": "main", "sha": "def456" }
              }
            ]
            """)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let page = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken(),
            filter: .open,
            page: 1,
            perPage: 30
        )
        let pullRequests = page.items

        XCTAssertEqual(pullRequests[0].state, .draft)
    }

    func testUnauthorizedMapsToReauthorizationRequired() async throws {
        try await assertStatus(
            401,
            mapsTo: .reauthorizationRequired
        )
    }

    func testForbiddenMapsToPermissionDenied() async throws {
        try await assertStatus(
            403,
            mapsTo: .permissionDenied
        )
    }

    func testNotFoundMapsToRepositoryUnavailable() async throws {
        try await assertStatus(
            404,
            mapsTo: .repositoryUnavailable
        )
    }

    func testCreatePullRequestPostsExpectedBody() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 201, body: """
            {
              "number": 22,
              "title": "Add provider-backed pull request actions",
              "state": "open",
              "draft": false,
              "html_url": "https://github.com/octocat/Hello-World/pull/22",
              "created_at": "2026-07-08T00:10:11Z",
              "updated_at": "2026-07-08T00:10:11Z",
              "merged_at": null,
              "user": { "login": "octocat", "avatar_url": null },
              "head": { "label": "octocat:feature/pr-actions", "ref": "feature/pr-actions", "sha": "abc123" },
              "base": { "label": "octocat:main", "ref": "main", "sha": "def456" }
            }
            """)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let result = try await service.createPullRequest(
            makeDraft(),
            token: makeToken()
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/octocat/Hello-World/pulls"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["title"], "Add provider-backed pull request actions")
        XCTAssertEqual(json["body"], "Implements create, comment, and checkout actions.")
        XCTAssertEqual(json["head"], "feature/pr-actions")
        XCTAssertEqual(json["base"], "main")
        XCTAssertEqual(result.summary.number, 22)
        XCTAssertEqual(result.summary.title, "Add provider-backed pull request actions")
    }

    func testPullRequestParticipantsLoadsAssignableUsers() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              { "login": "reviewer", "avatar_url": "https://example.com/reviewer.png" },
              { "login": "assignee", "avatar_url": null }
            ]
            """)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let participants = try await service.pullRequestParticipants(
            repository: makeRepository(),
            token: makeToken()
        )

        XCTAssertEqual(participants.map(\.username), ["reviewer", "assignee"])
        XCTAssertEqual(
            client.requests.first?.url?.absoluteString,
            "https://api.github.com/repos/octocat/Hello-World/assignees?per_page=100&page=1"
        )
    }

    func testCreatePullRequestAddsReviewersAndAssigneesAfterCreation() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 201, body: """
            {
              "number": 22,
              "title": "Add provider-backed pull request actions",
              "state": "open",
              "draft": false,
              "html_url": "https://github.com/octocat/Hello-World/pull/22",
              "created_at": "2026-07-08T00:10:11Z",
              "updated_at": "2026-07-08T00:10:11Z",
              "merged_at": null,
              "user": { "login": "octocat", "avatar_url": null },
              "head": { "label": "octocat:feature/pr-actions", "ref": "feature/pr-actions", "sha": "abc123" },
              "base": { "label": "octocat:main", "ref": "main", "sha": "def456" }
            }
            """),
            .json(statusCode: 201, body: "{}"),
            .json(statusCode: 201, body: "{}"),
        ])
        let service = GitHubPullRequestService(httpClient: client)
        var draft = try makeDraft()
        draft.reviewers = [PullRequestParticipant(id: "reviewer", username: "reviewer", avatarURL: nil)]
        draft.assignees = [PullRequestParticipant(id: "assignee", username: "assignee", avatarURL: nil)]

        let result = try await service.createPullRequest(draft, token: makeToken())

        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(client.requests.map { $0.url?.path }, [
            "/repos/octocat/Hello-World/pulls",
            "/repos/octocat/Hello-World/pulls/22/requested_reviewers",
            "/repos/octocat/Hello-World/issues/22/assignees",
        ])
        let reviewerBody = try XCTUnwrap(client.requests[1].httpBody)
        let reviewerJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: reviewerBody) as? [String: [String]])
        XCTAssertEqual(reviewerJSON["reviewers"], ["reviewer"])
        let assigneeBody = try XCTUnwrap(client.requests[2].httpBody)
        let assigneeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: assigneeBody) as? [String: [String]])
        XCTAssertEqual(assigneeJSON["assignees"], ["assignee"])
    }

    func testPullRequestChangesLoadsAllPagesAndDecodesPatches() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "filename": "macgit/App.swift",
                "status": "modified",
                "additions": 2,
                "deletions": 1,
                "patch": "@@ -1,2 +1,3 @@\\n-old\\n+new\\n context"
              }
            ]
            """, headers: [
                "Link": "<https://api.github.com/repos/octocat/Hello-World/pulls/12/files?per_page=100&page=2>; rel=\"next\""
            ]),
            .json(statusCode: 200, body: """
            [
              {
                "filename": "Assets/logo.png",
                "previous_filename": "Assets/old-logo.png",
                "status": "renamed",
                "additions": 0,
                "deletions": 0,
                "patch": null
              }
            ]
            """)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let files = try await service.pullRequestChanges(
            repository: makeRepository(),
            token: makeToken(),
            number: 12
        )

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].path, "macgit/App.swift")
        XCTAssertEqual(files[0].status, .modified)
        XCTAssertEqual(files[0].additions, 2)
        XCTAssertEqual(files[0].deletions, 1)
        XCTAssertEqual(files[0].diffHunks.count, 1)
        XCTAssertEqual(files[1].previousPath, "Assets/old-logo.png")
        XCTAssertEqual(files[1].status, .renamed)
        XCTAssertNil(files[1].patch)
        XCTAssertNotNil(files[1].patchUnavailableReason)
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, [
            "https://api.github.com/repos/octocat/Hello-World/pulls/12/files?per_page=100&page=1",
            "https://api.github.com/repos/octocat/Hello-World/pulls/12/files?per_page=100&page=2",
        ])
    }

    func testCreatePullRequestPermissionDeniedMapsToUserFacingError() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 403, body: #"{"message":"Resource not accessible by integration"}"#)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        do {
            _ = try await service.createPullRequest(makeDraft(), token: makeToken())
            XCTFail("Expected createPullRequest to throw")
        } catch {
            XCTAssertEqual(
                error as? PullRequestProviderError,
                .providerMessage("The connected account does not have permission to modify pull requests.")
            )
        }
    }

    func testCreatePullRequestDuplicateValidationExplainsPossibleExistingPullRequest() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 422, body: #"{"message":"Validation Failed","errors":[{"resource":"PullRequest","code":"custom","message":"A pull request already exists for feature/pr-actions:main"}]}"#)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        do {
            _ = try await service.createPullRequest(makeDraft(), token: makeToken())
            XCTFail("Expected createPullRequest to throw")
        } catch {
            XCTAssertEqual(
                error as? PullRequestProviderError,
                .providerMessage("GitHub couldn't create this pull request. A pull request from this branch to the selected target already exists. Check the repository's pull requests, or choose a different target branch.")
            )
        }
    }

    func testCreatePullRequestOtherValidationFailurePreservesGeneralError() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 422, body: #"{"message":"Validation Failed","errors":[{"resource":"PullRequest","code":"custom","message":"No commits between main and feature/pr-actions"}]}"#)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        do {
            _ = try await service.createPullRequest(makeDraft(), token: makeToken())
            XCTFail("Expected createPullRequest to throw")
        } catch {
            XCTAssertEqual(error as? PullRequestProviderError, .providerMessage("Validation Failed"))
        }
    }

    func testMergePullRequestUsesProviderMergeEndpoint() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: #"{"merged":true,"message":"Pull Request successfully merged"}"#)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        try await service.mergePullRequest(
            makeSummary(number: 22),
            repository: makeRepository(),
            token: makeToken()
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/octocat/Hello-World/pulls/22/merge"
        )
    }

    func testCreateCommentPostsExpectedBody() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 201, body: """
            {
              "id": 101,
              "body": "Looks good to me.",
              "created_at": "2026-07-08T01:00:00Z",
              "updated_at": "2026-07-08T01:00:00Z",
              "html_url": "https://github.com/octocat/Hello-World/pull/22#issuecomment-101",
              "user": { "login": "reviewer", "avatar_url": null }
            }
            """)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        try await service.createComment(
            body: "Looks good to me.",
            on: makeSummary(number: 22),
            repository: makeRepository(),
            token: makeToken()
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/octocat/Hello-World/issues/22/comments"
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["body": "Looks good to me."])
    }

    private func assertStatus(
        _ statusCode: Int,
        mapsTo expectedError: PullRequestProviderError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: statusCode, body: #"{"message":"request failed"}"#)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        do {
            _ = try await service.listPullRequests(
                repository: makeRepository(),
                token: makeToken(),
                filter: .open,
                page: 1,
                perPage: 30
            )
            XCTFail("Expected listPullRequests to throw", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PullRequestProviderError, expectedError, file: file, line: line)
        }
    }

    private func makeRepository() -> GitRepositoryIdentity {
        GitRepositoryIdentity(
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            owner: "octocat",
            name: "Hello-World"
        )
    }

    private func makeDraft() throws -> PullRequestDraft {
        try PullRequestDraft(
            repository: makeRepository(),
            sourceBranch: "feature/pr-actions",
            targetBranch: "main",
            title: "Add provider-backed pull request actions",
            body: "Implements create, comment, and checkout actions."
        )
    }

    private func makeSummary(number: Int) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Add provider-backed pull request actions",
            state: .open,
            author: PullRequestAuthor(username: "octocat", avatarURL: nil),
            source: PullRequestBranchRef(label: "octocat:feature/pr-actions", ref: "feature/pr-actions", sha: "abc123"),
            target: PullRequestBranchRef(label: "octocat:main", ref: "main", sha: "def456"),
            webURL: URL(string: "https://github.com/octocat/Hello-World/pull/\(number)")!,
            createdAt: Date(timeIntervalSince1970: 1_783_468_211),
            updatedAt: Date(timeIntervalSince1970: 1_783_468_211)
        )
    }

    private func makeToken() -> GitProviderToken {
        GitProviderToken(
            accessToken: "secret-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "bearer"
        )
    }
}

private final class StubPullRequestHTTPClient: GitProviderHTTPClient {
    struct Response {
        var statusCode: Int
        var data: Data
        var headers: [String: String]

        static func json(statusCode: Int, body: String, headers: [String: String] = [:]) -> Response {
            Response(statusCode: statusCode, data: Data(body.utf8), headers: headers)
        }
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        let httpResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: response.headers
            )
        )
        return (response.data, httpResponse)
    }
}
