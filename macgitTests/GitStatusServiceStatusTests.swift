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

    func testStatusPathsWithSpecialCharactersCanBeStaged() async throws {
        let repoURL = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let names = ["Screen Recording 2026-09-23.mov", "quote\"file.txt", "日本語.txt", "line\nbreak.txt", "tab\tfile.txt", "old -> new.txt", "back\\slash.txt"]
        for name in names {
            try "content".write(to: repoURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let service = GitStatusService.shared
        let status = try await service.status(for: repoURL)
        XCTAssertEqual(Set(status.untracked.map(\.path)), Set(names))
        for file in status.untracked {
            try await service.stage(file: file, in: repoURL)
        }
        let staged = try await service.status(for: repoURL)
        XCTAssertEqual(Set(staged.staged.map(\.path)), Set(names))
        XCTAssertTrue(staged.untracked.isEmpty)
    }

    func testStatusPreservesBothRenamePathsWithSpecialCharacters() async throws {
        let repoURL = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let oldPath = "old -> name\"日本語.txt"
        let newPath = "new name\nfinal.txt"
        try "rename content".write(to: repoURL.appendingPathComponent(oldPath), atomically: true, encoding: .utf8)
        try runGit(["add", "--", oldPath], in: repoURL)
        try runGit(["commit", "-m", "Add rename fixture"], in: repoURL)
        try runGit(["mv", "--", oldPath, newPath], in: repoURL)
        let status = try await GitStatusService.shared.status(for: repoURL)
        let renamed = try XCTUnwrap(status.staged.first { $0.status == .renamed })
        XCTAssertEqual(renamed.path, newPath)
        XCTAssertEqual(renamed.originalPath, oldPath)
    }

    func testStatusSnapshotObjectIDsChangeOnlyForStagedFile() async throws {
        let repoURL = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        for name in ["a file.txt", "b.txt"] {
            try "original".write(to: repoURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try runGit(["add", "--", "a file.txt", "b.txt"], in: repoURL)
        try runGit(["commit", "-m", "Add fixtures"], in: repoURL)
        for name in ["a file.txt", "b.txt"] {
            try "changed".write(to: repoURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try "new".write(to: repoURL.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)

        let before = try await GitStatusService.shared.statusSnapshot(for: repoURL)
        XCTAssertEqual(Set(before.status.unstaged.map(\.path)), ["a file.txt", "b.txt"])
        XCTAssertNotNil(before.objectIDs["a file.txt"])
        XCTAssertNil(before.objectIDs["untracked.txt"])

        try runGit(["add", "--", "a file.txt"], in: repoURL)
        let after = try await GitStatusService.shared.statusSnapshot(for: repoURL)
        XCTAssertNotEqual(after.objectIDs["a file.txt"], before.objectIDs["a file.txt"])
        XCTAssertEqual(after.objectIDs["b.txt"], before.objectIDs["b.txt"])
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

    func testStatusReportsFinderMoveAsDeletedAndUntracked() async throws {
        let repoURL = try makeTempRepo()
        try moveTrackedFile(in: repoURL)

        let status = try await GitStatusService.shared.status(for: repoURL)

        XCTAssertFalse(status.unstaged.contains { $0.status == .renamed },
                       "A move that is not staged should not be paired into a rename")
        XCTAssertTrue(status.unstaged.contains { $0.status == .deleted && $0.path == "tracked.txt" })
        XCTAssertEqual(status.untracked.map(\.path), ["relocated/tracked.txt"])
    }

    func testStatusAfterStashApplyMoveReportsAddedAndDeleted() async throws {
        let repoURL = try makeTempRepo()
        try moveTrackedFile(in: repoURL)
        try runGit(["add", "-A"], in: repoURL)
        try runGit(["stash", "push", "-m", "move"], in: repoURL)

        // Applying onto a clean tree loses the rename: the new file is staged as `A `
        // and the old one is a worktree deletion ` D`.
        try runGit(["stash", "apply"], in: repoURL)

        let status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(status.staged.contains { $0.status == .added && $0.path == "relocated/tracked.txt" })
        XCTAssertTrue(status.unstaged.contains { $0.status == .deleted && $0.path == "tracked.txt" })
        XCTAssertFalse(status.unstaged.contains { $0.status == .renamed })
    }

    func testStageAllOfFinderMoveRecordsIndexRename() async throws {
        let repoURL = try makeTempRepo()
        try moveTrackedFile(in: repoURL)

        let status = try await GitStatusService.shared.status(for: repoURL)
        try await GitStatusService.shared.stageAll(files: status.unstaged + status.untracked, in: repoURL)

        let after = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(
            after.staged.contains {
                $0.status == .renamed && $0.path == "relocated/tracked.txt" && $0.originalPath == "tracked.txt"
            },
            "Staging both sides of the move should record an index rename"
        )
        XCTAssertTrue(after.unstaged.isEmpty)
        XCTAssertTrue(after.untracked.isEmpty)
    }

    func testUnstageAllOnStagedRenameReturnsDeletedAndUntracked() async throws {
        let repoURL = try makeTempRepo()
        try moveTrackedFile(in: repoURL)
        try runGit(["add", "-A"], in: repoURL)

        let staged = try await GitStatusService.shared.status(for: repoURL)
        let stagedRename = try XCTUnwrap(staged.staged.first { $0.status == .renamed })

        try await GitStatusService.shared.unstageAll(files: [stagedRename], in: repoURL)

        let after = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(after.staged.isEmpty, "Staging area should be empty after unstaging a rename")
        XCTAssertTrue(after.unstaged.contains { $0.status == .deleted && $0.path == "tracked.txt" })
        XCTAssertEqual(after.untracked.map(\.path), ["relocated/tracked.txt"])
    }

    func testSortedForListOrdersByFileNameThenPath() {
        let files = [
            StatusFile(path: "src/b.swift", status: .modified, originalPath: nil),
            StatusFile(path: "docs/CHANGELOG.md", status: .untracked, originalPath: nil),
            StatusFile(path: "a.txt", status: .modified, originalPath: nil),
            StatusFile(path: "CHANGELOG.md", status: .deleted, originalPath: nil)
        ]

        XCTAssertEqual(
            StatusFile.sortedForList(files).map(\.path),
            ["a.txt", "src/b.swift", "CHANGELOG.md", "docs/CHANGELOG.md"]
        )
    }

    private func moveTrackedFile(in repoURL: URL) throws {
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent("relocated"),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(
            at: repoURL.appendingPathComponent("tracked.txt"),
            to: repoURL.appendingPathComponent("relocated/tracked.txt")
        )
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

    func testStatusRefreshDoesNotRewriteIndexWithOptionalLocks() async throws {
        let repoURL = try makeTempRepo()
        let indexURL = repoURL.appendingPathComponent(".git/index")
        // Stale stat info makes a plain `git status` refresh and rewrite the index.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: repoURL.appendingPathComponent("tracked.txt").path
        )
        let indexBefore = try Data(contentsOf: indexURL)

        let status = try await GitStatusService.shared.status(for: repoURL)
        let counts = await GitStatusService.shared.trackedStatusCounts(in: repoURL)

        XCTAssertTrue(status.staged.isEmpty && status.unstaged.isEmpty)
        XCTAssertEqual(counts.staged, 0)
        XCTAssertEqual(counts.unstaged, 0)
        XCTAssertEqual(try Data(contentsOf: indexURL), indexBefore)

        // Sanity check: without the environment, git does take the lock and rewrite the index.
        try runGit(["status", "--porcelain"], in: repoURL)
        XCTAssertNotEqual(try Data(contentsOf: indexURL), indexBefore)
    }

    func testStatusSucceedsWhileIndexLockIsHeld() async throws {
        let repoURL = try makeTempRepo()
        try "local\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        let lockURL = repoURL.appendingPathComponent(".git/index.lock")
        try Data().write(to: lockURL)
        defer { try? FileManager.default.removeItem(at: lockURL) }

        let status = try await GitStatusService.shared.status(for: repoURL)

        XCTAssertEqual(status.unstaged.map(\.path), ["tracked.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
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
