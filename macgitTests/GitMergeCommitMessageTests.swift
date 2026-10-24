// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class GitMergeCommitMessageTests: XCTestCase {
    func testCleanedMergeCommitMessageDropsConflictComments() {
        let rawMessage = """
        Merge branch 'main' of https://github.com/Commit-Plus/commit-plus

        # Conflicts:
        #\tmacgitTests/GitProviderAccountControllerTests.swift

        """

        XCTAssertEqual(
            GitStatusService.cleanedMergeCommitMessage(rawMessage),
            "Merge branch 'main' of https://github.com/Commit-Plus/commit-plus"
        )
    }

    func testCleanedMergeCommitMessageKeepsBodyAndCollapsesBlankLines() {
        let rawMessage = "Merge branch 'feature'\n\n\n# comment\n\nKeep this body\n  indented line\n"

        XCTAssertEqual(
            GitStatusService.cleanedMergeCommitMessage(rawMessage),
            "Merge branch 'feature'\n\nKeep this body\n  indented line"
        )
    }

    func testMergeCommitMessageReadsMergeMsgFromConflictedMerge() async throws {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("merge-message-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let fileURL = repositoryURL.appendingPathComponent("file.txt")
        try git(["init", "-b", "main"], in: repositoryURL)
        try git(["config", "user.name", "Test"], in: repositoryURL)
        try git(["config", "user.email", "test@example.com"], in: repositoryURL)
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["add", "."], in: repositoryURL)
        try git(["commit", "-m", "base"], in: repositoryURL)
        try git(["checkout", "-b", "feature"], in: repositoryURL)
        try "feature\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["commit", "-am", "feature"], in: repositoryURL)
        try git(["checkout", "main"], in: repositoryURL)
        try "main\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try git(["commit", "-am", "main"], in: repositoryURL)
        _ = try? git(["merge", "feature"], in: repositoryURL)

        let isMergeInProgress = await GitStatusService.shared.isMergeInProgress(in: repositoryURL)
        let message = await GitStatusService.shared.mergeCommitMessage(in: repositoryURL)

        XCTAssertTrue(isMergeInProgress)
        XCTAssertEqual(message, "Merge branch 'feature'")
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "git", code: Int(process.terminationStatus))
        }
        return process.terminationStatus
    }
}
