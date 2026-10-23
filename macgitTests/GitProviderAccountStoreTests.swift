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

import FirebaseFirestore
import XCTest
@testable import macgit

final class GitProviderAccountStoreTests: XCTestCase {
    func testFirestoreDocumentRoundTripsNonSecretMetadata() throws {
        let account = makeAccount()

        let data = GitProviderAccountDocument.encode(account)
        let decoded = try GitProviderAccountDocument.decode(
            data,
            id: account.id,
            macgitUID: account.macgitUID
        )

        XCTAssertEqual(decoded, account)
        XCTAssertNil(data["accessToken"])
        XCTAssertNil(data["refreshToken"])
    }

    func testFirestoreDocumentRejectsMalformedMetadata() {
        var data = GitProviderAccountDocument.encode(makeAccount())
        data["provider"] = "unsupported"

        XCTAssertThrowsError(
            try GitProviderAccountDocument.decode(data, id: "connection-1", macgitUID: "macgit-user-1")
        )
    }

    func testFirestoreDocumentRoundTripsBitbucketMetadata() throws {
        var account = makeAccount()
        account.provider = .bitbucket
        account.hostURL = URL(string: "https://bitbucket.org")!
        account.providerUserID = "Trantienthanh2412"
        account.username = "Trantienthanh2412"
        account.scopes = ["read:repository:bitbucket", "write:repository:bitbucket"]

        let data = GitProviderAccountDocument.encode(account)
        let decoded = try GitProviderAccountDocument.decode(
            data,
            id: account.id,
            macgitUID: account.macgitUID
        )

        XCTAssertEqual(decoded, account)
        XCTAssertNil(data["accessToken"])
    }

    func testFirestoreDocumentRoundTripsAzureDevOpsMetadata() throws {
        var account = makeAccount()
        account.provider = .azureDevOps
        account.hostURL = AzureReposRemote.organizationURL("Contoso")
        account.scopes = []
        account.permissions = ["authentication": "personalAccessToken"]

        let data = GitProviderAccountDocument.encode(account)
        let decoded = try GitProviderAccountDocument.decode(data, id: account.id, macgitUID: account.macgitUID)

        XCTAssertEqual(data["provider"] as? String, "azure")
        XCTAssertEqual(data["hostURL"] as? String, "https://dev.azure.com/contoso")
        XCTAssertEqual(decoded, account)
    }

    func testFirestoreAccountListSkipsUnknownProvidersButRejectsMalformedDocuments() throws {
        let account = makeAccount()
        var future = GitProviderAccountDocument.encode(account)
        future["provider"] = "provider-from-a-newer-version"

        let decoded = try GitProviderAccountDocument.decodeSupported(
            [(id: "future", data: future), (id: account.id, data: GitProviderAccountDocument.encode(account))],
            macgitUID: account.macgitUID
        )

        XCTAssertEqual(decoded, [account])
        var malformed = GitProviderAccountDocument.encode(account)
        malformed["provider"] = 42
        XCTAssertThrowsError(
            try GitProviderAccountDocument.decodeSupported([(id: "bad", data: malformed)], macgitUID: account.macgitUID)
        )
    }

    private func makeAccount() -> GitProviderAccount {
        GitProviderAccount(
            id: "connection-1",
            macgitUID: "macgit-user-1",
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: "583231",
            username: "octocat",
            displayName: "The Octocat",
            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/583231"),
            scopes: ["repo", "read:user"],
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }
}
