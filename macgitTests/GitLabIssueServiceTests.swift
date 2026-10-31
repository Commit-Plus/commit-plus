// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class GitLabIssueServiceTests: XCTestCase {
    private let repository = HostedIssueFixtures.repository(.gitlab, host: "https://gitlab.com", owner: "group/sub", name: "app")
    private let account = HostedIssueFixtures.account(.gitlab, host: "https://gitlab.com")
    private let token = HostedIssueFixtures.token

    private let issueJSON = """
    {"iid": 5, "title": "Crash on launch", "state": "opened", "description": "Trace",
     "web_url": "https://gitlab.com/group/sub/app/-/issues/5",
     "author": {"id": 1, "username": "alice", "name": "Alice"}, "assignees": [], "labels": ["bug"],
     "created_at": "2026-07-01T09:10:11.123Z", "updated_at": "2026-07-06T10:11:12.456Z"}
    """

    func testListUsesStateScopeAndPagination() async throws {
        let client = StubHostedIssueHTTPClient([.json(200, "[\(issueJSON)]", headers: ["X-Next-Page": "2"])])
        let page = try await GitLabIssueService(httpClient: client).listIssues(
            repository: repository, account: account, token: token,
            filter: HostedIssueFilter(state: .open, relationship: .assignedToMe), search: "", cursor: nil
        )

        XCTAssertEqual(page.items.map(\.number), [5])
        XCTAssertEqual(page.items.first?.state, .open)
        XCTAssertEqual(page.items.first?.author?.displayName, "Alice")
        XCTAssertNotNil(page.items.first?.updatedAt)
        XCTAssertEqual(page.next, .page(2))
        XCTAssertEqual(client.requests[0].url?.absoluteString.contains("/api/v4/projects/group%2Fsub%2Fapp/issues"), true)
        XCTAssertEqual(client.query(0)["state"], "opened")
        XCTAssertEqual(client.query(0)["scope"], "assigned_to_me")
        XCTAssertEqual(client.query(0)["order_by"], "updated_at")
    }

    func testAllStateOmitsStateAndSearchIsSent() async throws {
        let client = StubHostedIssueHTTPClient([.json(200, "[]"), .json(200, "[]")])
        let service = GitLabIssueService(httpClient: client)
        let page = try await service.listIssues(repository: repository, account: account, token: token,
            filter: HostedIssueFilter(state: .all, relationship: .createdByMe), search: "login", cursor: .page(4))
        _ = try await service.listIssues(repository: repository, account: account, token: token,
            filter: .default, search: "#12", cursor: nil)

        XCTAssertNil(page.next)
        XCTAssertNil(client.query(0)["state"])
        XCTAssertEqual(client.query(0)["scope"], "created_by_me")
        XCTAssertEqual(client.query(0)["search"], "login")
        XCTAssertEqual(client.query(0)["page"], "4")
        XCTAssertEqual(client.query(1)["iids[]"], "12")
        XCTAssertNil(client.query(1)["search"])
    }

    func testSelfManagedSubpathHost() async throws {
        let selfManaged = HostedIssueFixtures.repository(.gitlab, host: "https://git.example.com/gitlab", owner: "team", name: "app")
        let client = StubHostedIssueHTTPClient([.json(200, "[]")])
        _ = try await GitLabIssueService(httpClient: client).listIssues(
            repository: selfManaged, account: account, token: token, filter: .default, search: "", cursor: nil
        )

        XCTAssertEqual(client.requests[0].url?.host, "git.example.com")
        XCTAssertTrue(client.requests[0].url!.absoluteString.contains("/gitlab/api/v4/projects/team%2Fapp/issues"))
    }

    func testDetailSkipsSystemNotes() async throws {
        let client = StubHostedIssueHTTPClient([
            .json(200, issueJSON),
            .json(200, """
            [{"id": 1, "body": "changed the description", "system": true},
             {"id": 2, "body": "Looking", "system": false, "author": {"id": 2, "username": "bob"}, "created_at": "2026-07-02T00:00:00Z"}]
            """)
        ])
        let detail = try await GitLabIssueService(httpClient: client).issueDetail(number: 5, repository: repository, token: token)

        XCTAssertEqual(detail.body, "Trace")
        XCTAssertEqual(detail.comments.map(\.body), ["Looking"])
    }

    func testWritesSendExpectedRequests() async throws {
        let client = StubHostedIssueHTTPClient([.json(201, issueJSON), .json(201, "{}"), .json(200, "{}"), .json(200, "{}")])
        let service = GitLabIssueService(httpClient: client)
        _ = try await service.createIssue(HostedIssueDraft(title: "Crash on launch", body: "Trace"), repository: repository, token: token)
        try await service.addComment("Fixed", number: 5, repository: repository, token: token)
        try await service.setState(.closed, number: 5, repository: repository, token: token)
        try await service.setState(.open, number: 5, repository: repository, token: token)

        XCTAssertEqual(client.jsonBody(0)["description"] as? String, "Trace")
        XCTAssertTrue(client.requests[1].url!.absoluteString.hasSuffix("/issues/5/notes"))
        XCTAssertEqual(client.requests[2].httpMethod, "PUT")
        XCTAssertEqual(client.jsonBody(2)["state_event"] as? String, "close")
        XCTAssertEqual(client.jsonBody(3)["state_event"] as? String, "reopen")
    }

    func testErrorMapping() async throws {
        for (response, expected) in [
            (StubHostedIssueHTTPClient.Response.json(401, "{}"), HostedIssueError.reauthorizationRequired),
            (.json(403, #"{"message": "403 Forbidden"}"#), .trackerDisabled),
            (.json(404, #"{"message": "404 Project Not Found"}"#), .notFound),
            (.json(500, #"{"message": "boom"}"#), .providerMessage("boom")),
        ] {
            let client = StubHostedIssueHTTPClient([response])
            do {
                _ = try await GitLabIssueService(httpClient: client).listIssues(
                    repository: repository, account: account, token: token, filter: .default, search: "", cursor: nil
                )
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? HostedIssueError, expected)
            }
        }

        let client = StubHostedIssueHTTPClient([.json(403, #"{"message": "403 Forbidden"}"#)])
        do {
            try await GitLabIssueService(httpClient: client).setState(.closed, number: 5, repository: repository, token: token)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? HostedIssueError, .missingScope("write access to this repository"))
        }
    }
}
