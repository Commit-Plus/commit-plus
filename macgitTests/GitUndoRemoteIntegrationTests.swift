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

final class GitUndoRemoteIntegrationTests: XCTestCase {
    @MainActor
    func testDeleteRemoteBranchOperationRemovesPublishedBranchWhenHashMatches() async throws {
        let fixture = try makeFixtureWithFeatureBranch()
        let support = GitRemoteUndoSupport()
        let hashOptional = try await support.remoteHash(remote: "origin", branch: "feature", in: fixture.cloneURL)
        let hash = try XCTUnwrap(hashOptional)
        let executor = GitUndoExecutor()

        try await executor.execute(.deleteRemoteBranch(remote: "origin", branch: "feature", expectedHash: hash), in: fixture.cloneURL)

        let after = try await support.remoteHash(remote: "origin", branch: "feature", in: fixture.cloneURL)
        XCTAssertNil(after)
    }

    @MainActor
    func testPullUndoAndRedoRoundTrip() async throws {
        let fixture = try makePullFixture()
        let syncState = SyncState()
        let undoManager = GitUndoManager()
        let executor = GitUndoExecutor()

        let oldHead = try await gitRevParse("HEAD", in: fixture.cloneURL)
        await syncState.performPullBranch(branch: "main", repositoryURL: fixture.cloneURL, undoManager: undoManager)
        let newHead = try await gitRevParse("HEAD", in: fixture.cloneURL)

        XCTAssertNotEqual(oldHead, newHead)
        XCTAssertEqual(undoManager.undoStack.last?.label, "Pull")

        guard let entry = undoManager.popForUndo() else {
            XCTFail("Expected an undo entry")
            return
        }
        try await executor.execute(entry.undoOperation, in: fixture.cloneURL)
        let afterUndo = try await gitRevParse("HEAD", in: fixture.cloneURL)
        XCTAssertEqual(afterUndo, oldHead)

        undoManager.completeUndo(entry)
        guard let redoEntry = undoManager.popForRedo() else {
            XCTFail("Expected a redo entry")
            return
        }
        try await executor.execute(redoEntry.redoOperation, in: fixture.cloneURL)
        let afterRedo = try await gitRevParse("HEAD", in: fixture.cloneURL)
        XCTAssertEqual(afterRedo, newHead)
    }

    @MainActor
    func testPublishUndoAndRedoRoundTrip() async throws {
        let fixture = try makePublishFixture()
        let syncState = SyncState()
        let undoManager = GitUndoManager()
        let executor = GitUndoExecutor()

        await syncState.performPush(
            options: GitStatusService.PushOptions(remote: "origin", branches: ["feature"]),
            repositoryURL: fixture.sourceURL,
            undoManager: undoManager
        )

        let support = GitRemoteUndoSupport()
        let publishedHash = try await support.remoteHash(remote: "origin", branch: "feature", in: fixture.sourceURL)
        XCTAssertNotNil(publishedHash)
        XCTAssertEqual(undoManager.undoStack.last?.label, "Publish origin/feature")

        guard let entry = undoManager.popForUndo() else {
            XCTFail("Expected an undo entry")
            return
        }
        try await executor.execute(entry.undoOperation, in: fixture.sourceURL)
        let afterUndo = try await support.remoteHash(remote: "origin", branch: "feature", in: fixture.sourceURL)
        XCTAssertNil(afterUndo)

        undoManager.completeUndo(entry)
        guard let redoEntry = undoManager.popForRedo() else {
            XCTFail("Expected a redo entry")
            return
        }
        try await executor.execute(redoEntry.redoOperation, in: fixture.sourceURL)
        let afterRedo = try await support.remoteHash(remote: "origin", branch: "feature", in: fixture.sourceURL)
        XCTAssertEqual(afterRedo, publishedHash)
    }

    func testRemoteNamesCollectsUniqueRemotesFromSequences() {
        let operation = GitUndoOperation.sequence([
            .createLocalBranch(name: "topic", startPoint: "abc", checkout: false),
            .pushBranch(remote: "origin", localBranch: "abc", remoteBranch: "refs/heads/topic"),
            .sequence([.deleteRemoteBranch(remote: "fork", branch: "topic", expectedHash: "abc")]),
            .pushBranch(remote: "origin", localBranch: "def", remoteBranch: "refs/heads/other"),
        ])

        XCTAssertEqual(GitUndoExecutor.remoteNames(in: operation), ["origin", "fork"])
        XCTAssertEqual(GitUndoExecutor.remoteNames(in: .setUpstream(branch: "a", upstream: "origin/a")), [])
    }

    func testBackgroundEligibilityCoversRemoteOnlyEntries() {
        let deleteEntry = GitBranchUndoSupport.deletedBranchUndoEntry(
            repositoryURL: URL(fileURLWithPath: "/tmp/repo"),
            branch: "topic",
            force: true,
            tip: "abc",
            upstream: "origin/topic",
            remoteTarget: RemoteBranchDeleteTarget(remote: "origin", branch: "topic"),
            remoteHash: "abc"
        )
        let localOnlyDelete = GitBranchUndoSupport.deletedBranchUndoEntry(
            repositoryURL: URL(fileURLWithPath: "/tmp/repo"),
            branch: "topic",
            force: true,
            tip: "abc",
            upstream: nil,
            remoteTarget: nil,
            remoteHash: nil
        )
        let plan = BranchForcePushPlan(
            id: UUID(),
            remote: "origin",
            remoteURL: "/tmp/remote.git",
            localBranch: "main",
            remoteBranch: "main",
            localHash: "def",
            remoteHash: "abc",
            removedCommitCount: 1,
            isDefaultBranch: true
        )

        XCTAssertTrue(GitUndoExecutor.canRunInBackground(deleteEntry.undoOperation))
        XCTAssertTrue(GitUndoExecutor.canRunInBackground(deleteEntry.redoOperation))
        XCTAssertTrue(GitUndoExecutor.canRunInBackground(.deleteRemoteBranch(remote: "origin", branch: "topic", expectedHash: "abc")))
        XCTAssertTrue(GitUndoExecutor.canRunInBackground(.pushBranch(remote: "origin", localBranch: "topic", remoteBranch: "topic")))
        XCTAssertTrue(GitUndoExecutor.canRunInBackground(.replaceRemoteBranch(plan, restoring: true)))

        XCTAssertFalse(GitUndoExecutor.canRunInBackground(localOnlyDelete.undoOperation), "No remote, stays foreground")
        XCTAssertFalse(GitUndoExecutor.canRunInBackground(.resetHead(target: "abc", mode: .hard, expectedHead: "def")))
        XCTAssertFalse(GitUndoExecutor.canRunInBackground(.sequence([
            .createLocalBranch(name: "topic", startPoint: "abc", checkout: true),
            .pushBranch(remote: "origin", localBranch: "topic", remoteBranch: "topic"),
        ])))
        XCTAssertFalse(GitUndoExecutor.canRunInBackground(.sequence([
            .updateLocalBranch(name: "main", newTip: "abc", expectedTip: "def"),
            .pushBranch(remote: "origin", localBranch: "main", remoteBranch: "main"),
        ])))
    }

    @MainActor
    func testRemoteUndoOperationsConsultCredentialResolverBeforeRunningGit() async throws {
        let fixture = try makePublishFixture()
        try runGit(["remote", "add", "gh", "https://github.com/octocat/Hello-World.git"], in: fixture.sourceURL)
        let resolver = GitProviderCredentialResolver(
            accounts: [makeUndoProviderAccount(id: "connection-1"), makeUndoProviderAccount(id: "connection-2", username: "monalisa")],
            tokenVault: EmptyUndoTokenVault()
        )
        let executor = GitUndoExecutor()

        for operation: GitUndoOperation in [
            .pushBranch(remote: "gh", localBranch: "feature", remoteBranch: "feature"),
            .deleteRemoteBranch(remote: "gh", branch: "feature", expectedHash: "abc"),
        ] {
            do {
                try await executor.execute(operation, in: fixture.sourceURL, credentialResolver: resolver)
                XCTFail("Expected the resolver error for \(operation)")
            } catch {
                XCTAssertEqual(error as? GitProviderCredentialError, .multipleMatchingAccounts(host: "github.com"))
            }
        }
    }

    @MainActor
    func testPublishUndoAndRedoRoundTripWithCredentialResolver() async throws {
        let fixture = try makePublishFixture()
        let syncState = SyncState()
        let undoManager = GitUndoManager()
        let executor = GitUndoExecutor()
        let resolver = GitProviderCredentialResolver(accounts: [], tokenVault: EmptyUndoTokenVault())

        await syncState.performPush(
            options: GitStatusService.PushOptions(remote: "origin", branches: ["feature"]),
            repositoryURL: fixture.sourceURL,
            undoManager: undoManager
        )
        let support = GitRemoteUndoSupport()
        let publishedHash = try await support.remoteHash(remote: "origin", branch: "feature", in: fixture.sourceURL)
        let entry = try XCTUnwrap(undoManager.popForUndo())

        try await executor.execute(entry.undoOperation, in: fixture.sourceURL, credentialResolver: resolver)
        let afterUndo = try await support.remoteHash(remote: "origin", branch: "feature", in: fixture.sourceURL)
        XCTAssertNil(afterUndo)

        undoManager.completeUndo(entry)
        let redoEntry = try XCTUnwrap(undoManager.popForRedo())
        try await executor.execute(redoEntry.redoOperation, in: fixture.sourceURL, credentialResolver: resolver)
        let afterRedo = try await support.remoteHash(remote: "origin", branch: "feature", in: fixture.sourceURL)
        XCTAssertEqual(afterRedo, publishedHash)
    }

    private func makeUndoProviderAccount(id: String, username: String = "octocat") -> GitProviderAccount {
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

    private func makePullFixture() throws -> (sourceURL: URL, remoteURL: URL, cloneURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-pull-undo-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("source", isDirectory: true)
        let remoteURL = root.appendingPathComponent("remote.git", isDirectory: true)
        let cloneURL = root.appendingPathComponent("clone", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: sourceURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: sourceURL)
        try runGit(["config", "user.email", "tests@example.com"], in: sourceURL)
        try "base\n".write(to: sourceURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: sourceURL)
        try runGit(["commit", "-m", "initial"], in: sourceURL)
        try runGit(["init", "--bare", remoteURL.path], in: root)
        try runGit(["remote", "add", "origin", remoteURL.path], in: sourceURL)
        try runGit(["push", "-u", "origin", "main"], in: sourceURL)
        try runGit(["clone", remoteURL.path, cloneURL.path], in: root)
        try "pulled\n".write(to: sourceURL.appendingPathComponent("pulled.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "pulled.txt"], in: sourceURL)
        try runGit(["commit", "-m", "pulled"], in: sourceURL)
        try runGit(["push", "origin", "main"], in: sourceURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (sourceURL, remoteURL, cloneURL)
    }

    private func makePublishFixture() throws -> (sourceURL: URL, remoteURL: URL, cloneURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-publish-undo-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("source", isDirectory: true)
        let remoteURL = root.appendingPathComponent("remote.git", isDirectory: true)
        let cloneURL = root.appendingPathComponent("clone", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: sourceURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: sourceURL)
        try runGit(["config", "user.email", "tests@example.com"], in: sourceURL)
        try "base\n".write(to: sourceURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: sourceURL)
        try runGit(["commit", "-m", "initial"], in: sourceURL)
        try runGit(["init", "--bare", remoteURL.path], in: root)
        try runGit(["remote", "add", "origin", remoteURL.path], in: sourceURL)
        try runGit(["push", "-u", "origin", "main"], in: sourceURL)
        try runGit(["checkout", "-b", "feature"], in: sourceURL)
        try "feature\n".write(to: sourceURL.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "feature.txt"], in: sourceURL)
        try runGit(["commit", "-m", "feature"], in: sourceURL)
        try runGit(["clone", remoteURL.path, cloneURL.path], in: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (sourceURL, remoteURL, cloneURL)
    }

    private func makeFixtureWithFeatureBranch() throws -> (remoteURL: URL, cloneURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-remote-undo-integration-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("source", isDirectory: true)
        let remoteURL = root.appendingPathComponent("remote.git", isDirectory: true)
        let cloneURL = root.appendingPathComponent("clone", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: sourceURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: sourceURL)
        try runGit(["config", "user.email", "tests@example.com"], in: sourceURL)
        try "base\n".write(to: sourceURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: sourceURL)
        try runGit(["commit", "-m", "initial"], in: sourceURL)
        try runGit(["init", "--bare", remoteURL.path], in: root)
        try runGit(["remote", "add", "origin", remoteURL.path], in: sourceURL)
        try runGit(["push", "-u", "origin", "main"], in: sourceURL)
        try runGit(["checkout", "-b", "feature"], in: sourceURL)
        try "feature\n".write(to: sourceURL.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "feature.txt"], in: sourceURL)
        try runGit(["commit", "-m", "feature"], in: sourceURL)
        try runGit(["push", "origin", "feature"], in: sourceURL)
        try runGit(["clone", remoteURL.path, cloneURL.path], in: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (remoteURL, cloneURL)
    }

    private func gitRevParse(_ ref: String, in directory: URL) async throws -> String {
        let output = try await GitStatusService.shared.runGit(arguments: ["rev-parse", ref], in: directory)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = directory
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

private final class EmptyUndoTokenVault: GitProviderTokenVault {
    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? { nil }
    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {}
    func deleteToken(for account: GitProviderAccount) throws {}
}
