// SPDX-License-Identifier: AGPL-3.0-or-later
//
//  GitBranchDeletionIntegrationTests.swift
//  macgitTests
//

import XCTest
@testable import macgit

@MainActor
final class GitBranchDeletionIntegrationTests: XCTestCase {
    // MARK: - Remote delete and credentials

    func testDeleteRemoteBranchRemovesBranchFromRemote() async throws {
        let fixture = try makeFixture(pushedBranches: ["topic"])

        _ = try await GitStatusService.shared.deleteRemoteBranch(remote: "origin", name: "topic", in: fixture.cloneURL)

        XCTAssertFalse(refExists("refs/heads/topic", in: fixture.remoteURL))
    }

    func testDeleteRemoteBranchConsultsCredentialResolverBeforeRunningGit() async throws {
        let fixture = try makeFixture()
        try runGit(["remote", "add", "gh", "https://github.com/octocat/Hello-World.git"], in: fixture.cloneURL)
        let resolver = GitProviderCredentialResolver(
            accounts: [makeProviderAccount(id: "connection-1"), makeProviderAccount(id: "connection-2", username: "monalisa")],
            tokenVault: FakeDeletionTokenVault()
        )

        do {
            _ = try await GitStatusService.shared.deleteRemoteBranch(
                remote: "gh",
                name: "topic",
                in: fixture.cloneURL,
                credentialResolver: resolver
            )
            XCTFail("Expected the resolver error before any push")
        } catch {
            XCTAssertEqual(error as? GitProviderCredentialError, .multipleMatchingAccounts(host: "github.com"))
        }
    }

    func testRemoteBranchHashReturnsTipOrNil() async throws {
        let fixture = try makeFixture(pushedBranches: ["topic"])
        let expected = try gitOutput(["rev-parse", "topic"], in: fixture.cloneURL)

        let hash = try await GitStatusService.shared.remoteBranchHash(remote: "origin", branch: "topic", in: fixture.cloneURL)
        let missing = try await GitStatusService.shared.remoteBranchHash(remote: "origin", branch: "nope", in: fixture.cloneURL)

        XCTAssertEqual(hash, expected)
        XCTAssertNil(missing)
    }

    // MARK: - Local phase

    func testDeleteLocalBranchesDeletesMergedAndReportsFailuresWithoutTouchingRemote() async throws {
        let fixture = try makeFixture(pushedBranches: ["merged"])
        try runGit(["checkout", "-q", "-b", "unmerged"], in: fixture.cloneURL)
        try commit("unmerged work", file: "unmerged.txt", in: fixture.cloneURL)
        try runGit(["checkout", "-q", "main"], in: fixture.cloneURL)
        let mergedTip = try gitOutput(["rev-parse", "merged"], in: fixture.cloneURL)
        let target = RemoteBranchDeleteTarget(remote: "origin", branch: "merged")

        let result = await GitStatusService.shared.deleteLocalBranches(
            GitLocalBranchDeletionRequest(
                branches: ["main", "merged", "unmerged"],
                force: false,
                currentBranch: "main",
                remoteTargets: ["merged": target]
            ),
            validate: nil,
            in: fixture.cloneURL
        )

        XCTAssertEqual(result.deleted, [
            GitDeletedLocalBranch(name: "merged", tip: mergedTip, upstream: "origin/merged", force: false, remoteTarget: target)
        ])
        XCTAssertEqual(result.failures.map(\.name), ["main", "unmerged"])
        XCTAssertTrue(result.failures[0].message.contains("currently checked out"))
        XCTAssertTrue(result.failures[1].message.contains("not fully merged"))
        XCTAssertFalse(refExists("refs/heads/merged", in: fixture.cloneURL))
        XCTAssertTrue(refExists("refs/heads/unmerged", in: fixture.cloneURL))
        XCTAssertTrue(refExists("refs/heads/merged", in: fixture.remoteURL), "The local phase must not delete remote branches")
    }

    func testDeleteLocalBranchesForceDeletesUnmergedBranch() async throws {
        let fixture = try makeFixture()
        try runGit(["checkout", "-q", "-b", "unmerged"], in: fixture.cloneURL)
        try commit("unmerged work", file: "unmerged.txt", in: fixture.cloneURL)
        try runGit(["checkout", "-q", "main"], in: fixture.cloneURL)

        let result = await GitStatusService.shared.deleteLocalBranches(
            GitLocalBranchDeletionRequest(branches: ["unmerged"], force: true, currentBranch: "main", remoteTargets: [:]),
            validate: nil,
            in: fixture.cloneURL
        )

        XCTAssertEqual(result.deleted.map(\.name), ["unmerged"])
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testDeleteLocalBranchesRejectsValidatedTipMismatch() async throws {
        let fixture = try makeFixture()
        try runGit(["branch", "stale"], in: fixture.cloneURL)

        let result = await GitStatusService.shared.deleteLocalBranches(
            GitLocalBranchDeletionRequest(branches: ["stale"], force: true, currentBranch: "main", remoteTargets: [:]),
            validate: { _ in String(repeating: "0", count: 40) },
            in: fixture.cloneURL
        )

        XCTAssertTrue(result.deleted.isEmpty)
        XCTAssertTrue(result.failures.first?.message.contains("changed while its merge status") == true)
        XCTAssertTrue(refExists("refs/heads/stale", in: fixture.cloneURL))
    }

    // MARK: - Remote phase

    func testDeleteRemoteBranchesContinuesAfterFailureAndCapturesHashes() async throws {
        let fixture = try makeFixture(pushedBranches: ["a", "b", "c"])
        let hashA = try gitOutput(["rev-parse", "a"], in: fixture.cloneURL)
        try runGit(["branch", "-D", "b"], in: fixture.remoteURL)
        let local = { (name: String) in
            GitDeletedLocalBranch(
                name: name,
                tip: hashA,
                upstream: nil,
                force: true,
                remoteTarget: RemoteBranchDeleteTarget(remote: "origin", branch: name)
            )
        }
        let pending = [
            GitPendingRemoteBranchDeletion(target: RemoteBranchDeleteTarget(remote: "origin", branch: "a"), localBranch: local("a")),
            GitPendingRemoteBranchDeletion(target: RemoteBranchDeleteTarget(remote: "origin", branch: "b"), localBranch: local("b")),
            GitPendingRemoteBranchDeletion(target: RemoteBranchDeleteTarget(remote: "origin", branch: "c"), localBranch: nil),
        ]

        let results = await GitStatusService.shared.deleteRemoteBranches(pending, in: fixture.cloneURL)

        XCTAssertEqual(results.map(\.pending), pending)
        XCTAssertEqual(results[0].remoteHash, hashA)
        XCTAssertNil(results[0].failure)
        XCTAssertNil(results[1].remoteHash)
        XCTAssertEqual(results[1].failure?.name, "origin/b")
        XCTAssertEqual(results[1].failure?.message, "The remote branch does not exist or has already been deleted.")
        XCTAssertNil(results[2].remoteHash)
        XCTAssertNil(results[2].failure)
        XCTAssertFalse(refExists("refs/heads/a", in: fixture.remoteURL))
        XCTAssertFalse(refExists("refs/heads/c", in: fixture.remoteURL))

        let message = try XCTUnwrap(GitStatusService.remoteBranchDeletionFailureMessage(results))
        XCTAssertEqual(
            message,
            """
            Could not delete 1 of 3 remote branches.

            • origin/b: The remote branch does not exist or has already been deleted.
            """
        )
        XCTAssertEqual(
            RepositoryOperationProgress.backgroundErrorSummary(message),
            "Could not delete 1 of 3 remote branches."
        )
    }

    func testRemoteDeletionMessagesAndTitles() {
        let target = RemoteBranchDeleteTarget(remote: "origin", branch: "a")
        let one = [GitPendingRemoteBranchDeletion(target: target, localBranch: nil)]
        let two = one + [GitPendingRemoteBranchDeletion(target: RemoteBranchDeleteTarget(remote: "fork", branch: "b"), localBranch: nil)]

        XCTAssertEqual(GitStatusService.remoteBranchDeletionTitle(one), "Deleting origin/a")
        XCTAssertEqual(GitStatusService.remoteBranchDeletionTitle(two), "Deleting 2 remote branches")
        XCTAssertNil(GitStatusService.remoteBranchDeletionFailureMessage([
            GitRemoteBranchDeletionResult(pending: one[0], remoteHash: nil, failure: nil)
        ]))
        XCTAssertEqual(
            GitStatusService.remoteBranchDeletionFailureMessage([
                GitRemoteBranchDeletionResult(
                    pending: one[0],
                    remoteHash: nil,
                    failure: GitBranchDeletionFailure(name: "origin/a", message: "denied")
                )
            ]),
            "Could not delete 1 of 1 remote branch.\n\n• origin/a: denied"
        )
    }

    // MARK: - Helpers

    private struct Fixture {
        let remoteURL: URL
        let cloneURL: URL
    }

    private func makeFixture(pushedBranches: [String] = []) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-branch-deletion-\(UUID().uuidString)", isDirectory: true)
        let remoteURL = root.appendingPathComponent("remote.git", isDirectory: true)
        let cloneURL = root.appendingPathComponent("clone", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init", "-q", "--bare", "-b", "main", remoteURL.path], in: root)
        try runGit(["clone", "-q", remoteURL.path, cloneURL.path], in: root)
        try runGit(["config", "user.name", "Mac Git Tests"], in: cloneURL)
        try runGit(["config", "user.email", "tests@example.com"], in: cloneURL)
        try runGit(["checkout", "-q", "-b", "main"], in: cloneURL)
        try commit("initial", file: "tracked.txt", in: cloneURL)
        try runGit(["push", "-q", "-u", "origin", "main"], in: cloneURL)
        for branch in pushedBranches {
            try runGit(["branch", branch], in: cloneURL)
            try runGit(["push", "-q", "-u", "origin", branch], in: cloneURL)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Fixture(remoteURL: remoteURL, cloneURL: cloneURL)
    }

    private func commit(_ message: String, file: String, in directory: URL) throws {
        try "\(message)\n".write(to: directory.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try runGit(["add", file], in: directory)
        try runGit(["commit", "-q", "-m", message], in: directory)
    }

    private func refExists(_ ref: String, in directory: URL) -> Bool {
        (try? runGit(["rev-parse", "--verify", "--quiet", ref], in: directory)) != nil
    }

    private func gitOutput(_ arguments: [String], in directory: URL) throws -> String {
        try runGit(arguments, in: directory).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        try task.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw GitError.commandFailed(message)
        }
        return String(data: output, encoding: .utf8) ?? ""
    }

    private func makeProviderAccount(id: String, username: String = "octocat") -> GitProviderAccount {
        GitProviderAccount(
            id: id,
            macgitUID: "macgit-user-1",
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: id,
            username: username,
            displayName: nil,
            avatarURL: nil,
            scopes: [],
            permissions: [:],
            tokenStatus: .valid,
            transportProtocol: .https,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )
    }
}

private final class FakeDeletionTokenVault: GitProviderTokenVault {
    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? { nil }
    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {}
    func deleteToken(for account: GitProviderAccount) throws {}
}
