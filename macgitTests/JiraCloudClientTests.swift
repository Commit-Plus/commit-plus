// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class JiraCloudClientTests: XCTestCase {
    private let site = URL(string: "https://acme.atlassian.net")!
    private let credential = JiraCredential(email: "dev@example.com", token: "secret-token-123")

    func testValidateUsesBasicAuthAgainstTheSite() async throws {
        let http = StubJiraHTTPClient([
            .init(path: "/rest/api/3/myself", status: 200, body: #"{"accountId":"abc","displayName":"Dev","emailAddress":"dev@example.com"}"#),
        ])
        let account = try await JiraCloudClient(httpClient: http).validate(siteURL: site, credential: credential)

        XCTAssertEqual(account, JiraValidatedAccount(accountID: "abc", displayName: "Dev", email: "dev@example.com", apiBase: .site))
        let expected = "Basic " + Data("dev@example.com:secret-token-123".utf8).base64EncodedString()
        XCTAssertEqual(http.requests.first?.value(forHTTPHeaderField: "Authorization"), expected)
        XCTAssertEqual(http.requests.first?.url?.host(), "acme.atlassian.net")
    }

    func testScopedTokenFallsBackToGateway() async throws {
        let http = StubJiraHTTPClient([
            .init(path: "/rest/api/3/myself", status: 401, body: ""),
            .init(path: "/_edge/tenant_info", status: 200, body: #"{"cloudId":"11111111-2222-3333-4444-555555555555"}"#),
            .init(path: "/ex/jira/11111111-2222-3333-4444-555555555555/rest/api/3/myself", status: 200, body: #"{"accountId":"abc"}"#),
        ])
        let account = try await JiraCloudClient(httpClient: http).validate(siteURL: site, credential: credential)

        XCTAssertEqual(account.apiBase, .gateway(cloudID: "11111111-2222-3333-4444-555555555555"))
        XCTAssertEqual(http.requests.last?.url?.host(), "api.atlassian.com")
        XCTAssertNil(http.requests[1].value(forHTTPHeaderField: "Authorization"), "tenant_info must not receive the token")
        XCTAssertEqual(account.displayName, "dev@example.com")
    }

    func testRejectedEverywhereIsInvalidCredentials() async {
        let http = StubJiraHTTPClient([
            .init(path: "/rest/api/3/myself", status: 401, body: ""),
            .init(path: "/_edge/tenant_info", status: 200, body: #"{"cloudId":"abc"}"#),
            .init(path: "/ex/jira/abc/rest/api/3/myself", status: 401, body: ""),
        ])
        await assertThrows(.invalidCredentials) {
            _ = try await JiraCloudClient(httpClient: http).validate(siteURL: self.site, credential: self.credential)
        }
    }

    func testNonJiraSiteIsInvalidResponseAndNetworkFailureIsUnreachable() async {
        await assertThrows(.invalidResponse) {
            let http = StubJiraHTTPClient([.init(path: "/rest/api/3/myself", status: 200, body: "<html></html>")])
            _ = try await JiraCloudClient(httpClient: http).validate(siteURL: self.site, credential: self.credential)
        }
        await assertThrows(.unreachable) {
            let http = StubJiraHTTPClient([], error: URLError(.cannotFindHost))
            _ = try await JiraCloudClient(httpClient: http).validate(siteURL: self.site, credential: self.credential)
        }
    }

    func testStatusMapping() {
        func error(_ status: Int, headers: [String: String] = [:]) -> JiraError? {
            let response = HTTPURLResponse(url: site, statusCode: status, httpVersion: nil, headerFields: headers)!
            do { try JiraCloudClient.validate(response); return nil } catch { return error as? JiraError }
        }
        XCTAssertNil(error(200))
        XCTAssertEqual(error(400), .invalidQuery)
        XCTAssertEqual(error(401), .needsReconnect)
        XCTAssertEqual(error(403), .forbidden)
        XCTAssertEqual(error(429, headers: ["Retry-After": "12"]), .rateLimited(retryAfter: 12))
        XCTAssertEqual(error(429), .rateLimited(retryAfter: nil))
        XCTAssertEqual(error(503), .unreachable)
        XCTAssertEqual(error(404), .invalidResponse)
    }

    func testErrorDescriptionsNeverContainTheToken() {
        let errors: [JiraError] = [.unsupportedSite, .invalidCredentials, .needsReconnect, .forbidden,
                                   .rateLimited(retryAfter: 5), .unreachable, .invalidResponse, .invalidQuery,
                                   .notSignedIn, .notConnected]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.contains(credential.token))
        }
    }

    func testSprintFieldDiscovery() async throws {
        let withSprints = StubJiraHTTPClient([.init(path: "/rest/api/3/field", status: 200, body: #"""
            [{"id":"summary"},{"id":"customfield_10020","schema":{"custom":"com.pyxis.greenhopper.jira:gh-sprint"}}]
            """#)])
        let fieldID = try await JiraCloudClient(httpClient: withSprints).sprintFieldID(baseURL: site, credential: credential)
        XCTAssertEqual(fieldID, "customfield_10020")

        let withoutSprints = StubJiraHTTPClient([.init(path: "/rest/api/3/field", status: 200, body: #"[{"id":"summary"}]"#)])
        let missing = try await JiraCloudClient(httpClient: withoutSprints).sprintFieldID(baseURL: site, credential: credential)
        XCTAssertNil(missing)
        XCTAssertFalse(JiraJQLBuilder.jql(for: .default, supportsSprints: missing != nil).contains("sprint"))
    }

    func testSearchSendsJQLAndParsesIssuesAndNextPage() async throws {
        let http = StubJiraHTTPClient([.init(path: "/rest/api/3/search/jql", status: 200, body: #"""
            {"isLast":false,"nextPageToken":"page-2","issues":[{"id":"10001","key":"PROJ-1","fields":{
              "summary":"Fix login crash","updated":"2026-10-20T10:15:30.123+0700",
              "status":{"name":"In Review","statusCategory":{"key":"indeterminate"}},
              "issuetype":{"name":"Bug"},"priority":{"name":"High"},
              "project":{"key":"PROJ","name":"Project"},
              "customfield_10020":[{"id":7,"name":"Sprint 6","state":"closed"},{"id":8,"name":"Sprint 7","state":"active"}]}}]}
            """#)])
        let page = try await JiraCloudClient(httpClient: http).searchIssues(
            baseURL: site, credential: credential, jql: "assignee = currentUser()",
            sprintFieldID: "customfield_10020", pageToken: "page-1"
        )

        XCTAssertEqual(page.nextPageToken, "page-2")
        let issue = try XCTUnwrap(page.issues.first)
        XCTAssertEqual(issue.key, "PROJ-1")
        XCTAssertEqual(issue.statusCategory, .inProgress)
        XCTAssertEqual(issue.priorityName, "High")
        XCTAssertEqual(issue.displaySprint?.name, "Sprint 7")
        XCTAssertNotNil(issue.updated)

        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["jql"] as? String, "assignee = currentUser()")
        XCTAssertEqual(body["nextPageToken"] as? String, "page-1")
        XCTAssertEqual(body["maxResults"] as? Int, JiraCloudClient.pageSize)
        XCTAssertTrue((body["fields"] as? [String])?.contains("customfield_10020") == true)
    }

    func testLastPageHasNoNextToken() async throws {
        let http = StubJiraHTTPClient([.init(path: "/rest/api/3/search/jql", status: 200, body: #"{"isLast":true,"nextPageToken":"x","issues":[]}"#)])
        let page = try await JiraCloudClient(httpClient: http).searchIssues(
            baseURL: site, credential: credential, jql: "x", sprintFieldID: nil, pageToken: nil
        )
        XCTAssertNil(page.nextPageToken)
    }

    func testMissingIsLastKeepsNextPageToken() async throws {
        let http = StubJiraHTTPClient([.init(path: "/rest/api/3/search/jql", status: 200, body: #"{"nextPageToken":"page-2","issues":[]}"#)])
        let page = try await JiraCloudClient(httpClient: http).searchIssues(
            baseURL: site, credential: credential, jql: "x", sprintFieldID: nil, pageToken: nil
        )
        XCTAssertEqual(page.nextPageToken, "page-2")
    }

    private func assertThrows(
        _ expected: JiraError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? JiraError, expected, file: file, line: line)
        }
    }
}

final class StubJiraHTTPClient: GitProviderHTTPClient {
    struct Route {
        var path: String
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    private var routes: [Route]
    private let error: Error?
    private(set) var requests: [URLRequest] = []

    init(_ routes: [Route], error: Error? = nil) {
        self.routes = routes
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let error { throw error }
        guard let index = routes.firstIndex(where: { $0.path == request.url?.path() }) else {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        let route = routes.remove(at: index)
        let response = HTTPURLResponse(url: request.url!, statusCode: route.status, httpVersion: nil, headerFields: route.headers)!
        return (Data(route.body.utf8), response)
    }
}
