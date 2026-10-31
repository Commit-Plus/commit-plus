// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class StubHostedIssueHTTPClient: GitProviderHTTPClient, @unchecked Sendable {
    struct Response {
        var statusCode: Int
        var data: Data
        var headers: [String: String]

        static func json(_ statusCode: Int, _ body: String, headers: [String: String] = [:]) -> Response {
            Response(statusCode: statusCode, data: Data(body.utf8), headers: headers)
        }
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            XCTFail("Unexpected request \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
            throw URLError(.badServerResponse)
        }
        let response = responses.removeFirst()
        let httpResponse = try XCTUnwrap(HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: response.headers
        ))
        return (response.data, httpResponse)
    }

    func query(_ index: Int) -> [String: String] {
        let items = URLComponents(url: requests[index].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func jsonBody(_ index: Int) -> [String: Any] {
        guard let data = requests[index].httpBody,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
}

enum HostedIssueFixtures {
    static let token = GitProviderToken(accessToken: "secret-token", refreshToken: nil, expiresAt: nil, tokenType: "bearer")

    static func repository(_ provider: GitProviderKind, host: String, owner: String, name: String) -> GitRepositoryIdentity {
        GitRepositoryIdentity(provider: provider, hostURL: URL(string: host)!, owner: owner, name: name)
    }

    static func account(_ provider: GitProviderKind, host: String, username: String = "octocat", userID: String = "1") -> GitProviderAccount {
        GitProviderAccount(
            id: "\(provider.rawValue)-\(username)",
            macgitUID: "uid",
            provider: provider,
            hostURL: URL(string: host)!,
            providerUserID: userID,
            username: username,
            displayName: nil,
            avatarURL: nil,
            scopes: ["repo"],
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: Date(timeIntervalSince1970: 0),
            lastValidatedAt: nil
        )
    }
}
