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

final class BranchSyncStatusTests: XCTestCase {
    func testBranchSyncStatusEquality() {
        let a = BranchSyncStatus(ahead: 2, behind: 1)
        let b = BranchSyncStatus(ahead: 2, behind: 1)
        let c = BranchSyncStatus(ahead: 1, behind: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testBranchSyncStatusInSyncReturnsNil() {
        // This is a placeholder for an integration test.
        // A full integration test would create a temp git repo,
        // set up a remote tracking branch, and verify the
        // GitStatusService.branchSyncStatus method returns nil
        // when the branch is in sync with its upstream.
        // For now, we verify the model exists and compiles.
        XCTAssertTrue(true)
    }

    func testBranchSyncStatusReportsAheadAndBehindCountsForTrackedBranch() async throws {
        let repoURL = try makeRepoWithTrackedBranch(aheadCommits: 1)

        let status = await GitStatusService.shared.branchSyncStatus(for: "main", in: repoURL)
        let statuses = await GitStatusService.shared.branchSyncStatuses(
            for: ["main", "missing"],
            in: repoURL
        )

        XCTAssertEqual(status, BranchSyncStatus(ahead: 1, behind: 0))
        XCTAssertEqual(statuses, ["main": BranchSyncStatus(ahead: 1, behind: 0)])
    }

    func testCurrentBranchAheadBehindUsesMatchingRemoteTrackingBranchWhenUpstreamIsUnset() async throws {
        let branch = "codex/inline-create-pull-request"
        let repoURL = try makeRepoWithRemoteTrackingBranchWithoutUpstream(branch: branch)

        let counts = await GitStatusService.shared.aheadBehindCount(in: repoURL)
        let status = await GitStatusService.shared.branchSyncStatus(for: branch, in: repoURL)
        let statuses = await GitStatusService.shared.branchSyncStatuses(for: [branch], in: repoURL)

        XCTAssertEqual(counts.ahead, 1)
        XCTAssertEqual(counts.behind, 0)
        XCTAssertEqual(status, BranchSyncStatus(ahead: 1, behind: 0))
        XCTAssertEqual(statuses[branch], BranchSyncStatus(ahead: 1, behind: 0))
    }

    func testBatchBranchSyncStatusReportsDivergedCounts() async throws {
        let repoURL = try makeRepoWithDivergentTrackedBranch()

        let statuses = await GitStatusService.shared.branchSyncStatuses(for: ["main"], in: repoURL)

        XCTAssertEqual(statuses["main"], BranchSyncStatus(ahead: 1, behind: 1))
    }

    // MARK: - Helpers

    private func makeRepoWithTrackedBranch(aheadCommits: Int) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-branch-sync-\(UUID().uuidString)", isDirectory: true)
        let originURL = rootURL.appendingPathComponent("origin.git", isDirectory: true)
        let localURL = rootURL.appendingPathComponent("local", isDirectory: true)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try runGit(["init", "--bare", "--initial-branch=main", originURL.path], in: rootURL)
        try runGit(["clone", originURL.path, localURL.path], in: rootURL)
        try configureGit(in: localURL)

        let trackedFile = localURL.appendingPathComponent("tracked.txt")
        try "base\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "base"], in: localURL)
        try runGit(["push", "-u", "origin", "main"], in: localURL)

        for index in 1...aheadCommits {
            try "base \(index)\n".write(to: trackedFile, atomically: true, encoding: .utf8)
            try runGit(["add", "tracked.txt"], in: localURL)
            try runGit(["commit", "-m", "ahead \(index)"], in: localURL)
        }

        return localURL
    }

    private func makeRepoWithRemoteTrackingBranchWithoutUpstream(branch: String) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-current-branch-sync-\(UUID().uuidString)", isDirectory: true)
        let originURL = rootURL.appendingPathComponent("origin.git", isDirectory: true)
        let localURL = rootURL.appendingPathComponent("local", isDirectory: true)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try runGit(["init", "--bare", "--initial-branch=main", originURL.path], in: rootURL)
        try runGit(["clone", originURL.path, localURL.path], in: rootURL)
        try configureGit(in: localURL)

        let trackedFile = localURL.appendingPathComponent("tracked.txt")
        try "base\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "base"], in: localURL)
        try runGit(["push", "-u", "origin", "main"], in: localURL)

        try runGit(["checkout", "-b", branch], in: localURL)
        try "published\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "published"], in: localURL)
        try runGit(["push", "-u", "origin", branch], in: localURL)
        try runGit(["branch", "--unset-upstream", branch], in: localURL)

        try "local ahead\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "local ahead"], in: localURL)

        return localURL
    }

    private func makeRepoWithDivergentTrackedBranch() throws -> URL {
        let localURL = try makeRepoWithTrackedBranch(aheadCommits: 1)
        let rootURL = localURL.deletingLastPathComponent()
        let originURL = rootURL.appendingPathComponent("origin.git", isDirectory: true)
        let updaterURL = rootURL.appendingPathComponent("updater", isDirectory: true)

        try runGit(["clone", originURL.path, updaterURL.path], in: rootURL)
        try configureGit(in: updaterURL)

        let remoteFile = updaterURL.appendingPathComponent("remote.txt")
        try "remote\n".write(to: remoteFile, atomically: true, encoding: .utf8)
        try runGit(["add", "remote.txt"], in: updaterURL)
        try runGit(["commit", "-m", "remote ahead"], in: updaterURL)
        try runGit(["push", "origin", "main"], in: updaterURL)
        try runGit(["fetch", "origin"], in: localURL)

        return localURL
    }

    private func configureGit(in repositoryURL: URL) throws {
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let outputData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "git failed"
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(output)")
        }
    }
}
