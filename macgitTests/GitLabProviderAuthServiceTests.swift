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

final class GitLabProviderAuthServiceTests: XCTestCase {
    func testDeviceAuthorizationRequestsUserCodeWithClientIDScopesAndHost() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(
                statusCode: 200,
                body: #"""
                {
                  "device_code": "gitlab-device-code",
                  "user_code": "A1B2-C3D4",
                  "verification_uri": "https://gitlab.example.com/oauth/device",
                  "verification_uri_complete": "https://gitlab.example.com/oauth/device?user_code=A1B2-C3D4",
                  "expires_in": 300,
                  "interval": 5
                }
                """#
            )
        ])
        let service = makeService(httpClient: client)

        let authorization = try await service.requestDeviceAuthorization(host: makeHost())

        let request = try XCTUnwrap(client.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://gitlab.example.com/oauth/authorize_device")
        XCTAssertTrue(body.contains("client_id=gitlab-client-id"))
        XCTAssertTrue(body.contains("scope=api%20read_user%20write_repository"))
        XCTAssertEqual(authorization.provider, .gitlab)
        XCTAssertEqual(authorization.deviceCode, "gitlab-device-code")
        XCTAssertEqual(authorization.userCode, "A1B2-C3D4")
        XCTAssertEqual(authorization.verificationURI.absoluteString, "https://gitlab.example.com/oauth/device?user_code=A1B2-C3D4")
        XCTAssertEqual(authorization.expiresIn, 300)
        XCTAssertEqual(authorization.interval, 5)
    }

    func testPollDeviceAuthorizationUsesConfiguredHostAndDeviceCode() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(
                statusCode: 200,
                body: #"{"access_token":"secret-token","refresh_token":"refresh-token","expires_in":7200,"token_type":"Bearer"}"#
            )
        ])
        let service = makeService(httpClient: client)

        let token = try await service.pollDeviceAuthorization(
            GitProviderDeviceAuthorization(
                provider: .gitlab,
                deviceCode: "gitlab-device-code",
                userCode: "A1B2-C3D4",
                verificationURI: URL(string: "https://gitlab.example.com/oauth/device")!,
                expiresIn: 300,
                interval: 5
            ),
            host: makeHost()
        )

        let request = try XCTUnwrap(client.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://gitlab.example.com/oauth/token")
        XCTAssertTrue(body.contains("client_id=gitlab-client-id"))
        XCTAssertTrue(body.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"))
        XCTAssertTrue(body.contains("device_code=gitlab-device-code"))
        XCTAssertFalse(body.contains("client_secret"))
        XCTAssertEqual(token.accessToken, "secret-token")
        XCTAssertEqual(token.refreshToken, "refresh-token")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 1_700_007_200))
        XCTAssertEqual(token.tokenType, "Bearer")
    }

    func testPollDeviceAuthorizationMapsPendingResponseBeforeHTTPFailure() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(statusCode: 400, body: #"{"error":"authorization_pending","error_description":"Pending"}"#)
        ])
        let service = makeService(httpClient: client)

        do {
            _ = try await service.pollDeviceAuthorization(
                GitProviderDeviceAuthorization(
                    provider: .gitlab,
                    deviceCode: "gitlab-device-code",
                    userCode: "A1B2-C3D4",
                    verificationURI: URL(string: "https://gitlab.example.com/oauth/device")!,
                    expiresIn: 300,
                    interval: 5
                ),
                host: makeHost()
            )
            XCTFail("Expected pending authorization to throw")
        } catch {
            XCTAssertEqual(error as? GitProviderAuthError, .authorizationPending)
        }
    }

    func testRefreshTokenRotatesGitLabOAuthCredentials() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(
                statusCode: 200,
                body: #"{"access_token":"new-token","refresh_token":"new-refresh-token","expires_in":7200,"token_type":"Bearer"}"#
            )
        ])
        let service = makeService(httpClient: client)

        let token = try await service.refreshToken("old-refresh-token", host: makeHost())

        let request = try XCTUnwrap(client.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(request.url?.absoluteString, "https://gitlab.example.com/oauth/token")
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("refresh_token=old-refresh-token"))
        XCTAssertEqual(token.accessToken, "new-token")
        XCTAssertEqual(token.refreshToken, "new-refresh-token")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 1_700_007_200))
    }

    func testInvalidRefreshTokenRequiresReauthorization() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(statusCode: 400, body: #"{"error":"invalid_grant","error_description":"Token is invalid"}"#)
        ])
        let service = makeService(httpClient: client)

        do {
            _ = try await service.refreshToken("invalid-refresh-token", host: makeHost())
            XCTFail("Expected invalid refresh token to throw")
        } catch {
            XCTAssertEqual(error as? GitProviderAuthError, .reauthorizationRequired)
        }
    }

    func testDeviceAuthorizationSurfacesInvalidClientMessage() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(
                statusCode: 401,
                body: #"{"error":"invalid_client","error_description":"Client authentication failed due to unknown client, no client authentication included, or unsupported authentication method."}"#
            )
        ])
        let service = makeService(httpClient: client)

        do {
            _ = try await service.requestDeviceAuthorization(host: makeHost())
            XCTFail("Expected invalid client response to throw")
        } catch {
            XCTAssertEqual(
                error as? GitProviderAuthError,
                .providerMessage("Client authentication failed due to unknown client, no client authentication included, or unsupported authentication method.")
            )
        }
    }

    func testProfileResponseCreatesGitLabProviderAccount() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(
                statusCode: 200,
                body: #"{"id":42,"username":"tanuki","name":"GitLab User","avatar_url":"https://gitlab.com/uploads/-/system/user/avatar/42/avatar.png"}"#
            )
        ])
        let service = makeService(httpClient: client)

        let account = try await service.fetchAccount(
            token: makeToken(),
            macgitUID: "macgit-user-1",
            host: .gitlabDotCom
        )

        XCTAssertEqual(account.id, "macgit-user-1:gitlab:gitlab.com:42")
        XCTAssertEqual(account.provider, .gitlab)
        XCTAssertEqual(account.hostURL, URL(string: "https://gitlab.com"))
        XCTAssertEqual(account.providerUserID, "42")
        XCTAssertEqual(account.username, "tanuki")
        XCTAssertEqual(account.displayName, "GitLab User")
        XCTAssertEqual(account.avatarURL?.absoluteString, "https://gitlab.com/uploads/-/system/user/avatar/42/avatar.png")
        XCTAssertEqual(account.scopes, ["api", "read_user", "write_repository"])
        XCTAssertEqual(account.tokenStatus, .valid)
        XCTAssertEqual(account.connectedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(account.lastValidatedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(client.requests.first?.url?.absoluteString, "https://gitlab.com/api/v4/user")
        XCTAssertEqual(client.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testSelfHostedHostIsPreserved() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(statusCode: 200, body: #"{"id":99,"username":"admin","name":null,"avatar_url":null}"#)
        ])
        let service = makeService(httpClient: client)
        let host = GitProviderHost(
            kind: .gitlab,
            baseURL: try XCTUnwrap(URL(string: "https://gitlab.example.com/gitlab/"))
        )

        let account = try await service.fetchAccount(
            token: makeToken(),
            macgitUID: "macgit-user-1",
            host: host
        )

        XCTAssertEqual(account.id, "macgit-user-1:gitlab:gitlab.example.com:99")
        XCTAssertEqual(account.hostURL.absoluteString, "https://gitlab.example.com")
        XCTAssertEqual(client.requests.first?.url?.absoluteString, "https://gitlab.example.com/api/v4/user")
    }

    func testUnauthorizedMapsToReauthorizationRequired() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(statusCode: 401, body: #"{"message":"401 Unauthorized"}"#)
        ])
        let service = makeService(httpClient: client)

        do {
            _ = try await service.fetchAccount(
                token: makeToken(),
                macgitUID: "macgit-user-1",
                host: .gitlabDotCom
            )
            XCTFail("Expected fetchAccount to throw")
        } catch {
            XCTAssertEqual(error as? GitProviderAuthError, .reauthorizationRequired)
        }
    }

    private func makeService(httpClient: GitProviderHTTPClient) -> GitLabProviderAuthService {
        GitLabProviderAuthService(
            configuration: GitLabProviderAuthConfiguration(
                clientID: "gitlab-client-id",
                redirectURI: URL(string: "macgit://git-provider/oauth/callback")!,
                scopes: ["api", "read_user", "write_repository"]
            ),
            httpClient: httpClient,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private func makeHost() -> GitProviderHost {
        GitProviderHost(
            kind: .gitlab,
            baseURL: URL(string: "https://gitlab.example.com")!
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
}

private final class StubGitLabAuthHTTPClient: GitProviderHTTPClient {
    struct Response {
        var statusCode: Int
        var data: Data

        static func json(statusCode: Int, body: String) -> Response {
            Response(statusCode: statusCode, data: Data(body.utf8))
        }
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(responses: [Response] = []) {
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
                headerFields: [:]
            )
        )
        return (response.data, httpResponse)
    }
}
