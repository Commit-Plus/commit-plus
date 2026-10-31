// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class BitbucketIssueServiceTests: XCTestCase {
    private let repository = HostedIssueFixtures.repository(.bitbucket, host: "https://bitbucket.org", owner: "team", name: "app")
    private let account = HostedIssueFixtures.account(.bitbucket, host: "https://bitbucket.org", username: "alice")
    private var token: GitProviderToken {
        var token = HostedIssueFixtures.token
        token.apiUsername = "alice@example.com"
        return token
    }

    private let issueJSON = """
    {"id": 7, "title": "Broken build", "state": "on hold", "kind": "bug", "priority": "major",
     "content": {"raw": "Fails on CI"}, "reporter": {"uuid": "{u1}", "display_name": "Alice"},
     "assignee": {"uuid": "{u2}", "display_name": "Bob"},
     "created_on": "2026-07-01T09:10:11.123456+00:00", "updated_on": "2026-07-06T10:11:12.654321+00:00",
     "links": {"html": {"href": "https://bitbucket.org/team/app/issues/7"}}}
    """

    func testListBuildsBBQLAndUsesEmailBasicAuth() async throws {
        let client = StubHostedIssueHTTPClient([
            .json(200, #"{"uuid": "{u2}"}"#),
            .json(200, #"{"values": [\#(issueJSON)], "next": "https://api.bitbucket.org/2.0/repositories/team/app/issues?page=2"}"#)
        ])
        let page = try await BitbucketIssueService(httpClient: client).listIssues(
            repository: repository, account: account, token: token,
            filter: HostedIssueFilter(state: .open, relationship: .assignedToMe), search: "build", cursor: nil
        )

        XCTAssertEqual(page.items.map(\.number), [7])
        XCTAssertEqual(page.items.first?.state, .open)
        XCTAssertEqual(page.items.first?.stateName, "On hold")
        XCTAssertEqual(page.items.first?.labels.map(\.name), ["bug", "major"])
        XCTAssertNotNil(page.items.first?.updatedAt)
        XCTAssertEqual(page.next, .url(URL(string: "https://api.bitbucket.org/2.0/repositories/team/app/issues?page=2")!))
        XCTAssertEqual(client.requests[0].url?.path, "/2.0/user")
        XCTAssertEqual(client.requests[1].url?.path, "/2.0/repositories/team/app/issues")
        XCTAssertEqual(client.query(1)["q"],
            #"(state="new" OR state="open" OR state="on hold") AND assignee.uuid="{u2}" AND title~"build""#)
        XCTAssertEqual(client.query(1)["sort"], "-updated_on")
        let expectedAuth = "Basic " + Data("alice@example.com:secret-token".utf8).base64EncodedString()
        XCTAssertEqual(client.requests[1].value(forHTTPHeaderField: "Authorization"), expectedAuth)
    }

    func testNextCursorIsFollowedAsIs() async throws {
        let next = URL(string: "https://api.bitbucket.org/2.0/repositories/team/app/issues?page=2")!
        let client = StubHostedIssueHTTPClient([.json(200, #"{"values": []}"#)])
        let page = try await BitbucketIssueService(httpClient: client).listIssues(
            repository: repository, account: account, token: token, filter: .default, search: "", cursor: .url(next)
        )

        XCTAssertNil(page.next)
        XCTAssertEqual(client.requests[0].url, next)
    }

    func testClosedStatesAndNumberSearch() async throws {
        let client = StubHostedIssueHTTPClient([.json(200, #"{"values": []}"#)])
        _ = try await BitbucketIssueService(httpClient: client).listIssues(
            repository: repository, account: account, token: token,
            filter: HostedIssueFilter(state: .closed, relationship: .all), search: "#12", cursor: nil
        )

        XCTAssertEqual(client.query(0)["q"],
            #"(state="resolved" OR state="invalid" OR state="duplicate" OR state="wontfix" OR state="closed") AND id=12"#)
    }

    func testMissingEmailAsksForAccountUpdateWithoutRequest() async {
        let client = StubHostedIssueHTTPClient([])
        do {
            _ = try await BitbucketIssueService(httpClient: client).listIssues(
                repository: repository, account: account, token: HostedIssueFixtures.token,
                filter: .default, search: "", cursor: nil
            )
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? HostedIssueError, .accountUpdateRequired(BitbucketIssueService.missingEmailMessage))
        }
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testDetailSkipsChangeOnlyComments() async throws {
        let client = StubHostedIssueHTTPClient([
            .json(200, issueJSON),
            .json(200, #"{"values": [{"id": 1, "content": {"raw": ""}}, {"id": 2, "content": {"raw": "On it"}, "user": {"display_name": "Bob"}}]}"#)
        ])
        let detail = try await BitbucketIssueService(httpClient: client).issueDetail(number: 7, repository: repository, token: token)

        XCTAssertEqual(detail.body, "Fails on CI")
        XCTAssertEqual(detail.comments.map(\.body), ["On it"])
    }

    func testWritesSendExpectedRequests() async throws {
        let client = StubHostedIssueHTTPClient([.json(201, issueJSON), .json(201, "{}"), .json(200, "{}"), .json(200, "{}")])
        let service = BitbucketIssueService(httpClient: client)
        _ = try await service.createIssue(HostedIssueDraft(title: "Broken build", body: "Fails"), repository: repository, token: token)
        try await service.addComment("On it", number: 7, repository: repository, token: token)
        try await service.setState(.closed, number: 7, repository: repository, token: token)
        try await service.setState(.open, number: 7, repository: repository, token: token)

        XCTAssertEqual((client.jsonBody(0)["content"] as? [String: String])?["raw"], "Fails")
        XCTAssertEqual(client.requests[1].url?.path, "/2.0/repositories/team/app/issues/7/comments")
        XCTAssertEqual(client.requests[2].httpMethod, "PUT")
        XCTAssertEqual(client.jsonBody(2)["state"] as? String, "resolved")
        XCTAssertEqual(client.jsonBody(3)["state"] as? String, "open")
    }

    func testErrorMapping() async throws {
        for (response, expected) in [
            (StubHostedIssueHTTPClient.Response.json(404, #"{"error": {"message": "Repository has no issue tracker."}}"#), HostedIssueError.trackerDisabled),
            (.json(404, #"{"error": {"message": "Repository team/app not found"}}"#), .notFound),
            (.json(403, #"{"error": {"message": "Forbidden"}}"#), .missingScope("an API token with the read:issue:bitbucket scope")),
            (.json(401, "{}"), .reauthorizationRequired),
        ] {
            let client = StubHostedIssueHTTPClient([response])
            do {
                _ = try await BitbucketIssueService(httpClient: client).listIssues(
                    repository: repository, account: account, token: token, filter: .default, search: "", cursor: nil
                )
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? HostedIssueError, expected)
            }
        }

        let client = StubHostedIssueHTTPClient([.json(403, "{}")])
        do {
            try await BitbucketIssueService(httpClient: client).addComment("x", number: 7, repository: repository, token: token)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? HostedIssueError, .missingScope("an API token with the write:issue:bitbucket scope"))
        }
    }
}
