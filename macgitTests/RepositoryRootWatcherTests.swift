// SPDX-License-Identifier: AGPL-3.0-or-later
import CoreServices
import XCTest
@testable import macgit

final class RepositoryRootWatcherTests: XCTestCase {
    func testRelevanceIgnoresGitInternalsAndFileEdits() {
        let created = kFSEventStreamEventFlagItemCreated
        let isDir = kFSEventStreamEventFlagItemIsDir
        XCTAssertTrue(RepositoryRootWatcher.isRelevant(path: "/root/new/.git", flags: created | isDir))
        XCTAssertTrue(RepositoryRootWatcher.isRelevant(path: "/root/worktree/.git", flags: created | kFSEventStreamEventFlagItemIsFile))
        XCTAssertTrue(RepositoryRootWatcher.isRelevant(path: "/root/moved", flags: kFSEventStreamEventFlagItemRenamed | isDir))
        XCTAssertTrue(RepositoryRootWatcher.isRelevant(path: "/root/deleted", flags: kFSEventStreamEventFlagItemRemoved | isDir))
        XCTAssertTrue(RepositoryRootWatcher.isRelevant(path: "/root", flags: kFSEventStreamEventFlagMustScanSubDirs))
        XCTAssertFalse(RepositoryRootWatcher.isRelevant(path: "/root/repo/.git/index", flags: created | kFSEventStreamEventFlagItemIsFile))
        XCTAssertFalse(RepositoryRootWatcher.isRelevant(path: "/root/repo/.git/refs", flags: kFSEventStreamEventFlagItemRenamed | isDir))
        XCTAssertFalse(RepositoryRootWatcher.isRelevant(path: "/root/repo/file.swift", flags: kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile))
        XCTAssertFalse(RepositoryRootWatcher.isRelevant(path: "/root/new-folder", flags: created | isDir))
    }

    func testWatcherReportsRepositoryCreatedUnderRoot() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("repository-root-watcher-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let changed = expectation(description: "watcher reports new repository")
        changed.assertForOverFulfill = false
        let watcher = RepositoryRootWatcher { changed.fulfill() }
        watcher.watch([root])
        defer { watcher.stop() }

        try fileManager.createDirectory(
            at: root.appendingPathComponent("group/new/.git", isDirectory: true),
            withIntermediateDirectories: true
        )
        wait(for: [changed], timeout: 10)
    }
}
