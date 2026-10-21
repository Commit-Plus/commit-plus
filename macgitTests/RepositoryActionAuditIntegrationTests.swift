// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class RepositoryActionAuditIntegrationTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let sourceURL: URL
        let cloneURL: URL
    }

    func testPushAndCommitAreRecordedWithOutput() async throws {
        let fixture = try makeFixture()
        try "change\n".write(to: fixture.cloneURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try await GitStatusService.shared.runGit(arguments: ["add", "--", "tracked.txt"], in: fixture.cloneURL)
        _ = try await GitStatusService.shared.runGit(arguments: ["commit", "-m", "change"], in: fixture.cloneURL)
        _ = try await GitStatusService.shared.runGit(arguments: ["push", "origin", "main"], in: fixture.cloneURL)
        _ = try await GitStatusService.shared.runGit(arguments: ["status", "--porcelain"], in: fixture.cloneURL)
        _ = try await GitStatusService.shared.runGit(arguments: ["log", "-1", "--format=%H"], in: fixture.cloneURL)

        let summaries = await summaries(for: fixture.cloneURL)

        XCTAssertEqual(summaries.map(\.title), ["Push origin", "Commit", "Add tracked.txt"])
        XCTAssertTrue(summaries.allSatisfy { $0.status == .succeeded && $0.origin == .user })
        let push = try await entry(summaries[0])
        XCTAssertEqual(push.command, "push origin main")
        // Git reports push results on stderr, which the audit keeps on success.
        XCTAssertTrue(push.output.contains("main -> main"), push.output)
    }

    func testFailedCommandRecordsError() async throws {
        let fixture = try makeFixture()
        do {
            _ = try await GitStatusService.shared.runGit(arguments: ["checkout", "missing-branch"], in: fixture.cloneURL)
            XCTFail("Expected checkout to fail")
        } catch {}

        let summaries = await summaries(for: fixture.cloneURL)

        XCTAssertEqual(summaries.first?.title, "Checkout missing-branch")
        XCTAssertEqual(summaries.first?.status, .failed)
        let failure = try await entry(try XCTUnwrap(summaries.first))
        XCTAssertTrue(failure.output.contains("missing-branch"), failure.output)
    }

    func testStagingLinesRecordsApply() async throws {
        let fixture = try makeFixture()
        let patch = """
        diff --git a/tracked.txt b/tracked.txt
        --- a/tracked.txt
        +++ b/tracked.txt
        @@ -1 +1 @@
        -initial
        +staged

        """
        try "staged\n".write(to: fixture.cloneURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try await GitStatusService.shared.applyPatch(patch, in: fixture.cloneURL, cached: true)

        let summaries = await summaries(for: fixture.cloneURL)

        XCTAssertEqual(summaries.first?.title, "Apply")
        let apply = try await entry(try XCTUnwrap(summaries.first))
        XCTAssertEqual(apply.command, "apply --cached -")
    }

    func testAutomaticFetchIsSystemAndUserFetchIsUser() async throws {
        let fixture = try makeFixture()
        let syncState = SyncState()

        let fetched = await syncState.performAutomaticFetch(
            options: GitStatusService.FetchOptions(),
            repositoryURL: fixture.cloneURL,
            force: true
        )
        XCTAssertTrue(fetched)
        let outcome = await syncState.performBackgroundFetch(
            options: GitStatusService.FetchOptions(),
            repositoryURL: fixture.cloneURL
        )
        XCTAssertEqual(outcome, .succeeded)

        let summaries = await summaries(for: fixture.cloneURL)

        XCTAssertEqual(summaries.map(\.title), ["Fetch origin", "Fetch origin"])
        XCTAssertEqual(summaries.map(\.origin), [.user, .system])
    }

    private func summaries(for repositoryURL: URL) async -> [RepositoryActionAuditSummary] {
        await RepositoryActionAuditStore.shared.summaries(repositoryPath: repositoryURL.standardizedFileURL.path)
    }

    private func entry(_ summary: RepositoryActionAuditSummary) async throws -> RepositoryActionAuditEntry {
        let entry = await RepositoryActionAuditStore.shared.entry(id: summary.id)
        return try XCTUnwrap(entry)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-action-audit-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("source", isDirectory: true)
        let remoteURL = root.appendingPathComponent("remote.git", isDirectory: true)
        let cloneURL = root.appendingPathComponent("clone", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: sourceURL)
        try configureIdentity(in: sourceURL)
        try "initial\n".write(to: sourceURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: sourceURL)
        try runGit(["commit", "-m", "initial"], in: sourceURL)
        try runGit(["init", "--bare", "-b", "main", remoteURL.path], in: root)
        try runGit(["remote", "add", "origin", remoteURL.path], in: sourceURL)
        try runGit(["push", "-u", "origin", "main"], in: sourceURL)
        try runGit(["clone", remoteURL.path, cloneURL.path], in: root)
        try configureIdentity(in: cloneURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Fixture(root: root, sourceURL: sourceURL, cloneURL: cloneURL)
    }

    private func configureIdentity(in directory: URL) throws {
        try runGit(["config", "user.name", "Mac Git Tests"], in: directory)
        try runGit(["config", "user.email", "tests@example.com"], in: directory)
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
}
