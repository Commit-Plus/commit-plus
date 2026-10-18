// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class BranchMergeEvidenceServiceTests: XCTestCase {
    func testGitHubRequiresMergedPRAndExactSourceRepository() async throws {
        let client = BranchMergeHTTPClient(data: Data(#"""
        [
          {"number":57,"title":"Merged feature","merged_at":"2026-10-14T10:00:00Z","html_url":"https://github.com/acme/app/pull/57",
           "head":{"ref":"feature","sha":"abc123","repo":{"full_name":"acme/app"}},"base":{"ref":"main"}},
          {"number":58,"title":"Closed only","merged_at":null,"html_url":"https://github.com/acme/app/pull/58",
           "head":{"ref":"feature","sha":"def456","repo":{"full_name":"acme/app"}},"base":{"ref":"main"}},
          {"number":59,"title":"Fork collision","merged_at":"2026-10-14T10:00:00Z","html_url":"https://github.com/acme/app/pull/59",
           "head":{"ref":"feature","sha":"abc123","repo":{"full_name":"other/app"}},"base":{"ref":"main"}}
        ]
        """#.utf8), statusCode: 200)
        let repository = GitRepositoryIdentity(provider: .github, hostURL: URL(string: "https://github.com")!, owner: "acme", name: "app")

        let changes = try await GitHubBranchMergeEvidenceService(httpClient: client).mergedChanges(
            targetRepository: repository,
            sourceRepository: repository,
            sourceBranch: "feature",
            token: GitProviderToken(accessToken: "secret", tokenType: "Bearer")
        )

        XCTAssertEqual(changes.map(\.number), [57])
        XCTAssertEqual(changes.first?.sourceSHA, "abc123")
        XCTAssertTrue(client.lastRequest?.url?.absoluteString.contains("head=acme:feature") == true)
    }

    func testGitHubEnterpriseUsesConfiguredAPIBaseURL() async throws {
        let client = BranchMergeHTTPClient(data: Data("[]".utf8), statusCode: 200)
        let repository = GitRepositoryIdentity(provider: .github, hostURL: URL(string: "https://github.company.test")!, owner: "team", name: "app")
        _ = try await GitHubBranchMergeEvidenceService(httpClient: client).mergedChanges(
            targetRepository: repository, sourceRepository: repository, sourceBranch: "feature",
            token: GitProviderToken(accessToken: "secret", tokenType: "Bearer")
        )
        XCTAssertEqual(client.lastRequest?.url?.host, "github.company.test")
        XCTAssertTrue(client.lastRequest?.url?.path.hasPrefix("/api/v3/repos/team/app/pulls") == true)
    }

    func testSelfHostedGitLabUsesHostSubpathAndRejectsClosedUnmerged() async throws {
        let client = BranchMergeHTTPClient(data: Data(#"""
        [
          {"iid":8,"title":"Merged feature","state":"merged","source_branch":"feature","target_branch":"main","sha":"abc123",
           "source_project_id":1,"target_project_id":1,"web_url":"https://gitlab.company.test/gitlab/team/app/-/merge_requests/8",
           "merged_at":"2026-10-14T10:00:00Z","references":{"full":"team/app!8"}},
          {"iid":9,"title":"Closed feature","state":"closed","source_branch":"feature","target_branch":"main","sha":"abc123",
           "source_project_id":1,"target_project_id":1,"web_url":"https://gitlab.company.test/gitlab/team/app/-/merge_requests/9",
           "merged_at":null,"references":{"full":"team/app!9"}}
        ]
        """#.utf8), statusCode: 200)
        let repository = GitRepositoryIdentity(provider: .gitlab, hostURL: URL(string: "https://gitlab.company.test/gitlab")!, owner: "team", name: "app")
        let changes = try await GitLabBranchMergeEvidenceService(httpClient: client).mergedChanges(
            targetRepository: repository, sourceRepository: repository, sourceBranch: "feature",
            token: GitProviderToken(accessToken: "secret", tokenType: "Bearer")
        )
        XCTAssertEqual(changes.map(\.number), [8])
        let requestURL = try XCTUnwrap(client.lastRequest?.url)
        let requestPath = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.percentEncodedPath
        XCTAssertTrue(requestPath?.hasPrefix("/gitlab/api/v4/projects/team%2Fapp/merge_requests") == true)
    }
}

private final class BranchMergeHTTPClient: GitProviderHTTPClient, @unchecked Sendable {
    let data: Data
    let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return (data, HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!)
    }
}

