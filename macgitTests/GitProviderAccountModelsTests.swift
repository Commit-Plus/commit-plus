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

final class GitProviderAccountModelsTests: XCTestCase {
    func testGitHubDotComHostNormalizesToHttpsBaseURL() {
        XCTAssertEqual(GitProviderHost.githubDotCom.baseURL.absoluteString, "https://github.com")
    }

    func testBitbucketDotOrgHostNormalizesToHttpsBaseURL() {
        XCTAssertEqual(GitProviderHost.bitbucketDotOrg.baseURL.absoluteString, "https://bitbucket.org")
    }

    func testSelfHostedGitLabHostPreservesHost() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://git.company.com/"))
        let host = GitProviderHost(kind: .gitlab, baseURL: baseURL)

        XCTAssertEqual(host.normalized.baseURL.absoluteString, "https://git.company.com")
    }

    func testProviderAccountRoundTripsCodable() throws {
        let account = GitProviderAccount(
            id: "connection-1",
            macgitUID: "macgit-user-1",
            provider: .github,
            hostURL: try XCTUnwrap(URL(string: "https://github.com")),
            providerUserID: "provider-user-42",
            username: "octocat",
            displayName: "The Octocat",
            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/583231"),
            scopes: ["repo", "read:user"],
            permissions: ["contents": "read", "pull_requests": "write"],
            tokenStatus: .valid,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(GitProviderAccount.self, from: data)

        XCTAssertEqual(decoded.providerUserID, account.providerUserID)
        XCTAssertEqual(decoded.username, account.username)
        XCTAssertEqual(decoded.scopes, account.scopes)
        XCTAssertEqual(decoded.permissions, account.permissions)
        XCTAssertEqual(decoded.tokenStatus, account.tokenStatus)
    }

    func testProviderAccountDefaultsTransportProtocolToHTTPSWhenDecodingOldPayload() throws {
        let payload = """
        {
          "id": "connection-1",
          "macgitUID": "macgit-user-1",
          "provider": "github",
          "hostURL": "https://github.com",
          "providerUserID": "provider-user-42",
          "username": "octocat",
          "displayName": "The Octocat",
          "avatarURL": null,
          "scopes": ["repo", "read:user"],
          "permissions": {"contents": "read"},
          "tokenStatus": "valid",
          "connectedAt": 1700000000,
          "lastValidatedAt": null
        }
        """

        let data = try XCTUnwrap(payload.data(using: .utf8))
        let decoded = try JSONDecoder().decode(GitProviderAccount.self, from: data)

        XCTAssertEqual(decoded.transportProtocol, .https)
    }

    func testProviderAccountRoundTripsSSHTransportProtocol() throws {
        let account = GitProviderAccount(
            id: "connection-1",
            macgitUID: "macgit-user-1",
            provider: .github,
            hostURL: try XCTUnwrap(URL(string: "https://github.com")),
            providerUserID: "provider-user-42",
            username: "octocat",
            displayName: "The Octocat",
            avatarURL: nil,
            scopes: ["repo", "read:user"],
            permissions: ["contents": "read"],
            tokenStatus: .valid,
            transportProtocol: .ssh,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )

        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(GitProviderAccount.self, from: data)

        XCTAssertEqual(decoded.transportProtocol, .ssh)
    }

    func testAzureDevOpsOrganizationHostIsNotSelfHosted() {
        let host = GitProviderHost(kind: .azureDevOps, baseURL: AzureReposRemote.organizationURL("Contoso"))

        XCTAssertFalse(host.isSelfHosted)
        XCTAssertEqual(host.baseURL.absoluteString, "https://dev.azure.com/contoso")
        XCTAssertEqual(GitProviderKind.azureDevOps.displayName, "Azure Repos")
    }

    func testAzureDevOpsAccountRoundTripsCodableWithAzureRawValue() throws {
        let account = GitProviderAccount(
            id: "connection-azure",
            macgitUID: "macgit-user-1",
            provider: .azureDevOps,
            hostURL: AzureReposRemote.organizationURL("Contoso"),
            providerUserID: "0f6c8f5e-0000-0000-0000-000000000001",
            username: "dev@contoso.com",
            displayName: "Dev",
            avatarURL: nil,
            scopes: [],
            permissions: ["authentication": "personalAccessToken"],
            tokenStatus: .valid,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )

        let data = try JSONEncoder().encode(account)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(GitProviderAccount.self, from: data)

        XCTAssertEqual(json["provider"] as? String, "azure")
        XCTAssertEqual(decoded, account)
    }

    func testUnavailableTokenStatusIsDistinctFromRevoked() {
        XCTAssertNotEqual(GitProviderTokenStatus.unavailableOnThisDevice, .revoked)
    }
}
