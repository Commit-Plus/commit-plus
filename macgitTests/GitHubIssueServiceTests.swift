// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class GitHubIssueServiceTests: XCTestCase {
    private let repository = HostedIssueFixtures.repository(.github, host: "https://github.com", owner: "octocat", name: "Hello-World")
    private let account = HostedIssueFixtures.account(.github, host: "https://github.com")
    private let token = HostedIssueFixtures.token

    private let issueJSON = """
    {"number": 42, "title": "Fix login", "state": "open", "body": "Steps", "html_url": "https://github.com/octocat/Hello-World/issues/42",
     "user": {"login": "hubot"}, "assignees": [{"login": "octocat"}], "labels": [{"name": "bug", "color": "d73a4a"}],
     "created_at": "2026-07-01T09:10:11Z", "updated_at": "2026-07-06T10:11:12Z"}
    """

    func testListDropsPullRequestsAndFollowsLinkHeader() async throws {
        let client = StubHostedIssueHTTPClient([
            .json(200, """
            [\(issueJSON),
             {"number": 43, "title": "A PR", "state": "open", "pull_request": {"url": "x"}}]
            """, headers: ["Link": "<https://api.github.com/repos/octocat/Hello-World/issues?page=2>; rel=\"next\""])
        ])
        let page = try await GitHubIssueService(httpClient: client).listIssues(
            repository: repository, account: account, token: token, filter: .default, search: "", cursor: nil
        )

        XCTAssertEqual(page.items.map(\.number), [42])
        XCTAssertEqual(page.next, .page(2))
        XCTAssertEqual(page.items.first?.labels, [HostedIssueLabel(name: "bug", color: "d73a4a")])
        XCTAssertEqual(page.items.first?.assignees.map(\.id), ["octocat"])
        XCTAssertEqual(client.requests[0].url?.path, "/repos/octocat/Hello-World/issues")
        XCTAssertEqual(client.query(0)["state"], "open")
        XCTAssertEqual(client.query(0)["sort"], "updated")
        XCTAssertEqual(client.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testRelationshipFiltersUseConnectedLogin() async throws {
        let client = StubHostedIssueHTTPClient([.json(200, "[]"), .json(200, "[]")])
        let service = GitHubIssueService(httpClient: client)
        _ = try await service.listIssues(repository: repository, account: account, token: token,
            filter: HostedIssueFilter(state: .closed, relationship: .assignedToMe), search: "", cursor: nil)
        _ = try await service.listIssues(repository: repository, account: account, token: token,
            filter: HostedIssueFilter(state: .all, relationship: .createdByMe), search: "", cursor: .page(3))

        XCTAssertEqual(client.query(0)["assignee"], "octocat")
        XCTAssertEqual(client.query(0)["state"], "closed")
        XCTAssertEqual(client.query(1)["creator"], "octocat")
        XCTAssertEqual(client.query(1)["page"], "3")
    }

    func testSearchUsesSearchEndpointQualifiers() async throws {
        let client = StubHostedIssueHTTPClient([.json(200, #"{"items": [\#(issueJSON)]}"#)])
        let page = try await GitHubIssueService(httpClient: client).listIssues(
            repository: repository, account: account, token: token,
            filter: HostedIssueFilter(state: .open, relationship: .createdByMe), search: " login ", cursor: nil
        )

        XCTAssertEqual(page.items.count, 1)
        XCTAssertNil(page.next)
        XCTAssertEqual(client.requests[0].url?.path, "/search/issues")
        XCTAssertEqual(client.query(0)["q"], "repo:octocat/Hello-World is:issue is:open author:octocat login")
    }

    func testEnterpriseUsesServerAPIBase() async throws {
        let enterprise = HostedIssueFixtures.repository(.github, host: "https://ghe.example.com", owner: "team", name: "app")
        let client = StubHostedIssueHTTPClient([.json(200, "[]")])
        _ = try await GitHubIssueService(httpClient: client).listIssues(
            repository: enterprise, account: account, token: token, filter: .default, search: "", cursor: nil
        )

        XCTAssertEqual(client.requests[0].url?.host, "ghe.example.com")
        XCTAssertEqual(client.requests[0].url?.path, "/api/v3/repos/team/app/issues")
    }

    func testDetailLoadsComments() async throws {
        let client = StubHostedIssueHTTPClient([
            .json(200, issueJSON),
            .json(200, #"[{"id": 7, "body": "Same here", "user": {"login": "hubot"}, "created_at": "2026-07-02T00:00:00Z"}]"#)
        ])
        let detail = try await GitHubIssueService(httpClient: client).issueDetail(number: 42, repository: repository, token: token)

        XCTAssertEqual(detail.body, "Steps")
        XCTAssertEqual(detail.bodyFormat, .markdown)
        XCTAssertEqual(detail.comments.map(\.body), ["Same here"])
        XCTAssertFalse(detail.commentsUnavailable)
        XCTAssertEqual(client.requests[1].url?.path, "/repos/octocat/Hello-World/issues/42/comments")
    }

    func testWritesSendExpectedRequests() async throws {
        let client = StubHostedIssueHTTPClient([.json(201, issueJSON), .json(201, "{}"), .json(200, "{}")])
        let service = GitHubIssueService(httpClient: client)
        let created = try await service.createIssue(HostedIssueDraft(title: "Fix login", body: "Steps"), repository: repository, token: token)
        try await service.addComment("Fixed in main", number: 42, repository: repository, token: token)
        try await service.setState(.closed, number: 42, repository: repository, token: token)

        XCTAssertEqual(created.number, 42)
        XCTAssertEqual(client.requests[0].httpMethod, "POST")
        XCTAssertEqual(client.jsonBody(0)["title"] as? String, "Fix login")
        XCTAssertEqual(client.requests[1].url?.path, "/repos/octocat/Hello-World/issues/42/comments")
        XCTAssertEqual(client.jsonBody(1)["body"] as? String, "Fixed in main")
        XCTAssertEqual(client.requests[2].httpMethod, "PATCH")
        XCTAssertEqual(client.jsonBody(2)["state"] as? String, "closed")
    }

    func testErrorMapping() async {
        await assertListError(.json(410, #"{"message": "Issues are disabled for this repo"}"#), .trackerDisabled)
        await assertListError(.json(401, "{}"), .reauthorizationRequired)
        await assertListError(.json(404, "{}"), .notFound)
        await assertListError(
            .json(403, #"{"message": "Although you appear to have the correct authorization credentials, the org organization has enabled OAuth App access restrictions"}"#),
            .organizationAccessRequired
        )
        await assertListError(
            .json(403, #"{"message": "API rate limit exceeded"}"#, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "2000000000"]),
            .rateLimited(retryAfter: Date(timeIntervalSince1970: 2_000_000_000))
        )
    }

    func testWritePermissionDeniedNamesRepositoryAccess() async {
        let client = StubHostedIssueHTTPClient([.json(403, #"{"message": "Resource not accessible by integration"}"#)])
        do {
            try await GitHubIssueService(httpClient: client).addComment("x", number: 1, repository: repository, token: token)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? HostedIssueError, .missingScope("write access to this repository"))
        }
    }

    private func assertListError(_ response: StubHostedIssueHTTPClient.Response, _ expected: HostedIssueError,
                                 line: UInt = #line) async {
        let client = StubHostedIssueHTTPClient([response])
        do {
            _ = try await GitHubIssueService(httpClient: client).listIssues(
                repository: repository, account: account, token: token, filter: .default, search: "", cursor: nil
            )
            XCTFail("Expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? HostedIssueError, expected, line: line)
        }
    }
}
