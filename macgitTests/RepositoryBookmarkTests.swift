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

final class RepositoryBookmarkTests: XCTestCase {
    func testIdentityNormalizesHTTPSAndSSHRemotesToSameRepository() throws {
        let https = try XCTUnwrap(
            RepositoryBookmarkIdentity.resolve(
                remoteURLString: "https://github.com/OpenAI/Codex.git"
            )
        )
        let ssh = try XCTUnwrap(
            RepositoryBookmarkIdentity.resolve(
                remoteURLString: "git@github.com:openai/codex.git"
            )
        )

        XCTAssertEqual(https.canonicalKey, ssh.canonicalKey)
        XCTAssertEqual(https.documentID, ssh.documentID)
        XCTAssertEqual(https.provider, .github)
        XCTAssertEqual(https.canonicalRemoteURL.absoluteString, "https://github.com/OpenAI/Codex.git")
    }

    func testIdentitySupportsGitLabGroupsAndBitbucket() throws {
        let gitLab = try XCTUnwrap(
            RepositoryBookmarkIdentity.resolve(
                remoteURLString: "git@gitlab.com:team/platform/client.git"
            )
        )
        let bitbucket = try XCTUnwrap(
            RepositoryBookmarkIdentity.resolve(
                remoteURLString: "https://bitbucket.org/team/client.git"
            )
        )

        XCTAssertEqual(gitLab.ownerPath, "team/platform")
        XCTAssertEqual(gitLab.provider, .gitlab)
        XCTAssertEqual(bitbucket.provider, .bitbucket)
    }

    func testIdentityRejectsLocalAndHostOnlyURLs() {
        XCTAssertNil(
            RepositoryBookmarkIdentity.resolve(remoteURLString: "file:///tmp/repository")
        )
        XCTAssertNil(
            RepositoryBookmarkIdentity.resolve(remoteURLString: "https://github.com")
        )
    }

    func testDocumentRoundTripsApprovedMetadata() throws {
        let identity = try XCTUnwrap(
            RepositoryBookmarkIdentity.resolve(
                remoteURLString: "https://github.com/openai/codex.git"
            )
        )
        let bookmark = RepositoryBookmark(
            identity: identity,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        var encoded = RepositoryBookmarkDocument.encode(bookmark)
        encoded["updatedAt"] = Timestamp(date: bookmark.updatedAt)

        let decoded = try RepositoryBookmarkDocument.decode(encoded, id: bookmark.id)

        XCTAssertEqual(decoded, bookmark)
        XCTAssertNil(encoded["localPath"])
        XCTAssertNil(encoded["accessToken"])
    }

    @MainActor
    func testControllerKeepsLocalFolderMappingOutOfBookmarkModel() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let controller = RepositoryBookmarkController(
            cloudStore: nil,
            dataStore: fixture.store
        )
        let identity = try XCTUnwrap(
            RepositoryBookmarkIdentity.resolve(
                remoteURLString: "https://github.com/openai/codex.git"
            )
        )
        let bookmark = RepositoryBookmark(identity: identity)
        let localURL = URL(fileURLWithPath: "/Users/test/Project/codex", isDirectory: true)

        try await controller.link(bookmark, to: localURL)

        XCTAssertEqual(controller.localURL(for: bookmark), localURL)
        XCTAssertFalse(bookmark.remoteURL.absoluteString.contains("/Users/test"))
    }
}
