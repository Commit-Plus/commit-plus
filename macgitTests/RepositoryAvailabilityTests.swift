// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class RepositoryAvailabilityTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("repository-availability-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testGitDirectoryOrFileMakesRepositoryAvailable() throws {
        let worktree = directory.appendingPathComponent("worktree")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: /elsewhere\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let repository = directory.appendingPathComponent("repository")
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )

        XCTAssertTrue(SyncState.repositoryIsAvailable(at: worktree))
        XCTAssertTrue(SyncState.repositoryIsAvailable(at: repository))
    }

    func testRefreshReportsDeletedRepository() async {
        let missing = directory.appendingPathComponent("deleted")
        await assertRefreshReportsUnavailable(missing)
    }

    func testRefreshReportsFolderWithoutGitDirectory() async {
        await assertRefreshReportsUnavailable(directory)
    }

    private func assertRefreshReportsUnavailable(_ repositoryURL: URL) async {
        let posted = expectation(forNotification: .repositoryBecameUnavailable, object: nil) { notification in
            notification.userInfo?["repositoryURL"] as? URL == repositoryURL
        }
        await SyncState().refresh(repositoryURL: repositoryURL)
        await fulfillment(of: [posted], timeout: 1)
    }
}
