// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class AzureBoardsWorkItemServiceTests: XCTestCase {
    private let repository = HostedIssueFixtures.repository(.azureDevOps, host: "https://dev.azure.com/contoso", owner: "ChatApp", name: "ChatApp")
    private let account = HostedIssueFixtures.account(.azureDevOps, host: "https://dev.azure.com/contoso")
    private let token = HostedIssueFixtures.token

    private let typesJSON = """
    {"value": [
      {"name": "Bug", "states": [{"name": "New", "category": "Proposed"}, {"name": "Active", "category": "InProgress"},
                                 {"name": "Resolved", "category": "Resolved"}, {"name": "Closed", "category": "Completed"}]},
      {"name": "Task", "states": [{"name": "To Do", "category": "Proposed"}, {"name": "Done", "category": "Completed"},
                                  {"name": "Removed", "category": "Removed"}]},
      {"name": "Note", "states": [{"name": "Open", "category": "InProgress"}]},
      {"name": "Legacy", "isDisabled": true, "states": []}
    ]}
    """

    private func workItemJSON(_ id: Int, type: String = "Bug", state: String = "Active") -> String {
        """
        {"id": \(id), "fields": {"System.Title": "Item \(id)", "System.State": "\(state)", "System.WorkItemType": "\(type)",
         "System.CreatedBy": {"displayName": "Alice", "uniqueName": "alice@contoso.com"},
         "System.Tags": "ui; login", "System.ChangedDate": "2026-07-06T10:11:12.1234567Z",
         "System.Description": "<p>Steps<br>1 &amp; 2</p>"}}
        """
    }

    func testWIQLUsesProjectStateCategoriesAndMe() {
        let open = AzureBoardsWorkItemService.wiql(
            filter: HostedIssueFilter(state: .open, relationship: .assignedToMe), search: "", closedStates: ["Closed", "Done"])
        XCTAssertEqual(open, "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND [System.State] NOT IN ('Closed', 'Done') AND [System.AssignedTo] = @Me ORDER BY [System.ChangedDate] DESC")

        let closed = AzureBoardsWorkItemService.wiql(
            filter: HostedIssueFilter(state: .closed, relationship: .createdByMe), search: "it's", closedStates: ["Done"])
        XCTAssertTrue(closed.contains("[System.State] IN ('Done')"))
        XCTAssertTrue(closed.contains("[System.CreatedBy] = @Me"))
        XCTAssertTrue(closed.contains("[System.Title] CONTAINS 'it''s'"))

        let byNumber = AzureBoardsWorkItemService.wiql(filter: HostedIssueFilter(state: .all), search: "AB#42", closedStates: [])
        XCTAssertTrue(byNumber.contains("[System.Id] = 42"))
        XCTAssertFalse(byNumber.contains("[System.State]"))
    }

    func testListChunksIDsAndKeepsQueryOrder() async throws {
        let ids = Array(1...250)
        let wiql = #"{"workItems": ["# + ids.map { #"{"id": \#($0)}"# }.joined(separator: ",") + "]}"
        let batch = #"{"value": [\#(workItemJSON(2, type: "Task", state: "Done")), \#(workItemJSON(1))]}"#
        let client = StubHostedIssueHTTPClient([.json(200, typesJSON), .json(200, wiql), .json(200, batch)])
        let page = try await AzureBoardsWorkItemService(httpClient: client).listIssues(
            repository: repository, account: account, token: token,
            filter: HostedIssueFilter(state: .all, relationship: .all), search: "", cursor: nil
        )

        XCTAssertEqual(client.requests[0].url?.path, "/contoso/ChatApp/_apis/wit/workitemtypes")
        XCTAssertEqual(client.query(0)["api-version"], "7.1")
        XCTAssertEqual(client.requests[1].url?.path, "/contoso/ChatApp/_apis/wit/wiql")
        XCTAssertEqual(client.requests[2].url?.path, "/contoso/_apis/wit/workitemsbatch")
        XCTAssertEqual((client.jsonBody(2)["ids"] as? [Int])?.count, 200)
        XCTAssertEqual(page.items.map(\.number), [1, 2])
        XCTAssertEqual(page.items[0].state, .open)
        XCTAssertEqual(page.items[0].stateName, "Active")
        XCTAssertEqual(page.items[1].state, .closed)
        XCTAssertEqual(page.items[0].labels.map(\.name), ["ui", "login"])
        XCTAssertNotNil(page.items[0].updatedAt)
        XCTAssertEqual(page.items[0].webURL?.absoluteString, "https://dev.azure.com/contoso/ChatApp/_workitems/edit/1")
        XCTAssertEqual(page.next, .workItemIDs(Array(201...250)))
        XCTAssertEqual(client.requests[0].value(forHTTPHeaderField: "Authorization"),
                       "Basic " + Data(":secret-token".utf8).base64EncodedString())
    }

    func testNextCursorSkipsQuery() async throws {
        let client = StubHostedIssueHTTPClient([.json(200, typesJSON), .json(200, #"{"value": [\#(workItemJSON(201))]}"#)])
        let page = try await AzureBoardsWorkItemService(httpClient: client).listIssues(
            repository: repository, account: account, token: token, filter: .default, search: "", cursor: .workItemIDs([201])
        )

        XCTAssertEqual(page.items.map(\.number), [201])
        XCTAssertNil(page.next)
        XCTAssertEqual(client.requests.count, 2)
    }

    func testDetailAndHTMLText() async throws {
        let client = StubHostedIssueHTTPClient([
            .json(200, typesJSON),
            .json(200, workItemJSON(7)),
            .json(200, #"{"comments": [{"id": 3, "text": "<div>Looks good</div>", "createdBy": {"displayName": "Bob"}, "createdDate": "2026-07-07T00:00:00.12Z"}]}"#)
        ])
        let detail = try await AzureBoardsWorkItemService(httpClient: client).issueDetail(number: 7, repository: repository, token: token)

        XCTAssertEqual(detail.bodyFormat, .html)
        XCTAssertEqual(HostedIssueHTMLText.plainText(fromHTML: detail.body), "Steps\n1 & 2")
        XCTAssertEqual(detail.comments.map(\.body), ["<div>Looks good</div>"])
        XCTAssertEqual(client.query(2)["api-version"], AzureBoardsWorkItemService.commentsAPIVersion)
        XCTAssertEqual(client.query(2)["order"], "asc")
    }

    func testHTMLTextDropsImagesAndScripts() {
        let html = #"<p>See <img src="https://evil.example/x.png"> here</p><script>alert(1)</script><ul><li>One</li><li>Two &#233;</li></ul>"#
        XCTAssertEqual(HostedIssueHTMLText.plainText(fromHTML: html), "See  here\n\n• One\n• Two é")
        XCTAssertEqual(HostedIssueHTMLText.html(fromPlainText: "a < b\nc & d"), "a &lt; b<br>c &amp; d")
    }

    func testWorkItemTypesSkipDisabled() async throws {
        let client = StubHostedIssueHTTPClient([.json(200, typesJSON)])
        let types = try await AzureBoardsWorkItemService(httpClient: client).workItemTypes(repository: repository, token: token)
        XCTAssertEqual(types, ["Bug", "Task", "Note"])
    }

    func testCreateCommentAndStateTransitions() async throws {
        let client = StubHostedIssueHTTPClient([
            .json(200, workItemJSON(9, state: "New")), .json(200, typesJSON),
            .json(200, "{}"),
            .json(200, workItemJSON(9)), .json(200, typesJSON), .json(200, "{}"),
            .json(200, workItemJSON(9, state: "Closed")), .json(200, typesJSON), .json(200, "{}"),
        ])
        let service = AzureBoardsWorkItemService(httpClient: client)
        let created = try await service.createIssue(
            HostedIssueDraft(title: "Crash", body: "a<b", workItemType: "User Story"), repository: repository, token: token)
        try await service.addComment("Fixed", number: 9, repository: repository, token: token)
        try await service.setState(.closed, number: 9, repository: repository, token: token)
        try await service.setState(.open, number: 9, repository: repository, token: token)

        XCTAssertEqual(created.number, 9)
        XCTAssertTrue(client.requests[0].url!.absoluteString.contains("/_apis/wit/workitems/$User%20Story"))
        XCTAssertEqual(client.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json-patch+json")
        let createOps = try XCTUnwrap(JSONSerialization.jsonObject(with: client.requests[0].httpBody!) as? [[String: String]])
        XCTAssertEqual(createOps.map { $0["path"] }, ["/fields/System.Title", "/fields/System.Description"])
        XCTAssertEqual(createOps[1]["value"], "a&lt;b")
        XCTAssertEqual(client.jsonBody(2)["text"] as? String, "Fixed")
        XCTAssertEqual(client.query(2)["api-version"], AzureBoardsWorkItemService.commentsAPIVersion)
        let closeOps = try XCTUnwrap(JSONSerialization.jsonObject(with: client.requests[5].httpBody!) as? [[String: String]])
        XCTAssertEqual(closeOps.first?["value"], "Closed")
        XCTAssertEqual(client.requests[5].httpMethod, "PATCH")
        let reopenOps = try XCTUnwrap(JSONSerialization.jsonObject(with: client.requests[8].httpBody!) as? [[String: String]])
        XCTAssertEqual(reopenOps.first?["value"], "New")
    }

    func testTypeWithoutCompletedStateCannotClose() async {
        let client = StubHostedIssueHTTPClient([.json(200, workItemJSON(4, type: "Note", state: "Open")), .json(200, typesJSON)])
        do {
            try await AzureBoardsWorkItemService(httpClient: client).setState(.closed, number: 4, repository: repository, token: token)
            XCTFail("Expected an error")
        } catch {
            guard case .closeUnavailable = error as? HostedIssueError else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertEqual(client.requests.count, 2)
    }

    func testErrorMapping() async throws {
        for (response, expected) in [
            (StubHostedIssueHTTPClient.Response.json(401, "{}"), HostedIssueError.missingScope(AzureBoardsWorkItemService.readScope)),
            (.json(403, "{}"), .missingScope(AzureBoardsWorkItemService.readScope)),
            (.json(203, "<html></html>", headers: ["Content-Type": "text/html"]), .reauthorizationRequired),
            (.json(404, #"{"message": "TF200016: The project does not exist."}"#), .notFound),
        ] {
            let client = StubHostedIssueHTTPClient([response])
            do {
                _ = try await AzureBoardsWorkItemService(httpClient: client).listIssues(
                    repository: repository, account: account, token: token, filter: .default, search: "", cursor: nil
                )
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? HostedIssueError, expected)
            }
        }

        let client = StubHostedIssueHTTPClient([.json(401, "{}")])
        do {
            try await AzureBoardsWorkItemService(httpClient: client).addComment("x", number: 1, repository: repository, token: token)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? HostedIssueError, .missingScope(AzureBoardsWorkItemService.writeScope))
        }
    }
}
