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

final class AzureReposPullRequestServiceTests: XCTestCase {
    // MARK: - Requests and errors

    func testRequestURLEncodesProjectAndAuthenticatesWithBasicPAT() async throws {
        let client = StubAzureHTTPClient { _ in .json(#"{"value":[]}"#) }
        let service = AzureReposPullRequestService(httpClient: client)

        _ = try await service.listPullRequests(
            repository: makeRepository(project: "Chat App"), token: makeToken(), filter: .open, page: 1, perPage: 30
        )

        let request = try XCTUnwrap(client.requests.first)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, "dev.azure.com")
        XCTAssertEqual(url.path(percentEncoded: true), "/trantienthanh1998/Chat%20App/_apis/git/repositories/ChatApp/pullrequests")
        let query = queryItems(url)
        XCTAssertEqual(query["api-version"], "7.1")
        XCTAssertEqual(query["searchCriteria.status"], "active")
        XCTAssertEqual(query["$top"], "31")
        XCTAssertEqual(query["$skip"], "0")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Basic " + Data(":secret-pat".utf8).base64EncodedString()
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TFS-FedAuthRedirect"), "Suppress")
    }

    func testErrorsMapToActionableMessages() async throws {
        let cases: [(StubAzureHTTPClient.Response, PullRequestProviderError)] = [
            (.json("{}", statusCode: 401), .reauthorizationRequired),
            (.init(statusCode: 203, data: Data("<html>".utf8), contentType: "text/html"), .reauthorizationRequired),
            (.json(#"{"message":"denied"}"#, statusCode: 403), .permissionDenied),
            (.json("{}", statusCode: 404), .repositoryUnavailable),
            (.json(#"{"message":"TF401019: The Git repository does not exist."}"#, statusCode: 400),
             .providerMessage("TF401019: The Git repository does not exist.")),
            (.json("{}", statusCode: 500), .providerMessage("Azure DevOps request failed (HTTP 500).")),
        ]
        for (response, expected) in cases {
            let service = AzureReposPullRequestService(httpClient: StubAzureHTTPClient { _ in response })
            do {
                _ = try await service.listPullRequests(
                    repository: makeRepository(), token: makeToken(), filter: .all, page: 1, perPage: 30
                )
                XCTFail("Expected \(expected)")
            } catch let error as PullRequestProviderError {
                XCTAssertEqual(error, expected)
                XCTAssertFalse(error.localizedDescription.contains("secret-pat"))
            }
        }
    }

    func testWriteWithoutPermissionNamesCodeScope() async throws {
        let service = AzureReposPullRequestService(httpClient: StubAzureHTTPClient { _ in
            .json(#"{"message":"forbidden"}"#, statusCode: 403)
        })

        do {
            try await service.createComment(
                body: "Hi", on: makeSummary(), repository: makeRepository(), token: makeToken()
            )
            XCTFail("Expected a permission error")
        } catch let error as PullRequestProviderError {
            XCTAssertEqual(error, .providerMessage("The personal access token needs the Code (Read & Write) scope."))
        }
    }

    // MARK: - List

    func testListMapsStatesBranchesReadinessAndPaging() async throws {
        let client = StubAzureHTTPClient { _ in
            .json("""
            {"value":[
              \(pullRequestJSON(id: 1, status: "active", mergeStatus: "succeeded")),
              \(pullRequestJSON(id: 2, status: "active", isDraft: true, mergeStatus: "conflicts")),
              \(pullRequestJSON(id: 3, status: "completed", closedDate: "2026-07-03T10:00:00.1234567Z")),
              \(pullRequestJSON(id: 4, status: "abandoned"))
            ]}
            """)
        }
        let service = AzureReposPullRequestService(httpClient: client)

        let page = try await service.listPullRequests(
            repository: makeRepository(), token: makeToken(), filter: .closed, page: 2, perPage: 3
        )

        XCTAssertEqual(queryItems(try XCTUnwrap(client.requests.first?.url))["searchCriteria.status"], "all")
        XCTAssertEqual(queryItems(try XCTUnwrap(client.requests.first?.url))["$skip"], "3")
        XCTAssertEqual(page.items.map(\.number), [1, 2, 3])
        XCTAssertTrue(page.hasNextPage)
        XCTAssertTrue(page.hasPreviousPage)
        XCTAssertEqual(page.items.map(\.state), [.open, .draft, .merged])
        XCTAssertEqual(page.items.map(\.mergeReadiness), [.ready, .blocked, .unknown])

        let first = page.items[0]
        XCTAssertEqual(first.title, "Pull request 1")
        XCTAssertEqual(first.source.ref, "feature/login")
        XCTAssertEqual(first.target.ref, "main")
        XCTAssertEqual(first.source.sha, "source-sha")
        XCTAssertEqual(first.author.username, "user@example.com")
        XCTAssertEqual(
            first.webURL.absoluteString,
            "https://dev.azure.com/trantienthanh1998/ChatApp/_git/ChatApp/pullrequest/1"
        )
        XCTAssertNotNil(page.items[2].mergedAt)
    }

    func testListWithoutExtraItemHasNoNextPage() async throws {
        let service = AzureReposPullRequestService(httpClient: StubAzureHTTPClient { _ in
            .json(#"{"value":[\#(pullRequestJSON(id: 1, status: "active"))]}"#)
        })

        let page = try await service.listPullRequests(
            repository: makeRepository(), token: makeToken(), filter: .open, page: 1, perPage: 30
        )

        XCTAssertEqual(page.items.count, 1)
        XCTAssertFalse(page.hasNextPage)
        XCTAssertFalse(page.hasPreviousPage)
    }

    // MARK: - Branch lookup

    func testOpenPullRequestQueriesBySourceBranchAndPrefersActive() async throws {
        let client = StubAzureHTTPClient { _ in
            .json("""
            {"value":[
              \(pullRequestJSON(id: 7, status: "completed")),
              \(pullRequestJSON(id: 9, status: "active"))
            ]}
            """)
        }
        let service = AzureReposPullRequestService(httpClient: client)

        let result = try await service.openPullRequest(
            repository: makeRepository(), token: makeToken(), sourceBranch: "feature/login"
        )

        XCTAssertEqual(result?.number, 9)
        let query = queryItems(try XCTUnwrap(client.requests.first?.url))
        XCTAssertEqual(query["searchCriteria.sourceRefName"], "refs/heads/feature/login")
        XCTAssertEqual(query["searchCriteria.status"], "all")
    }

    func testOpenPullRequestFallsBackToCompletedAndReturnsNilWithoutMatches() async throws {
        let completed = AzureReposPullRequestService(httpClient: StubAzureHTTPClient { _ in
            .json(#"{"value":[\#(pullRequestJSON(id: 7, status: "completed"))]}"#)
        })
        let empty = AzureReposPullRequestService(httpClient: StubAzureHTTPClient { _ in .json(#"{"value":[]}"#) })

        let fallback = try await completed.openPullRequest(
            repository: makeRepository(), token: makeToken(), sourceBranch: "feature/login"
        )
        let none = try await empty.openPullRequest(
            repository: makeRepository(), token: makeToken(), sourceBranch: "feature/new"
        )

        XCTAssertEqual(fallback?.number, 7)
        XCTAssertNil(none)
    }

    // MARK: - Detail

    func testDetailKeepsTextCommentsAndMapsFileContext() async throws {
        let client = StubAzureHTTPClient { request in
            if request.url!.path.hasSuffix("/threads") {
                return .json("""
                {"value":[
                  {"id":5,"publishedDate":"2026-07-02T10:00:00Z","comments":[
                    {"id":1,"author":{"displayName":"Ada","uniqueName":"ada@example.com"},"content":"Second","publishedDate":"2026-07-02T10:00:00.5Z","commentType":"text"},
                    {"id":2,"author":{"displayName":"Ada"},"content":"Removed","publishedDate":"2026-07-02T11:00:00Z","commentType":"text","isDeleted":true}
                  ]},
                  {"id":6,"publishedDate":"2026-07-01T10:00:00Z","comments":[
                    {"id":1,"author":{"displayName":"Azure"},"content":"Ada voted 10","publishedDate":"2026-07-01T09:00:00Z","commentType":"system"}
                  ]},
                  {"id":7,"publishedDate":"2026-07-01T10:00:00Z",
                   "threadContext":{"filePath":"/Sources/App.swift","rightFileStart":{"line":12,"offset":1}},
                   "comments":[
                    {"id":1,"author":{"uniqueName":"bob@example.com"},"content":"First","publishedDate":"2026-07-01T10:00:00Z","commentType":"text"}
                  ]},
                  {"id":8,"isDeleted":true,"publishedDate":"2026-07-01T10:00:00Z","comments":[
                    {"id":1,"content":"Gone","publishedDate":"2026-07-01T10:00:00Z","commentType":"text"}
                  ]}
                ]}
                """)
            }
            return .json(pullRequestJSON(
                id: 42, status: "active",
                extra: #","description":"Body text","reviewers":[{"displayName":"Ada","uniqueName":"ada@example.com","vote":10}]"#
            ))
        }
        let service = AzureReposPullRequestService(httpClient: client)

        let detail = try await service.pullRequestDetail(repository: makeRepository(), token: makeToken(), number: 42)

        XCTAssertEqual(detail.body, "Body text")
        XCTAssertEqual(detail.reviewers.map(\.username), ["ada@example.com"])
        XCTAssertEqual(detail.assignees, [])
        XCTAssertEqual(detail.comments.map(\.body), ["First", "Second"])
        XCTAssertEqual(detail.comments.map(\.id), [7001, 5001])
        let context = try XCTUnwrap(detail.comments[0].reviewContext)
        XCTAssertEqual(context.path, "Sources/App.swift")
        XCTAssertEqual(context.line, 12)
        XCTAssertEqual(context.side, "RIGHT")
        XCTAssertNil(detail.comments[1].reviewContext)
        XCTAssertEqual(queryItems(detail.comments[0].webURL)["discussionId"], "7")
    }

    // MARK: - Changes

    func testChangesBuildDiffsForTextFilesAndSkipBinaryAndLargeFiles() async throws {
        let large = String(repeating: "x", count: AzureReposPullRequestService.maximumDiffFileBytes + 1)
        let contents: [String: Data] = [
            "/README.md@base": Data("one\ntwo\n".utf8),
            "/README.md@head": Data("one\nthree\n".utf8),
            "/old.txt@base": Data("keep\nold\n".utf8),
            "/new.txt@head": Data("keep\nnew\n".utf8),
            "/logo.png@head": Data([0x89, 0x50, 0x00, 0x01]),
            "/big.txt@base": Data("small\n".utf8),
            "/big.txt@head": Data(large.utf8),
        ]
        let client = StubAzureHTTPClient { request in
            let url = request.url!
            if url.path.hasSuffix("/iterations") {
                return .json("""
                {"value":[
                  {"id":1,"sourceRefCommit":{"commitId":"old-head"},"commonRefCommit":{"commitId":"old-base"}},
                  {"id":2,"sourceRefCommit":{"commitId":"head"},"commonRefCommit":{"commitId":"base"}}
                ]}
                """)
            }
            if url.path.hasSuffix("/iterations/2/changes") {
                return .json("""
                {"changeEntries":[
                  {"changeType":"edit","item":{"path":"/README.md"}},
                  {"changeType":"edit, rename","item":{"path":"/new.txt"},"originalPath":"/old.txt"},
                  {"changeType":"add","item":{"path":"/logo.png"}},
                  {"changeType":"edit","item":{"path":"/big.txt"}},
                  {"changeType":"add","item":{"path":"/Sources","isFolder":true}}
                ]}
                """)
            }
            if url.path.hasSuffix("/items") {
                let query = queryItems(url)
                let key = "\(query["path"] ?? "")@\(query["versionDescriptor.version"] ?? "")"
                guard let data = contents[key] else { return .json("{}", statusCode: 404) }
                return .init(statusCode: 200, data: data, contentType: "application/octet-stream")
            }
            return .json("{}", statusCode: 404)
        }
        let service = AzureReposPullRequestService(httpClient: client, unifiedDiff: { original, modified, path in
            try await GitStatusService.shared.unifiedDiff(original: original, modified: modified, path: path)
        })

        let files = try await service.pullRequestChanges(repository: makeRepository(), token: makeToken(), number: 42)

        XCTAssertEqual(files.map(\.path), ["README.md", "new.txt", "logo.png", "big.txt"])
        XCTAssertEqual(files.map(\.status), [.modified, .renamed, .added, .modified])

        let readme = files[0]
        XCTAssertEqual(readme.additions, 1)
        XCTAssertEqual(readme.deletions, 1)
        XCTAssertTrue(readme.patch?.contains("-two") == true)
        XCTAssertTrue(readme.patch?.contains("+three") == true)
        XCTAssertTrue(readme.patch?.contains("+++ b/README.md") == true)

        XCTAssertEqual(files[1].previousPath, "old.txt")
        XCTAssertTrue(files[1].patch?.contains("+new") == true)

        XCTAssertNil(files[2].patch)
        XCTAssertEqual(files[2].patchUnavailableReason, "Binary file. View the diff on Azure DevOps.")
        XCTAssertNil(files[3].patch)
        XCTAssertEqual(files[3].patchUnavailableReason, "This file is larger than 1 MB. View the diff on Azure DevOps.")

        let itemRequests = client.requests.filter { $0.url!.path.hasSuffix("/items") }
        XCTAssertTrue(itemRequests.allSatisfy { queryItems($0.url!)["versionDescriptor.version"] != "old-head" })
        XCTAssertTrue(itemRequests.allSatisfy { $0.value(forHTTPHeaderField: "Accept") == "application/octet-stream" })
    }

    func testChangesBeyondLimitAreListedWithoutDiffs() async throws {
        let count = AzureReposPullRequestService.maximumDiffFileCount + 1
        let entries = (0..<count).map { #"{"changeType":"edit","item":{"path":"/file\#($0).txt"}}"# }
        let client = StubAzureHTTPClient { request in
            let url = request.url!
            if url.path.hasSuffix("/iterations") {
                return .json(#"{"value":[{"id":1,"sourceRefCommit":{"commitId":"head"},"commonRefCommit":{"commitId":"base"}}]}"#)
            }
            if url.path.hasSuffix("/changes") {
                return .json(#"{"changeEntries":[\#(entries.joined(separator: ","))]}"#)
            }
            let version = queryItems(url)["versionDescriptor.version"] ?? ""
            return .init(statusCode: 200, data: Data("\(version)\n".utf8), contentType: "application/octet-stream")
        }
        let service = AzureReposPullRequestService(httpClient: client, unifiedDiff: { _, _, path in
            "diff --git a/\(path) b/\(path)\n@@ -1 +1 @@\n-base\n+head\n"
        })

        let files = try await service.pullRequestChanges(repository: makeRepository(), token: makeToken(), number: 42)

        XCTAssertEqual(files.count, count)
        XCTAssertEqual(files.prefix(count - 1).filter { $0.patch != nil }.count, count - 1)
        XCTAssertNil(files.last?.patch)
        XCTAssertEqual(
            files.last?.patchUnavailableReason,
            "This pull request has more than 100 files. View the diff on Azure DevOps."
        )
        XCTAssertEqual(files.map(\.path), (0..<count).map { "file\($0).txt" })
    }

    // MARK: - Writes

    func testCreateCommentPostsActiveThread() async throws {
        let client = StubAzureHTTPClient { _ in .json(#"{"id":11,"comments":[]}"#) }
        let service = AzureReposPullRequestService(httpClient: client)

        try await service.createComment(body: "Looks good", on: makeSummary(), repository: makeRepository(), token: makeToken())

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.hasSuffix("/pullrequests/42/threads"))
        let body = try jsonObject(request)
        XCTAssertEqual(body["status"] as? Int, 1)
        let comment = try XCTUnwrap((body["comments"] as? [[String: Any]])?.first)
        XCTAssertEqual(comment["content"] as? String, "Looks good")
        XCTAssertEqual(comment["parentCommentId"] as? Int, 0)
        XCTAssertEqual(comment["commentType"] as? Int, 1)
    }

    func testCreatePullRequestPostsRefNamesAndReturnsSummary() async throws {
        let client = StubAzureHTTPClient { _ in .json(pullRequestJSON(id: 77, status: "active")) }
        let service = AzureReposPullRequestService(httpClient: client)
        let draft = try PullRequestDraft(
            repository: makeRepository(), sourceBranch: "feature/login", targetBranch: "main",
            title: "Add login", body: "Details"
        )

        let result = try await service.createPullRequest(draft, token: makeToken())

        XCTAssertEqual(result.summary.number, 77)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.hasSuffix("/repositories/ChatApp/pullrequests"))
        let body = try jsonObject(request)
        XCTAssertEqual(body["sourceRefName"] as? String, "refs/heads/feature/login")
        XCTAssertEqual(body["targetRefName"] as? String, "refs/heads/main")
        XCTAssertEqual(body["title"] as? String, "Add login")
        XCTAssertEqual(body["description"] as? String, "Details")
    }

    func testCreateDuplicatePullRequestSurfacesAzureMessage() async throws {
        let message = "TF401179: An active pull request for the source and target branch already exists."
        let service = AzureReposPullRequestService(httpClient: StubAzureHTTPClient { _ in
            .json(#"{"message":"\#(message)"}"#, statusCode: 409)
        })
        let draft = try PullRequestDraft(
            repository: makeRepository(), sourceBranch: "feature/login", targetBranch: "main", title: "Add login", body: ""
        )

        do {
            _ = try await service.createPullRequest(draft, token: makeToken())
            XCTFail("Expected duplicate error")
        } catch let error as PullRequestProviderError {
            XCTAssertEqual(error, .providerMessage(message))
        }
    }

    func testMergeCompletesWithMergeCommitAndKeepsSourceBranch() async throws {
        let client = StubAzureHTTPClient { _ in .json(pullRequestJSON(id: 42, status: "completed")) }
        let service = AzureReposPullRequestService(httpClient: client, mergePollDelay: {})

        try await service.mergePullRequest(makeSummary(), repository: makeRepository(), token: makeToken())

        XCTAssertEqual(client.requests.count, 1)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertTrue(request.url!.path.hasSuffix("/pullrequests/42"))
        let body = try jsonObject(request)
        XCTAssertEqual(body["status"] as? String, "completed")
        XCTAssertEqual((body["lastMergeSourceCommit"] as? [String: Any])?["commitId"] as? String, "abc123")
        let options = try XCTUnwrap(body["completionOptions"] as? [String: Any])
        XCTAssertEqual(options["mergeStrategy"] as? String, "noFastForward")
        XCTAssertEqual(options["deleteSourceBranch"] as? Bool, false)
    }

    func testMergePollsUntilQueuedCompletionFinishes() async throws {
        var responses = [
            pullRequestJSON(id: 42, status: "active", mergeStatus: "queued"),
            pullRequestJSON(id: 42, status: "active", mergeStatus: "queued"),
            pullRequestJSON(id: 42, status: "completed", mergeStatus: "succeeded"),
        ]
        let client = StubAzureHTTPClient { _ in .json(responses.removeFirst()) }
        let service = AzureReposPullRequestService(httpClient: client, mergePollDelay: {})

        try await service.mergePullRequest(makeSummary(), repository: makeRepository(), token: makeToken())

        XCTAssertEqual(client.requests.map(\.httpMethod), ["PATCH", "GET", "GET"])
    }

    func testMergeReportsPolicyRejectionAndBlockingMessage() async throws {
        let rejected = AzureReposPullRequestService(httpClient: StubAzureHTTPClient { _ in
            .json(pullRequestJSON(
                id: 42, status: "active", mergeStatus: "rejectedByPolicy",
                extra: #","mergeFailureMessage":"Required reviewers have not approved.""#
            ))
        }, mergePollDelay: {})
        let blocked = AzureReposPullRequestService(httpClient: StubAzureHTTPClient { _ in
            .json(#"{"message":"TF401027: Policy requires a minimum of 1 reviewer."}"#, statusCode: 400)
        }, mergePollDelay: {})

        for (service, expected) in [
            (rejected, "Required reviewers have not approved."),
            (blocked, "TF401027: Policy requires a minimum of 1 reviewer."),
        ] {
            do {
                try await service.mergePullRequest(makeSummary(), repository: makeRepository(), token: makeToken())
                XCTFail("Expected merge failure")
            } catch let error as PullRequestProviderError {
                XCTAssertEqual(error, .providerMessage(expected))
            }
        }
    }

    func testMergeTimesOutWhileAzureIsStillCompleting() async throws {
        let client = StubAzureHTTPClient { _ in .json(pullRequestJSON(id: 42, status: "active", mergeStatus: "queued")) }
        let service = AzureReposPullRequestService(httpClient: client, mergePollDelay: {})

        do {
            try await service.mergePullRequest(makeSummary(), repository: makeRepository(), token: makeToken())
            XCTFail("Expected timeout")
        } catch let error as PullRequestProviderError {
            XCTAssertEqual(error, .providerMessage("Azure DevOps is still completing the pull request. Refresh to see the result."))
        }
        XCTAssertEqual(client.requests.count, 1 + AzureReposPullRequestService.mergePollAttempts)
    }

    func testParsesAzureDatesWithSevenFractionalDigits() {
        XCTAssertEqual(
            AzureReposPullRequestService.parseDate("2026-07-01T09:10:11.1234567Z"),
            ISO8601DateFormatter().date(from: "2026-07-01T09:10:11Z")
        )
        XCTAssertNotNil(AzureReposPullRequestService.parseDate("2026-07-01T09:10:11Z"))
    }

    // MARK: - Helpers

    private func makeRepository(project: String = "ChatApp") -> GitRepositoryIdentity {
        GitRepositoryIdentity(
            provider: .azureDevOps,
            hostURL: AzureReposRemote.organizationURL("Trantienthanh1998"),
            owner: project,
            name: "ChatApp"
        )
    }

    private func makeToken() -> GitProviderToken {
        GitProviderToken(accessToken: "secret-pat", refreshToken: nil, expiresAt: nil, tokenType: "Basic")
    }

    private func makeSummary() -> PullRequestSummary {
        PullRequestSummary(
            number: 42,
            title: "Add login",
            state: .open,
            author: PullRequestAuthor(username: "user@example.com", avatarURL: nil),
            source: PullRequestBranchRef(label: "feature/login", ref: "feature/login", sha: "abc123"),
            target: PullRequestBranchRef(label: "main", ref: "main", sha: "def456"),
            webURL: URL(string: "https://dev.azure.com/trantienthanh1998/ChatApp/_git/ChatApp/pullrequest/42")!,
            updatedAt: Date()
        )
    }

    private func jsonObject(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}

private func queryItems(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}

private func pullRequestJSON(
    id: Int,
    status: String,
    isDraft: Bool = false,
    mergeStatus: String? = nil,
    closedDate: String? = nil,
    extra: String = ""
) -> String {
    """
    {"pullRequestId":\(id),"title":"Pull request \(id)","status":"\(status)","isDraft":\(isDraft),\
    "createdBy":{"displayName":"User","uniqueName":"user@example.com"},\
    "creationDate":"2026-07-01T09:10:11.1234567Z",\
    \(closedDate.map { #""closedDate":"\#($0)","# } ?? "")\
    "sourceRefName":"refs/heads/feature/login","targetRefName":"refs/heads/main",\
    \(mergeStatus.map { #""mergeStatus":"\#($0)","# } ?? "")\
    "lastMergeSourceCommit":{"commitId":"source-sha"},"lastMergeTargetCommit":{"commitId":"target-sha"}\(extra)}
    """
}

final class StubAzureHTTPClient: GitProviderHTTPClient {
    struct Response {
        var statusCode: Int
        var data: Data
        var contentType: String

        static func json(_ body: String, statusCode: Int = 200) -> Response {
            Response(statusCode: statusCode, data: Data(body.utf8), contentType: "application/json; charset=utf-8")
        }
    }

    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    private let handler: (URLRequest) -> Response

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    init(handler: @escaping (URLRequest) -> Response) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // The changes test fetches file contents concurrently.
        let response = lock.withLock {
            recordedRequests.append(request)
            return handler(request)
        }
        let httpResponse = try XCTUnwrap(HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": response.contentType]
        ))
        return (response.data, httpResponse)
    }
}
