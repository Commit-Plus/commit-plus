// SPDX-License-Identifier: AGPL-3.0-or-later
//
//  SyncStateBackgroundRemoteIntegrationTests.swift
//  macgitTests
//

import Combine
import XCTest
@testable import macgit

@MainActor
final class SyncStateBackgroundRemoteIntegrationTests: XCTestCase {
    func testBackgroundFetchUpdatesRemoteRefsWithoutSyncFlagsOrAlert() async throws {
        let fixture = try makeFixture()
        try commitAndPush("upstream change", file: "remote.txt", in: fixture.sourceURL)
        let expectedTip = try gitOutput(["rev-parse", "main"], in: fixture.sourceURL)
        let syncState = SyncState()
        let recorder = SyncFlagRecorder(syncState)

        let outcome = await syncState.performBackgroundFetch(
            options: GitStatusService.FetchOptions(),
            repositoryURL: fixture.cloneURL
        )

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(try gitOutput(["rev-parse", "origin/main"], in: fixture.cloneURL), expectedTip)
        XCTAssertFalse(recorder.sawSyncing)
        XCTAssertFalse(syncState.showingError)
    }

    func testAutomaticFetchIsDeferredWhileBackgroundWorkIsPending() async throws {
        let fixture = try makeFixture()
        let initialTip = try gitOutput(["rev-parse", "origin/main"], in: fixture.cloneURL)
        try commitAndPush("upstream change", file: "remote.txt", in: fixture.sourceURL)
        let expectedTip = try gitOutput(["rev-parse", "main"], in: fixture.sourceURL)
        let syncState = SyncState()
        var hasPendingBackgroundWork = true
        syncState.shouldDeferAutomaticFetch = { hasPendingBackgroundWork }

        let deferred = await syncState.performAutomaticFetch(
            options: GitStatusService.FetchOptions(),
            repositoryURL: fixture.cloneURL,
            force: false
        )

        XCTAssertFalse(deferred)
        XCTAssertEqual(try gitOutput(["rev-parse", "origin/main"], in: fixture.cloneURL), initialTip)
        await syncState.waitForAutomaticFetchToFinish()

        // A deferred fetch does not count toward the throttle or backoff.
        hasPendingBackgroundWork = false
        let fetched = await syncState.performAutomaticFetch(
            options: GitStatusService.FetchOptions(),
            repositoryURL: fixture.cloneURL,
            force: false
        )

        XCTAssertTrue(fetched)
        XCTAssertEqual(try gitOutput(["rev-parse", "origin/main"], in: fixture.cloneURL), expectedTip)
    }

    func testBackgroundFetchReportsMissingRemoteFailure() async throws {
        let fixture = try makeFixture()
        try runGit(["remote", "set-url", "origin", fixture.root.appendingPathComponent("missing.git").path], in: fixture.cloneURL)
        let syncState = SyncState()

        let outcome = await syncState.performBackgroundFetch(
            options: GitStatusService.FetchOptions(),
            repositoryURL: fixture.cloneURL
        )

        guard case .failed(let message) = outcome else {
            return XCTFail("Expected failure, got \(outcome)")
        }
        XCTAssertTrue(message.hasPrefix("Could not fetch 'origin'"), message)
        XCTAssertFalse(syncState.showingError)
    }

    func testBackgroundFetchAppliesPartialSuccessAndNamesFailingRemote() async throws {
        let fixture = try makeFixture()
        try runGit(["remote", "add", "upstream", fixture.root.appendingPathComponent("missing.git").path], in: fixture.cloneURL)
        try commitAndPush("origin change", file: "remote.txt", in: fixture.sourceURL)
        let expectedTip = try gitOutput(["rev-parse", "main"], in: fixture.sourceURL)
        let syncState = SyncState()

        let outcome = await syncState.performBackgroundFetch(
            options: GitStatusService.FetchOptions(),
            repositoryURL: fixture.cloneURL
        )

        guard case .failed(let message) = outcome else {
            return XCTFail("Expected failure, got \(outcome)")
        }
        XCTAssertTrue(message.hasPrefix("Could not fetch 'upstream'"), message)
        XCTAssertTrue(message.contains("Fetched origin."), message)
        XCTAssertTrue(
            RepositoryOperationProgress.backgroundErrorSummary(message).hasPrefix("Could not fetch 'upstream'")
        )
        XCTAssertEqual(try gitOutput(["rev-parse", "origin/main"], in: fixture.cloneURL), expectedTip)
        XCTAssertFalse(syncState.showingError)
    }

    func testBackgroundPushPublishRegistersUndoAfterSuccess() async throws {
        let fixture = try makeFixture()
        try runGit(["checkout", "-b", "feature"], in: fixture.cloneURL)
        try commit("feature", file: "feature.txt", in: fixture.cloneURL)
        let syncState = SyncState()
        let undoManager = GitUndoManager()
        let recorder = SyncFlagRecorder(syncState)

        let outcome = await syncState.performBackgroundPush(
            options: GitStatusService.PushOptions(remote: "origin", branches: ["feature"]),
            repositoryURL: fixture.cloneURL,
            undoManager: undoManager
        )

        XCTAssertEqual(outcome, .succeeded)
        XCTAssertEqual(undoManager.undoStack.last?.label, "Publish origin/feature")
        XCTAssertEqual(
            try gitOutput(["rev-parse", "feature"], in: fixture.remoteURL),
            try gitOutput(["rev-parse", "feature"], in: fixture.cloneURL)
        )
        XCTAssertFalse(recorder.sawSyncing)
        XCTAssertNil(syncState.activeSyncBranch)
        XCTAssertFalse(syncState.showingError)
    }

    func testBackgroundPushRejectedNonFastForwardReturnsFailure() async throws {
        let fixture = try makeFixture()
        try commitAndPush("remote ahead", file: "remote.txt", in: fixture.sourceURL)
        try commit("local diverged", file: "local.txt", in: fixture.cloneURL)
        let syncState = SyncState()
        let undoManager = GitUndoManager()

        let outcome = await syncState.performBackgroundPush(
            options: GitStatusService.PushOptions(remote: "origin", branches: ["main"]),
            repositoryURL: fixture.cloneURL,
            undoManager: undoManager
        )

        guard case .failed(let message) = outcome else {
            return XCTFail("Expected failure, got \(outcome)")
        }
        XCTAssertTrue(message.contains("Force Push"), message)
        XCTAssertTrue(undoManager.undoStack.isEmpty)
        XCTAssertFalse(syncState.isPushing)
        XCTAssertFalse(syncState.showingError)
    }

    // MARK: - Helpers

    private final class SyncFlagRecorder {
        private(set) var sawSyncing = false
        private var cancellables: Set<AnyCancellable> = []

        init(_ syncState: SyncState) {
            syncState.$isFetching.sink { [weak self] in if $0 { self?.sawSyncing = true } }.store(in: &cancellables)
            syncState.$isPushing.sink { [weak self] in if $0 { self?.sawSyncing = true } }.store(in: &cancellables)
        }
    }

    private struct Fixture {
        let root: URL
        let sourceURL: URL
        let remoteURL: URL
        let cloneURL: URL
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-background-remote-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("source", isDirectory: true)
        let remoteURL = root.appendingPathComponent("remote.git", isDirectory: true)
        let cloneURL = root.appendingPathComponent("clone", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: sourceURL)
        try configureIdentity(in: sourceURL)
        try commit("initial", file: "tracked.txt", in: sourceURL)
        try runGit(["init", "--bare", "-b", "main", remoteURL.path], in: root)
        try runGit(["remote", "add", "origin", remoteURL.path], in: sourceURL)
        try runGit(["push", "-u", "origin", "main"], in: sourceURL)
        try runGit(["clone", remoteURL.path, cloneURL.path], in: root)
        try configureIdentity(in: cloneURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Fixture(root: root, sourceURL: sourceURL, remoteURL: remoteURL, cloneURL: cloneURL)
    }

    private func configureIdentity(in directory: URL) throws {
        try runGit(["config", "user.name", "Mac Git Tests"], in: directory)
        try runGit(["config", "user.email", "tests@example.com"], in: directory)
    }

    private func commit(_ message: String, file: String, in directory: URL) throws {
        try "\(message)\n".write(to: directory.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try runGit(["add", file], in: directory)
        try runGit(["commit", "-m", message], in: directory)
    }

    private func commitAndPush(_ message: String, file: String, in directory: URL) throws {
        try commit(message, file: file, in: directory)
        try runGit(["push", "origin", "main"], in: directory)
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

    private func gitOutput(_ arguments: [String], in directory: URL) throws -> String {
        try runGit(arguments, in: directory).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
