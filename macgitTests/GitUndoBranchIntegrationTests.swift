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

final class GitUndoBranchIntegrationTests: XCTestCase {
    func testUndoCreateBranchDeletesCreatedBranchWhenTipMatches() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let start = try await support.tip(of: "main", in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)
        let branchesAfterCreate = await GitStatusService.shared.localBranches(in: repoURL)
        XCTAssertTrue(branchesAfterCreate.contains("feature"))

        try await executor.execute(.deleteLocalBranch(name: "feature", force: true, expectedTip: start), in: repoURL)
        let branchesAfterDelete = await GitStatusService.shared.localBranches(in: repoURL)
        XCTAssertFalse(branchesAfterDelete.contains("feature"))
    }

    func testUndoDeleteBranchRecreatesBranchAtCapturedTip() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let start = try await support.tip(of: "main", in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)
        try await executor.execute(.deleteLocalBranch(name: "feature", force: true, expectedTip: start), in: repoURL)
        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)

        let restoredTip = try await support.tip(of: "feature", in: repoURL)
        XCTAssertEqual(restoredTip, start)
    }

    func testCheckoutRefSwitchesCurrentBranch() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let start = try await support.tip(of: "main", in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)
        try await executor.execute(.checkoutRef(ref: "feature"), in: repoURL)

        let currentRef = try await support.currentRef(in: repoURL)
        XCTAssertEqual(currentRef, "feature")
    }

    func testDeleteValidatedMergedBranchDeletesBranchAtExpectedTip() async throws {
        let repoURL = try makeTempRepo()
        let start = try await GitBranchUndoSupport().tip(of: "main", in: repoURL)
        try runGit(["branch", "feature"], in: repoURL)
        try runGit(["config", "branch.feature.description", "merged"], in: repoURL)

        _ = try await GitStatusService.shared.deleteValidatedMergedBranch(
            name: "feature", expectedTip: start, in: repoURL
        )

        let branches = await GitStatusService.shared.localBranches(in: repoURL)
        XCTAssertFalse(branches.contains("feature"))
        let config = try? await GitStatusService.shared.runGit(
            arguments: ["config", "--get", "branch.feature.description"], in: repoURL
        )
        XCTAssertNil(config)
    }

    func testDeleteValidatedMergedBranchRejectsMovedTip() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let validatedTip = try await support.tip(of: "main", in: repoURL)
        try runGit(["checkout", "-b", "feature"], in: repoURL)
        try runGit(["commit", "--allow-empty", "-m", "unmerged"], in: repoURL)
        try runGit(["checkout", "main"], in: repoURL)
        let movedTip = try await support.tip(of: "feature", in: repoURL)

        do {
            _ = try await GitStatusService.shared.deleteValidatedMergedBranch(
                name: "feature", expectedTip: validatedTip, in: repoURL
            )
            XCTFail("Expected deletion of a moved branch to fail")
        } catch {}

        let remainingTip = try await support.tip(of: "feature", in: repoURL)
        XCTAssertEqual(remainingTip, movedTip)
    }

    func testDeleteValidatedMergedBranchRejectsBranchCheckedOutInWorktree() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let start = try await support.tip(of: "main", in: repoURL)
        let worktreeURL = repoURL.deletingLastPathComponent()
            .appendingPathComponent("macgit-undo-branch-worktree-\(UUID().uuidString)", isDirectory: true)
        try runGit(["worktree", "add", "-b", "feature", worktreeURL.path], in: repoURL)

        do {
            _ = try await GitStatusService.shared.deleteValidatedMergedBranch(
                name: "feature", expectedTip: start, in: repoURL
            )
            XCTFail("Expected deletion of a checked-out branch to fail")
        } catch {}

        let remainingTip = try await support.tip(of: "feature", in: repoURL)
        XCTAssertEqual(remainingTip, start)
    }

    @MainActor
    func testDeletedBranchUndoEntryRestoresAndRedeletesLocalAndRemote() async throws {
        let (remoteURL, cloneURL) = try makeRepoWithRemote()
        try runGit(["branch", "topic"], in: cloneURL)
        try runGit(["push", "-q", "-u", "origin", "topic"], in: cloneURL)
        let support = GitBranchUndoSupport()
        let tip = try await support.tip(of: "topic", in: cloneURL)
        let target = RemoteBranchDeleteTarget(remote: "origin", branch: "topic")
        let remoteHash = try await GitStatusService.shared.remoteBranchHash(remote: "origin", branch: "topic", in: cloneURL)
        _ = try await GitStatusService.shared.deleteBranch(name: "topic", force: true, in: cloneURL)
        _ = try await GitStatusService.shared.deleteRemoteBranch(remote: "origin", name: "topic", in: cloneURL)
        let entry = GitBranchUndoSupport.deletedBranchUndoEntry(
            repositoryURL: cloneURL,
            branch: "topic",
            force: true,
            tip: tip,
            upstream: "origin/topic",
            remoteTarget: target,
            remoteHash: remoteHash
        )
        let executor = GitUndoExecutor()

        XCTAssertEqual(entry.label, "Delete branch topic")
        try await executor.execute(entry.undoOperation, in: cloneURL)

        let restoredTip = try await support.tip(of: "topic", in: cloneURL)
        let restoredUpstream = await support.upstream(of: "topic", in: cloneURL)
        let remoteAfterUndo = try await GitStatusService.shared.remoteBranchHash(remote: "origin", branch: "topic", in: cloneURL)
        XCTAssertEqual(restoredTip, tip)
        XCTAssertEqual(restoredUpstream, "origin/topic")
        XCTAssertEqual(remoteAfterUndo, remoteHash)

        try await executor.execute(entry.redoOperation, in: cloneURL)

        let branchesAfterRedo = await GitStatusService.shared.localBranches(in: cloneURL)
        let remoteAfterRedo = try await GitStatusService.shared.remoteBranchHash(remote: "origin", branch: "topic", in: cloneURL)
        XCTAssertFalse(branchesAfterRedo.contains("topic"))
        XCTAssertNil(remoteAfterRedo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: remoteURL.path))
    }

    func testDeletedBranchUndoEntryWithoutRemoteOnlyRestoresLocalBranch() {
        let repositoryURL = URL(fileURLWithPath: "/tmp/repo")
        let entry = GitBranchUndoSupport.deletedBranchUndoEntry(
            repositoryURL: repositoryURL,
            branch: "topic",
            force: false,
            tip: "abc123",
            upstream: nil,
            remoteTarget: RemoteBranchDeleteTarget(remote: "origin", branch: "topic"),
            remoteHash: nil
        )

        XCTAssertEqual(entry.undoOperation, .sequence([
            .createLocalBranch(name: "topic", startPoint: "abc123", checkout: false)
        ]))
        XCTAssertEqual(entry.redoOperation, .sequence([
            .deleteLocalBranch(name: "topic", force: false, expectedTip: "abc123")
        ]))
    }

    private func makeRepoWithRemote() throws -> (remoteURL: URL, cloneURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-undo-branch-remote-\(UUID().uuidString)", isDirectory: true)
        let remoteURL = root.appendingPathComponent("remote.git", isDirectory: true)
        let cloneURL = try makeTempRepo()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init", "-q", "--bare", "-b", "main", remoteURL.path], in: root)
        try runGit(["remote", "add", "origin", remoteURL.path], in: cloneURL)
        try runGit(["push", "-q", "-u", "origin", "main"], in: cloneURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: cloneURL)
        }
        return (remoteURL, cloneURL)
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-undo-branch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)
        try "base\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)
        return repoURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL
        let stderr = Pipe()
        task.standardError = stderr
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw GitError.commandFailed(output)
        }
    }
}
