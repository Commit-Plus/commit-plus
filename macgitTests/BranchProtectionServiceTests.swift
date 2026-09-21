// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class BranchProtectionServiceTests: XCTestCase {
    func testProtectedBranchAndEncodedBranchName() async throws {
        let client = ProtectionHTTPClient(code: 200, body: #"{"protected":true}"#)
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(from: "git@github.com:team/repo.git"))
        let status = await BranchProtectionService(httpClient: client).status(branch: "release/1.0", identity: identity, token: nil)
        XCTAssertEqual(status, .protected)
        XCTAssertTrue(client.request?.url?.absoluteString.hasSuffix("branches/release%2F1%2E0") == true)
    }

    func testUnprotectedBranchIsNotInferredFromMainName() async throws {
        let client = ProtectionHTTPClient(code: 200, body: #"{"protected":false}"#)
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(from: "https://github.com/team/repo.git"))
        let status = await BranchProtectionService(httpClient: client).status(branch: "main", identity: identity, token: nil)
        XCTAssertEqual(status, .unprotected)
    }

    func testAuthorizationErrorsAndMissingFieldsAreUnknown() async throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(from: "https://github.com/team/repo.git"))
        for code in [401, 403, 404, 500, 200] {
            let client = ProtectionHTTPClient(code: code, body: "{}")
            let status = await BranchProtectionService(httpClient: client).status(branch: "main", identity: identity, token: nil)
            XCTAssertEqual(status, .unavailable)
        }
    }

    func testGitLabNestedProjectAndToken() async throws {
        let client = ProtectionHTTPClient(code: 200, body: #"{"protected":true}"#)
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(from: "git@gitlab.com:team/subgroup/repo.git"))
        let token = GitProviderToken(accessToken: "test-token", refreshToken: nil, expiresAt: nil, tokenType: "bearer")
        let status = await BranchProtectionService(httpClient: client).status(branch: "main", identity: identity, token: token)
        XCTAssertEqual(status, .protected)
        XCTAssertTrue(client.request?.url?.absoluteString.contains("projects/team%2Fsubgroup%2Frepo/") == true)
        XCTAssertEqual(client.request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    func testUsesUpstreamBranchMappingBeforeDefaultRemote() {
        let target = ProtectedBranchCommitController.target(branch: "local-main", upstream: "upstream/release/main", remotes: ["origin", "upstream"], preferredRemote: "origin")
        XCTAssertEqual(target?.remote, "upstream")
        XCTAssertEqual(target?.branch, "release/main")
        let fallback = ProtectedBranchCommitController.target(branch: "feature", upstream: nil, remotes: ["origin", "upstream"], preferredRemote: "upstream")
        XCTAssertEqual(fallback?.remote, "upstream")
        XCTAssertEqual(fallback?.branch, "feature")
        XCTAssertNil(ProtectedBranchCommitController.target(branch: "main", upstream: nil, remotes: [], preferredRemote: nil))
    }
}

private final class ProtectionHTTPClient: GitProviderHTTPClient {
    let code: Int
    let body: String
    var request: URLRequest?

    init(code: Int, body: String) {
        self.code = code
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}
