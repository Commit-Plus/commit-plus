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

final class AzureReposRepositoryVisibilityServiceTests: XCTestCase {
    func testPublicProjectResolvesAnonymously() async throws {
        let client = StubAzureHTTPClient { _ in
            .json(#"{"id":"repo","name":"ChatApp","project":{"name":"Open Source","visibility":"public"}}"#)
        }
        let service = AzureReposRepositoryVisibilityService(httpClient: client)

        let visibility = try await service.visibility(for: makeRepository(), token: nil)

        XCTAssertEqual(visibility, .public)
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://dev.azure.com/trantienthanh1998/ChatApp/_apis/git/repositories/ChatApp?api-version=7.1"
        )
    }

    func testPrivateProjectResolvesWithToken() async throws {
        let client = StubAzureHTTPClient { _ in
            .json(#"{"id":"repo","name":"ChatApp","project":{"name":"ChatApp","visibility":"private"}}"#)
        }
        let service = AzureReposRepositoryVisibilityService(httpClient: client)

        let visibility = try await service.visibility(for: makeRepository(), token: makeToken())

        XCTAssertEqual(visibility, .private)
        XCTAssertEqual(
            client.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Basic " + Data(":secret-pat".utf8).base64EncodedString()
        )
    }

    func testAnonymousRejectionRequiresAuthorization() async throws {
        for response in [
            StubAzureHTTPClient.Response(statusCode: 203, data: Data("<html>".utf8), contentType: "text/html"),
            .json("{}", statusCode: 401),
        ] {
            let service = AzureReposRepositoryVisibilityService(httpClient: StubAzureHTTPClient { _ in response })
            do {
                _ = try await service.visibility(for: makeRepository(), token: nil)
                XCTFail("Expected authorization error")
            } catch let error as RepositoryVisibilityProviderError {
                XCTAssertEqual(error, .authorizationRequired)
            }
        }
    }

    func testMissingRepositoryIsUnavailable() async throws {
        let service = AzureReposRepositoryVisibilityService(httpClient: StubAzureHTTPClient { _ in
            .json(#"{"message":"TF401019"}"#, statusCode: 404)
        })

        do {
            _ = try await service.visibility(for: makeRepository(), token: makeToken())
            XCTFail("Expected unavailable error")
        } catch let error as RepositoryVisibilityProviderError {
            XCTAssertEqual(error, .repositoryUnavailable)
        }
    }

    private func makeRepository() -> GitRepositoryIdentity {
        GitRepositoryIdentity(
            provider: .azureDevOps,
            hostURL: AzureReposRemote.organizationURL("Trantienthanh1998"),
            owner: "ChatApp",
            name: "ChatApp"
        )
    }

    private func makeToken() -> GitProviderToken {
        GitProviderToken(accessToken: "secret-pat", refreshToken: nil, expiresAt: nil, tokenType: "Basic")
    }
}
