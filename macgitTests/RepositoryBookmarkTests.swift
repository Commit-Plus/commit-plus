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
    @MainActor
    func testRepairReplacesOldBookmarkAndPersistsOfflineSyncMarkers() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repo = try makeMultiRemoteRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let old = try makeBookmark("https://github.com/team/old-client.git")
        try await fixture.store.transaction { transaction in
            try transaction.set(old, in: "bookmarks", id: old.id)
            try transaction.set(repo.path, in: "bookmarkPaths", id: old.id)
        }
        let controller = RepositoryBookmarkController(cloudStore: nil, dataStore: fixture.store)
        try controller.load()
        await controller.linkMatchingBookmarks(to: [repo])
        XCTAssertEqual(controller.bookmarksNeedingAttention(at: repo).map(\.id), [old.id])
        let remotes = try await GitStatusService.shared.repositoryBookmarkRemotes(in: repo)
        let origin = try XCTUnwrap(remotes.first { $0.name == "origin" })
        let updated = try await controller.updateBookmark(old, from: repo, remote: origin)

        XCTAssertEqual(updated.canonicalKey, "github.com/team/client")
        XCTAssertEqual(updated.createdAt, old.createdAt)
        XCTAssertEqual(controller.bookmarks.map(\.id), [updated.id])
        XCTAssertEqual(controller.localURL(for: updated), repo)
        XCTAssertNil(controller.localURL(for: old))
        XCTAssertTrue(controller.bookmarksNeedingAttention(at: repo).isEmpty)
        let reopened = try await fixture.reopen()
        XCTAssertEqual(try reopened.value(RepositoryBookmark.self, in: "bookmarks", id: updated.id), updated)
        XCTAssertNotNil(try reopened.value(String.self, in: "bookmarkUploads", id: updated.id))
        XCTAssertNotNil(try reopened.value(String.self, in: "bookmarkDeletes", id: old.id))
    }

    @MainActor
    func testRepairMergesExistingDestinationBookmarkAndKeepsUnrelatedBookmark() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repo = try makeMultiRemoteRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let old = try makeBookmark("https://github.com/team/old-client.git")
        let destination = try makeBookmark("https://github.com/team/client.git")
        let unrelated = try makeBookmark("https://gitlab.com/other/repository.git")
        try await fixture.store.transaction { transaction in
            for bookmark in [old, destination, unrelated] {
                try transaction.set(bookmark, in: "bookmarks", id: bookmark.id)
            }
        }
        let controller = RepositoryBookmarkController(cloudStore: nil, dataStore: fixture.store)
        try controller.load()
        let remotes = try await GitStatusService.shared.repositoryBookmarkRemotes(in: repo)
        let origin = try XCTUnwrap(remotes.first { $0.name == "origin" })
        let updated = try await controller.updateBookmark(old, from: repo, remote: origin)
        XCTAssertEqual(updated.id, destination.id)
        XCTAssertEqual(updated.createdAt, destination.createdAt)
        XCTAssertEqual(Set(controller.bookmarks.map(\.id)), [destination.id, unrelated.id])
        XCTAssertEqual(controller.localURL(for: destination), repo)
    }

    @MainActor
    func testRepairRejectsRemoteChangedAfterPreview() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repo = try makeMultiRemoteRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let old = try makeBookmark("https://github.com/team/old-client.git")
        try await fixture.store.transaction { try $0.set(old, in: "bookmarks", id: old.id) }
        let controller = RepositoryBookmarkController(cloudStore: nil, dataStore: fixture.store)
        try controller.load()
        let remotes = try await GitStatusService.shared.repositoryBookmarkRemotes(in: repo)
        let origin = try XCTUnwrap(remotes.first { $0.name == "origin" })
        _ = try await GitStatusService.shared.runGit(arguments: ["remote", "set-url", "origin", "https://github.com/other/repo.git"], in: repo)
        do {
            _ = try await controller.updateBookmark(old, from: repo, remote: origin)
            XCTFail("The user must review the new remote before saving")
        } catch RepositoryBookmarkError.remoteChanged {
            XCTAssertEqual(controller.bookmarks, [old])
        }
    }

    @MainActor
    func testFailedRepairSyncSurvivesLoginAndStaleCloudSnapshotThenRetries() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repo = try makeMultiRemoteRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let old = try makeBookmark("https://github.com/team/old-client.git")
        let cloud = BookmarkRepairTestCloud(bookmarks: [old])
        let account = AccountSnapshot(uid: "repair-user", email: nil, displayName: nil, providerIDs: [])
        let controller = RepositoryBookmarkController(cloudStore: cloud, dataStore: fixture.store)
        await controller.updateAccount(account)
        let remotes = try await GitStatusService.shared.repositoryBookmarkRemotes(in: repo)
        let origin = try XCTUnwrap(remotes.first { $0.name == "origin" })
        cloud.failSaves = true
        let updated = try await controller.updateBookmark(old, from: repo, remote: origin)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertTrue(controller.hasPendingChanges)
        XCTAssertEqual(Array(cloud.stored.values), [old], "Do not delete the cloud bookmark before saving its replacement")

        let reopened = try await fixture.reopen()
        let second = RepositoryBookmarkController(cloudStore: cloud, dataStore: reopened)
        await second.updateAccount(account)
        XCTAssertEqual(second.bookmarks.map(\.id), [updated.id])
        XCTAssertEqual(second.localURL(for: updated), repo)
        XCTAssertNil(second.bookmark(forID: old.id))

        cloud.failSaves = false
        await second.retryPendingChanges()
        XCTAssertEqual(Array(cloud.stored.values), [updated])
        XCTAssertEqual(second.bookmarks.map(\.id), [updated.id])
        XCTAssertFalse(second.hasPendingChanges)
        XCTAssertNil(try reopened.value(String.self, in: "bookmarkUploads", id: updated.id))
        XCTAssertNil(try reopened.value(String.self, in: "bookmarkDeletes", id: old.id))
    }

    @MainActor
    func testRepairModelLetsUserSelectSecondaryRemoteAndDoesNotMutateBeforeSave() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repo = try makeMultiRemoteRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let old = try makeBookmark("https://github.com/team/old-client.git")
        try await fixture.store.transaction { try $0.set(old, in: "bookmarks", id: old.id) }
        let controller = RepositoryBookmarkController(cloudStore: nil, dataStore: fixture.store)
        try controller.load()
        let model = RepositoryBookmarkRepairModel(bookmark: old)
        await model.selectRepository(repo)
        XCTAssertEqual(model.selectedRemoteID, "origin")
        model.selectedRemoteID = "mirror"
        XCTAssertEqual(model.selectedRemote?.identity.canonicalRemoteURL.absoluteString, "https://gitlab.com/team/client-mirror.git")
        XCTAssertEqual(controller.bookmarks, [old])
        let saved = await model.save(using: controller)
        XCTAssertTrue(saved)
        XCTAssertEqual(controller.bookmarks.first?.canonicalKey, "gitlab.com/team/client-mirror")
    }

    @MainActor
    func testRepairDoesNotRecreateBookmarkRemovedWhileSheetWasOpen() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repo = try makeMultiRemoteRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let old = try makeBookmark("https://github.com/team/old-client.git")
        try await fixture.store.transaction { try $0.set(old, in: "bookmarks", id: old.id) }
        let controller = RepositoryBookmarkController(cloudStore: nil, dataStore: fixture.store)
        try controller.load()
        let model = RepositoryBookmarkRepairModel(bookmark: old)
        await model.selectRepository(repo)
        await controller.removeBookmark(old)
        let saved = await model.save(using: controller)
        XCTAssertFalse(saved)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(controller.bookmarks.isEmpty)
    }

    @MainActor
    func testRepairModelRequiresRepositoryWithSupportedRemote() async throws {
        let repo = try makeMultiRemoteRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let model = RepositoryBookmarkRepairModel(bookmark: try makeBookmark("https://github.com/team/old-client.git"))
        await model.selectRepository(repo)
        XCTAssertTrue(model.canSave)
        await model.selectRepository(repo.appendingPathComponent("missing"))
        XCTAssertFalse(model.canSave)
        XCTAssertNotNil(model.errorMessage)
        for name in ["origin", "mirror"] {
            _ = try await GitStatusService.shared.runGit(arguments: ["remote", "remove", name], in: repo)
        }
        await model.selectRepository(repo)
        XCTAssertFalse(model.canSave)
        XCTAssertTrue(model.remotes.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testAutoLinkMatchesBothRemotesOnFeatureBranchAndKeepsOtherRepositoriesSeparate() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repo = try makeMultiRemoteRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let controller = RepositoryBookmarkController(cloudStore: nil, dataStore: fixture.store)
        let github = try makeBookmark("https://github.com/team/client.git")
        let gitlab = try makeBookmark("https://gitlab.com/team/client-mirror.git")
        let other = try makeBookmark("https://github.com/team/other-client.git")

        // Simulate bookmarks arriving after the local list has already loaded.
        await controller.linkMatchingBookmarks(to: [repo])
        try await fixture.store.transaction { transaction in
            for bookmark in [github, gitlab, other] {
                try transaction.set(bookmark, in: "bookmarks", id: bookmark.id)
            }
        }
        try controller.load()
        await controller.linkMatchingBookmarks(to: [repo, repo])

        XCTAssertEqual(controller.localURL(for: github), repo)
        XCTAssertEqual(controller.localURL(for: gitlab), repo)
        XCTAssertNil(controller.localURL(for: other))

        let anotherClone = URL(fileURLWithPath: "/tmp/another-clone", isDirectory: true)
        try await controller.link(github, to: anotherClone)
        await controller.linkMatchingBookmarks(to: [repo])
        XCTAssertEqual(controller.localURL(for: github), anotherClone)
    }

    @MainActor
    func testManualLinkAcceptsSecondaryRemoteAndRejectsDifferentRepository() async throws {
        let fixture = try LocalDataStoreTestFixture()
        defer { fixture.cleanup() }
        try await fixture.store.prepare()
        let repo = try makeMultiRemoteRepository()
        defer { try? FileManager.default.removeItem(at: repo) }
        let controller = RepositoryBookmarkController(cloudStore: nil, dataStore: fixture.store)
        let gitlab = try makeBookmark("https://gitlab.com/team/client-mirror.git")
        try await controller.validateAndLink(gitlab, to: repo)
        XCTAssertEqual(controller.localURL(for: gitlab), repo)

        let other = try makeBookmark("https://github.com/team/other-client.git")
        do {
            try await controller.validateAndLink(other, to: repo)
            XCTFail("A different remote repository must not be linked")
        } catch RepositoryBookmarkError.folderDoesNotMatch {
            XCTAssertNil(controller.localURL(for: other))
        }
    }

    private func makeBookmark(_ remote: String) throws -> RepositoryBookmark {
        RepositoryBookmark(identity: try XCTUnwrap(RepositoryBookmarkIdentity.resolve(remoteURLString: remote)))
    }

    private func makeMultiRemoteRepository() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for arguments in [
            ["init", "-b", "feat/bookmarks"],
            ["remote", "add", "origin", "git@github.com:team/client.git"],
            ["remote", "add", "mirror", "git@gitlab.com:team/client-mirror.git"]
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.currentDirectoryURL = url
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: url)
                throw GitError.commandFailed("Could not create bookmark test repository")
            }
        }
        return url
    }

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

@MainActor
private final class BookmarkRepairTestCloud: RepositoryBookmarkCloudStore {
    var stored: [String: RepositoryBookmark]
    var failSaves = false

    init(bookmarks: [RepositoryBookmark]) {
        stored = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })
    }

    func bookmarks(uid: String) async throws -> [RepositoryBookmark] { Array(stored.values) }

    func save(_ bookmark: RepositoryBookmark, uid: String) async throws {
        if failSaves { throw LocalDataError.notReady }
        stored[bookmark.id] = bookmark
    }

    func delete(bookmarkID: String, uid: String) async throws {
        stored[bookmarkID] = nil
    }

    func observe(uid: String, onChange: @escaping (Result<[RepositoryBookmark], Error>) -> Void) -> ObservationToken {
        BookmarkRepairTestObservation()
    }
}

private final class BookmarkRepairTestObservation: ObservationToken {
    func cancel() { }
}
