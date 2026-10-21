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

final class GitLabPullRequestServiceTests: XCTestCase {
    func testListMergeRequestsDecodesOpenItems() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "iid": 7,
                "title": "Add GitLab merge requests",
                "state": "opened",
                "draft": false,
                "web_url": "https://gitlab.com/group/subgroup/project/-/merge_requests/7",
                "created_at": "2026-07-01T09:10:11Z",
                "updated_at": "2026-07-06T10:11:12Z",
                "merged_at": null,
                "source_branch": "feature/gitlab-mrs",
                "target_branch": "main",
                "sha": "abc123",
                "author": {
                  "username": "tanuki",
                  "avatar_url": "https://gitlab.com/uploads/-/system/user/avatar/42/avatar.png"
                }
              }
            ]
            """, headers: [
                "X-Next-Page": "2"
            ])
        ])
        let service = GitLabPullRequestService(httpClient: client)

        let page = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken(),
            filter: .open,
            page: 1,
            perPage: 30
        )
        let mergeRequests = page.items

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests?state=opened&per_page=30&page=1"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(mergeRequests.count, 1)
        XCTAssertEqual(mergeRequests[0].number, 7)
        XCTAssertEqual(mergeRequests[0].title, "Add GitLab merge requests")
        XCTAssertEqual(mergeRequests[0].state, .open)
        XCTAssertEqual(mergeRequests[0].author.username, "tanuki")
        XCTAssertEqual(mergeRequests[0].source.ref, "feature/gitlab-mrs")
        XCTAssertEqual(mergeRequests[0].source.sha, "abc123")
        XCTAssertEqual(mergeRequests[0].target.ref, "main")
        XCTAssertEqual(mergeRequests[0].webURL.absoluteString, "https://gitlab.com/group/subgroup/project/-/merge_requests/7")
        XCTAssertTrue(page.hasNextPage)
        XCTAssertFalse(page.hasPreviousPage)
    }

    func testOpenPullRequestFiltersBySourceBranch() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "iid": 7,
                "title": "Add GitLab merge requests",
                "state": "opened",
                "draft": false,
                "web_url": "https://gitlab.com/group/subgroup/project/-/merge_requests/7",
                "created_at": "2026-07-01T09:10:11Z",
                "updated_at": "2026-07-06T10:11:12Z",
                "merged_at": null,
                "source_branch": "feature/gitlab-mrs",
                "target_branch": "main",
                "sha": "abc123",
                "author": { "username": "tanuki", "avatar_url": null }
              }
            ]
            """)
        ])
        let service = GitLabPullRequestService(httpClient: client)

        let pullRequest = try await service.openPullRequest(
            repository: makeRepository(),
            token: makeToken(),
            sourceBranch: "feature/gitlab-mrs"
        )

        let request = try XCTUnwrap(client.requests.first)
        let queryItems = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") }), [
            "state": "opened",
            "source_branch": "feature/gitlab-mrs",
            "per_page": "1",
        ])
        XCTAssertEqual(pullRequest?.number, 7)
    }

    func testCreateMergeRequestPostsExpectedBody() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 201, body: """
            {
              "iid": 8,
              "title": "Add GitLab action",
              "state": "opened",
              "draft": false,
              "web_url": "https://gitlab.com/group/subgroup/project/-/merge_requests/8",
              "created_at": "2026-07-08T00:10:11Z",
              "updated_at": "2026-07-08T00:10:11Z",
              "merged_at": null,
              "source_branch": "feature/gitlab-action",
              "target_branch": "main",
              "sha": "def456",
              "author": { "username": "tanuki", "avatar_url": null }
            }
            """)
        ])
        let service = GitLabPullRequestService(httpClient: client)

        let result = try await service.createPullRequest(
            makeDraft(),
            token: makeToken()
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["title"], "Add GitLab action")
        XCTAssertEqual(json["description"], "Implements GitLab merge request actions.")
        XCTAssertEqual(json["source_branch"], "feature/gitlab-action")
        XCTAssertEqual(json["target_branch"], "main")
        XCTAssertEqual(result.summary.number, 8)
        XCTAssertEqual(result.summary.title, "Add GitLab action")
    }

    func testPullRequestParticipantsLoadsProjectMembers() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              { "id": 7, "username": "reviewer", "avatar_url": null },
              { "id": 9, "username": "assignee", "avatar_url": "https://example.com/assignee.png" }
            ]
            """)
        ])
        let service = GitLabPullRequestService(httpClient: client)

        let participants = try await service.pullRequestParticipants(
            repository: makeRepository(),
            token: makeToken()
        )

        XCTAssertEqual(participants.map(\.providerUserID), [7, 9])
        XCTAssertEqual(
            client.requests.first?.url?.absoluteString,
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/members/all?per_page=100&page=1"
        )
    }

    func testCreateMergeRequestIncludesReviewerAndAssigneeIDs() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 201, body: """
            {
              "iid": 8,
              "title": "Add GitLab action",
              "state": "opened",
              "draft": false,
              "web_url": "https://gitlab.com/group/subgroup/project/-/merge_requests/8",
              "created_at": "2026-07-08T00:10:11Z",
              "updated_at": "2026-07-08T00:10:11Z",
              "merged_at": null,
              "source_branch": "feature/gitlab-action",
              "target_branch": "main",
              "sha": "def456",
              "author": { "username": "tanuki", "avatar_url": null }
            }
            """)
        ])
        let service = GitLabPullRequestService(httpClient: client)
        var draft = try makeDraft()
        draft.reviewers = [PullRequestParticipant(id: "7", username: "reviewer", avatarURL: nil, providerUserID: 7)]
        draft.assignees = [PullRequestParticipant(id: "9", username: "assignee", avatarURL: nil, providerUserID: 9)]

        _ = try await service.createPullRequest(draft, token: makeToken())

        let body = try XCTUnwrap(client.requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["reviewer_ids"] as? [Int], [7])
        XCTAssertEqual(json["assignee_ids"] as? [Int], [9])
    }

    func testPullRequestDetailDecodesFractionalSecondDates() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            {
              "iid": 7,
              "title": "Add GitLab merge requests",
              "description": "Preserve GitLab detail markdown.",
              "state": "opened",
              "draft": false,
              "web_url": "https://gitlab.com/group/subgroup/project/-/merge_requests/7",
              "created_at": "2026-07-01T09:10:11.163Z",
              "updated_at": "2026-07-06T10:11:12.134Z",
              "merged_at": null,
              "source_branch": "feature/gitlab-mrs",
              "target_branch": "main",
              "sha": "abc123",
              "author": { "username": "tanuki", "avatar_url": null },
              "assignees": [
                { "username": "reviewer", "avatar_url": null }
              ],
              "reviewers": [
                { "username": "maintainer", "avatar_url": null }
              ]
            }
            """),
            .json(statusCode: 200, body: """
            [
              {
                "id": 99,
                "body": "Looks good.",
                "system": false,
                "created_at": "2026-07-06T11:12:13.456Z",
                "updated_at": "2026-07-06T11:12:14.789Z",
                "author": { "username": "reviewer", "avatar_url": null }
              }
            ]
            """)
        ])
        let service = GitLabPullRequestService(httpClient: client)

        let detail = try await service.pullRequestDetail(
            repository: makeRepository(),
            token: makeToken(),
            number: 7
        )

        XCTAssertEqual(detail.summary.number, 7)
        XCTAssertEqual(detail.body, "Preserve GitLab detail markdown.")
        XCTAssertEqual(detail.reviewers.map(\.username), ["maintainer"])
        XCTAssertEqual(detail.assignees.map(\.username), ["reviewer"])
        XCTAssertEqual(detail.comments.count, 1)
        XCTAssertEqual(detail.comments.first?.body, "Looks good.")
        XCTAssertEqual(detail.comments.first?.webURL.absoluteString, "https://gitlab.com/group/subgroup/project/-/merge_requests/7#note_99")
        XCTAssertEqual(detail.changesURL.absoluteString, "https://gitlab.com/group/subgroup/project/-/merge_requests/7/diffs")
        XCTAssertEqual(client.requests.map { $0.url?.absoluteString }, [
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests/7",
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests/7/notes"
        ])
    }

    func testRepositoryPathIsURLEncodedForSubgroups() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: "[]")
        ])
        let service = GitLabPullRequestService(httpClient: client)

        _ = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken(),
            filter: .all,
            page: 3,
            perPage: 25
        )

        XCTAssertEqual(
            client.requests.first?.url?.absoluteString,
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests?state=all&per_page=25&page=3"
        )
    }

    func testPullRequestChangesDecodesUnifiedDiffAndUnavailableStates() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "old_path": "Sources/App.swift",
                "new_path": "Sources/App.swift",
                "diff": "@@ -1 +1 @@\\n-old\\n+new",
                "new_file": false,
                "renamed_file": false,
                "deleted_file": false,
                "collapsed": false,
                "too_large": false
              },
              {
                "old_path": "Generated/Large.swift",
                "new_path": "Generated/Large.swift",
                "diff": "",
                "new_file": false,
                "renamed_file": false,
                "deleted_file": false,
                "collapsed": true,
                "too_large": false
              }
            ]
            """)
        ])
        let service = GitLabPullRequestService(httpClient: client)

        let files = try await service.pullRequestChanges(
            repository: makeRepository(),
            token: makeToken(),
            number: 7
        )

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].status, .modified)
        XCTAssertEqual(files[0].diffHunks.count, 1)
        XCTAssertNil(files[1].patch)
        XCTAssertEqual(files[1].patchUnavailableReason, "GitLab collapsed this diff because of its size.")
        XCTAssertEqual(
            client.requests.first?.url?.absoluteString,
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests/7/diffs?per_page=100&page=1&unidiff=true"
        )
    }

    func testForbiddenMapsToPermissionDenied() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 403, body: #"{"message":"403 Forbidden"}"#)
        ])
        let service = GitLabPullRequestService(httpClient: client)

        do {
            _ = try await service.listPullRequests(
                repository: makeRepository(),
                token: makeToken(),
                filter: .open,
                page: 1,
                perPage: 30
            )
            XCTFail("Expected listPullRequests to throw")
        } catch {
            XCTAssertEqual(error as? PullRequestProviderError, .permissionDenied)
        }
    }

    func testMergePullRequestUsesProviderMergeEndpoint() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            {
              "iid": 7,
              "title": "Merge GitLab action",
              "state": "merged",
              "draft": false,
              "web_url": "https://gitlab.com/group/subgroup/project/-/merge_requests/7",
              "created_at": "2026-07-08T00:10:11Z",
              "updated_at": "2026-07-08T00:12:11Z",
              "merged_at": "2026-07-08T00:12:11Z",
              "source_branch": "feature/gitlab-action",
              "target_branch": "main",
              "sha": "def456",
              "author": { "username": "tanuki", "avatar_url": null }
            }
            """)
        ])
        let service = GitLabPullRequestService(httpClient: client)

        try await service.mergePullRequest(
            makeSummary(number: 7),
            repository: makeRepository(),
            token: makeToken()
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests/7/merge"
        )
    }

    private func makeRepository() -> GitRepositoryIdentity {
        GitRepositoryIdentity(
            provider: .gitlab,
            hostURL: URL(string: "https://gitlab.com")!,
            owner: "group/subgroup",
            name: "project"
        )
    }

    private func makeDraft() throws -> PullRequestDraft {
        try PullRequestDraft(
            repository: makeRepository(),
            sourceBranch: "feature/gitlab-action",
            targetBranch: "main",
            title: "Add GitLab action",
            body: "Implements GitLab merge request actions."
        )
    }

    private func makeToken() -> GitProviderToken {
        GitProviderToken(
            accessToken: "secret-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "Bearer"
        )
    }

    private func makeSummary(number: Int) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Merge GitLab action",
            state: .open,
            author: PullRequestAuthor(username: "tanuki", avatarURL: nil),
            source: PullRequestBranchRef(label: "feature/gitlab-action", ref: "feature/gitlab-action"),
            target: PullRequestBranchRef(label: "main", ref: "main"),
            webURL: URL(string: "https://gitlab.com/group/subgroup/project/-/merge_requests/\(number)")!,
            updatedAt: Date(),
            mergeReadiness: .ready
        )
    }
}

private final class StubGitLabPullRequestHTTPClient: GitProviderHTTPClient {
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
