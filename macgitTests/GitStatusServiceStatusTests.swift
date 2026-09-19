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

@MainActor
final class GitStatusServiceStatusTests: XCTestCase {
    func testRunGitDrainsLargeStandardOutputWhileProcessIsRunning() async throws {
        let repoURL = try makeTempRepo()
        let payload = String(repeating: "x", count: 1_000_000)
        try payload.write(
            to: repoURL.appendingPathComponent("large-output.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "large-output.txt"], in: repoURL)
        try runGit(["commit", "-m", "add large output"], in: repoURL)

        let operation = Task {
            try await GitStatusService.shared.runGit(
                arguments: ["show", "HEAD:large-output.txt"],
                in: repoURL
            )
        }
        let completed = expectation(description: "large Git output completes")
        Task {
            _ = try? await operation.value
            completed.fulfill()
        }

        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 3)
        guard result == .completed else {
            operation.cancel()
            XCTFail("Git command blocked while writing large stdout")
            return
        }

        let output = try await operation.value
        XCTAssertEqual(output.count, payload.count)
    }

    func testStatusIncludesUntrackedBinaryFile() async throws {
        let repoURL = try makeTempRepo()
        let fileURL = repoURL.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D]).write(to: fileURL)

        let status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(status.untracked.contains { $0.path == "clip.mp4" }, "Untracked .mp4 file should appear in status")
    }

    func testStatusHidesUntrackedEmbeddedGitRepository() async throws {
        let repoURL = try makeTempRepo()
        let nested = repoURL.appendingPathComponent("Package/cki-tool")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: nested)
        try "nested\n".write(to: nested.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try "plain\n".write(to: repoURL.appendingPathComponent("plain.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: repoURL.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try "doc\n".write(to: repoURL.appendingPathComponent("docs/readme.md"), atomically: true, encoding: .utf8)

        let status = try await GitStatusService.shared.status(for: repoURL)

        XCTAssertFalse(
            status.untracked.contains { $0.path.hasPrefix("Package/") },
            "Embedded git repository should be hidden like other clients"
        )
        XCTAssertTrue(status.untracked.contains { $0.path == "plain.txt" })
        XCTAssertTrue(
            status.untracked.contains { $0.path == "docs/readme.md" },
            "Normal untracked directories must still be listed"
        )
    }

    func testStatusIncludesModifiedBinaryFile() async throws {
        let repoURL = try makeTempRepo()
        let fileURL = repoURL.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]).write(to: fileURL)
        try runGit(["add", "clip.mp4"], in: repoURL)
        try runGit(["commit", "-m", "add video"], in: repoURL)

        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0xAA]).write(to: fileURL)

        let status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(status.unstaged.contains { $0.path == "clip.mp4" }, "Modified tracked .mp4 file should appear in status")
    }

    func testStatusCollapsesFinderMoveIntoRenamedEntry() async throws {
        let repoURL = try makeTempRepo()
        let oldURL = repoURL.appendingPathComponent("tracked.txt")
        let newURL = repoURL.appendingPathComponent("subdir/tracked.txt")

        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent("subdir"),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: oldURL, to: newURL)

        let status = try await GitStatusService.shared.status(for: repoURL)

        XCTAssertTrue(status.unstaged.contains { $0.status == .renamed },
                      "A file moved on disk should be reported as renamed")
        let rename = try XCTUnwrap(status.unstaged.first { $0.status == .renamed })
        XCTAssertEqual(rename.path, "subdir/tracked.txt")
        XCTAssertEqual(rename.originalPath, "tracked.txt")
        XCTAssertFalse(status.unstaged.contains { $0.status == .deleted && $0.path == "tracked.txt" },
                       "Worktree deletion should be consumed by the rename pairing")
        XCTAssertFalse(status.untracked.contains { $0.path == "subdir/tracked.txt" },
                       "Untracked entry at the new path should be consumed by the rename pairing")
    }

    func testStatusReportsDeletedAndUntrackedSeparatelyWhenBasenamesDiffer() async throws {
        let (staged, returnedUnstaged, returnedUntracked) = GitStatusService.pairWorktreeRenames(
            staged: [],
            unstaged: [
                StatusFile(path: "old/photo.png", status: .deleted, originalPath: nil)
            ],
            untracked: [
                StatusFile(path: "new/image.png", status: .untracked, originalPath: nil)
            ]
        )

        XCTAssertTrue(staged.isEmpty)
        XCTAssertEqual(returnedUnstaged.compactMap { $0.status == .deleted ? $0.path : nil },
                       ["old/photo.png"],
                       "Files with different basenames should not be paired")
        XCTAssertEqual(returnedUntracked.map(\.path), ["new/image.png"])
    }

    func testStatusAfterStashApplyMoveSurfacesRenamedEntry() async throws {
        let repoURL = try makeTempRepo()
        let oldURL = repoURL.appendingPathComponent("tracked.txt")
        let newURL = repoURL.appendingPathComponent("relocated/tracked.txt")
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent("relocated"),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        try runGit(["add", "-A"], in: repoURL)
        try runGit(["stash", "push", "-m", "move"], in: repoURL)

        // After `git stash push` the working tree matches HEAD, so the
        // relocated file is already gone. Applying the stash should put the
        // rename back into the worktree as `A ` + ` D` (because Git loses
        // the rename connection when re-applying onto a clean tree).
        try runGit(["stash", "apply"], in: repoURL)

        let status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(status.unstaged.contains { $0.status == .renamed },
                      "A stash-apply of a file move should be reported as renamed in the unstaged section")
    }

    func testPairWorktreeRenamesGroupsDAndUntrackedWithSameBasename() {
        let deleted = StatusFile(path: "old/notes.md", status: .deleted, originalPath: nil)
        let untracked = StatusFile(path: "new/notes.md", status: .untracked, originalPath: nil)
        let modifiedKept = StatusFile(path: "other.txt", status: .modified, originalPath: nil)
        let untrackedKept = StatusFile(path: "scratch.txt", status: .untracked, originalPath: nil)

        let (_, unstaged, remaining) = GitStatusService.pairWorktreeRenames(
            staged: [],
            unstaged: [deleted, modifiedKept],
            untracked: [untracked, untrackedKept]
        )

        XCTAssertEqual(unstaged.map(\.path), ["other.txt", "new/notes.md"])
        XCTAssertEqual(unstaged.last?.status, .renamed)
        XCTAssertEqual(unstaged.last?.originalPath, "old/notes.md")
        XCTAssertEqual(remaining.map(\.path), ["scratch.txt"])
    }

    func testPairWorktreeRenamesGroupsDAndStagedAddedWithSameBasename() {
        let deleted = StatusFile(path: "old/notes.md", status: .deleted, originalPath: nil)
        let stagedAdded = StatusFile(path: "new/notes.md", status: .added, originalPath: nil)
        let stagedKept = StatusFile(path: "staged.txt", status: .staged, originalPath: nil)

        let (staged, unstaged, untracked) = GitStatusService.pairWorktreeRenames(
            staged: [stagedAdded, stagedKept],
            unstaged: [deleted],
            untracked: []
        )

        XCTAssertEqual(staged.map(\.path), ["staged.txt"])
        XCTAssertEqual(unstaged.map(\.path), ["new/notes.md"])
        XCTAssertEqual(unstaged.last?.status, .renamed)
        XCTAssertEqual(unstaged.last?.originalPath, "old/notes.md")
        XCTAssertTrue(untracked.isEmpty)
    }

    func testStageAllCollapsesFinderMoveIntoIndexRename() async throws {
        let repoURL = try makeTempRepo()
        let newURL = repoURL.appendingPathComponent("relocated/tracked.txt")
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent("relocated"),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(
            at: repoURL.appendingPathComponent("tracked.txt"),
            to: newURL
        )

        let status = try await GitStatusService.shared.status(for: repoURL)
        let rename = try XCTUnwrap(status.unstaged.first { $0.status == .renamed })

        try await GitStatusService.shared.stageAll(files: [rename], in: repoURL)

        let after = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(
            after.staged.contains { $0.status == .renamed && $0.path == "relocated/tracked.txt" },
            "After staging, the move should be recorded as an index rename"
        )
        XCTAssertFalse(
            after.staged.contains { $0.status == .added && $0.path == "relocated/tracked.txt" },
            "The new path should not appear as a plain index addition"
        )
        XCTAssertTrue(after.unstaged.isEmpty, "No unstaged entries should remain after staging a rename")
    }

    func testUnstageAllOnStagedRenameReturnsWorktreeRenameRow() async throws {
        let repoURL = try makeTempRepo()
        let newURL = repoURL.appendingPathComponent("relocated/tracked.txt")
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent("relocated"),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(
            at: repoURL.appendingPathComponent("tracked.txt"),
            to: newURL
        )

        let status = try await GitStatusService.shared.status(for: repoURL)
        let rename = try XCTUnwrap(status.unstaged.first { $0.status == .renamed })
        try await GitStatusService.shared.stageAll(files: [rename], in: repoURL)

        let staged = try await GitStatusService.shared.status(for: repoURL)
        let stagedRename = try XCTUnwrap(staged.staged.first { $0.status == .renamed })

        try await GitStatusService.shared.unstageAll(files: [stagedRename], in: repoURL)

        let after = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(after.staged.isEmpty, "Staging area should be empty after unstaging a rename")
        XCTAssertTrue(
            after.unstaged.contains {
                $0.status == .renamed
                && $0.path == "relocated/tracked.txt"
                && $0.originalPath == "tracked.txt"
            },
            "Unstaging a rename should leave it as a worktree rename row in the unstaged section"
        )
        XCTAssertTrue(after.untracked.isEmpty,
                      "The new path should be consumed by the worktree rename pairing")
    }

    func testStatusDrainsLargeUntrackedOutputWithoutDeadlocking() async throws {
        let repoURL = try makeTempRepo()
        let filesURL = repoURL.appendingPathComponent("generated", isDirectory: true)
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)

        let fileCount = 2_000
        for index in 0..<fileCount {
            let filename = String(format: "generated-file-%04d-with-a-long-name-to-exceed-the-process-pipe-buffer.txt", index)
            try Data().write(to: filesURL.appendingPathComponent(filename))
        }

        let status = try await GitStatusService.shared.status(for: repoURL)
        let count = await GitStatusService.shared.uncommittedChangeCount(in: repoURL)

        XCTAssertEqual(status.untracked.count, fileCount)
        XCTAssertEqual(count, fileCount)
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-status-binary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)

        let trackedFile = repoURL.appendingPathComponent("tracked.txt")
        try "base\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial commit"], in: repoURL)

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
            let outputData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "git failed"
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(output)")
        }
    }
}
