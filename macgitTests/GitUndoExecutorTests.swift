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

final class GitUndoExecutorTests: XCTestCase {
    func testStageFilesRunsGitAddWithPathspecSeparator() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.stageFiles(paths: ["README.md", "Sources/App.swift"]), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(
                arguments: ["add", "--", "README.md", "Sources/App.swift"],
                directory: repoURL
            )
        ])
    }

    func testUnstageFilesRunsGitResetHeadWithPathspecSeparator() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.unstageFiles(paths: ["README.md"]), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(
                arguments: ["reset", "HEAD", "--", "README.md"],
                directory: repoURL
            )
        ])
    }

    func testEmptyPathListThrowsBeforeRunningGit() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        do {
            try await executor.execute(.stageFiles(paths: []), in: repoURL)
            XCTFail("Expected emptyPathList error")
        } catch let error as GitUndoError {
            XCTAssertEqual(error, .emptyPathList)
        }

        let calls = await runner.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testCheckoutRefRunsGitCheckout() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.checkoutRef(ref: "feature"), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["checkout", "feature"], directory: repoURL)
        ])
    }

    func testCreateLocalBranchUsesBranchCommandWhenCheckoutDisabled() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .createLocalBranch(name: "feature", startPoint: "abc123", checkout: false),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["branch", "feature", "abc123"], directory: repoURL)
        ])
    }

    func testDeleteLocalBranchChecksExpectedTipBeforeDeleting() async throws {
        let runner = RecordingGitRunner(outputs: ["rev-parse feature^{commit}": "abc123\n"])
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .deleteLocalBranch(name: "feature", force: true, expectedTip: "abc123"),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["rev-parse", "feature^{commit}"], directory: repoURL),
            GitCommandCall(arguments: ["branch", "-D", "feature"], directory: repoURL)
        ])
    }

    func testDeleteRemoteBranchChecksExpectedHashBeforeDeleting() async throws {
        let runner = RecordingGitRunner(outputs: ["ls-remote origin refs/heads/feature": "abc123\trefs/heads/feature\n"])
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .deleteRemoteBranch(remote: "origin", branch: "feature", expectedHash: "abc123"),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["ls-remote", "origin", "refs/heads/feature"], directory: repoURL),
            GitCommandCall(arguments: ["push", "origin", "--delete", "feature"], directory: repoURL)
        ])
    }

    func testDeleteRemoteBranchThrowsWhenExpectedHashDoesNotMatch() async throws {
        let runner = RecordingGitRunner(outputs: ["ls-remote origin refs/heads/feature": "def456\trefs/heads/feature\n"])
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        do {
            try await executor.execute(
                .deleteRemoteBranch(remote: "origin", branch: "feature", expectedHash: "abc123"),
                in: repoURL
            )
            XCTFail("Expected hash mismatch error")
        } catch let error as GitError {
            XCTAssertTrue(error.localizedDescription.contains("no longer at the expected hash"))
        }

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["ls-remote", "origin", "refs/heads/feature"], directory: repoURL)
        ])
    }

    func testPushBranchRunsGitPushWithSimpleRefSpec() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .pushBranch(remote: "origin", localBranch: "feature", remoteBranch: "feature"),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["push", "origin", "feature"], directory: repoURL)
        ])
    }

    func testPushBranchRunsGitPushWithExplicitRefSpecWhenNamesDiffer() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .pushBranch(remote: "origin", localBranch: "feature", remoteBranch: "feat-42"),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["push", "origin", "feature:feat-42"], directory: repoURL)
        ])
    }

    func testPushBranchCanRestoreRemoteBranchFromExactHash() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .pushBranch(
                remote: "origin",
                localBranch: "abc123",
                remoteBranch: "refs/heads/feature"
            ),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(
                arguments: ["push", "origin", "abc123:refs/heads/feature"],
                directory: repoURL
            )
        ])
    }

    func testSetUpstreamRunsGitBranchSetUpstreamTo() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .setUpstream(branch: "feature", upstream: "origin/feature"),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(
                arguments: ["branch", "--set-upstream-to", "origin/feature", "feature"],
                directory: repoURL
            )
        ])
    }

    func testRevertRunsGitRevert() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.revert(commit: "abc123"), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["revert", "--no-edit", "abc123"], directory: repoURL)
        ])
    }

    func testCherryPickCommitsRunsOneOrderedCherryPickCommand() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.cherryPickCommits(commits: ["old", "new"]), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["cherry-pick", "old", "new"], directory: repoURL)
        ])
    }

    func testMergeCommitRunsGitMergeWithSelectedFlags() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.mergeCommit(commit: "feature", noCommit: true, log: true), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["merge", "--no-commit", "--log", "feature"], directory: repoURL)
        ])
    }

    func testRebaseOntoRunsGitRebase() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.rebaseOnto(commit: "origin/main"), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["rebase", "origin/main"], directory: repoURL)
        ])
    }

    func testStashPushRedoRunsGitStashPushWithPathsAndUntracked() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .stashPush(
                message: "Selected files",
                keepIndex: false,
                paths: ["tracked.txt", "new.txt"],
                includeUntracked: true
            ),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(
                arguments: [
                    "stash",
                    "push",
                    "--include-untracked",
                    "-m",
                    "Selected files",
                    "--",
                    "tracked.txt",
                    "new.txt"
                ],
                directory: repoURL
            )
        ])
    }

    func testStashPushRedoOmitsIncludeUntrackedAndKeepsIndexFlag() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .stashPush(
                message: "",
                keepIndex: true,
                paths: ["only.txt"],
                includeUntracked: false
            ),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(
                arguments: ["stash", "push", "--keep-index", "--", "only.txt"],
                directory: repoURL
            )
        ])
    }
}

private struct GitCommandCall: Equatable {
    let arguments: [String]
    let directory: URL
}

private actor RecordingGitRunner: GitCommandRunning {
    private let outputs: [String: String]
    private var calls: [GitCommandCall] = []

    init(outputs: [String: String] = [:]) {
        self.outputs = outputs
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        calls.append(GitCommandCall(arguments: arguments, directory: directory))
        return outputs[arguments.joined(separator: " ")] ?? ""
    }

    func recordedCalls() -> [GitCommandCall] {
        calls
    }
}
