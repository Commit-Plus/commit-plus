//
//  GitFileUndoSnapshotStoreTests.swift
//  macgitTests
//

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

final class GitFileUndoSnapshotStoreTests: XCTestCase {
    func testCaptureAndRestoreExistingFile() throws {
        let repoURL = try makeRepoDirectory()
        let fileURL = repoURL.appendingPathComponent("Notes.txt")
        try "before\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = GitFileUndoSnapshotStore()

        let snapshot = try store.capture(paths: ["Notes.txt"], in: repoURL)
        try "after\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try store.restore(snapshotID: snapshot.id, in: repoURL)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "before\n")
    }

    func testCaptureAndRestoreMissingFileRemovesCurrentFile() throws {
        let repoURL = try makeRepoDirectory()
        let store = GitFileUndoSnapshotStore()

        let snapshot = try store.capture(paths: ["Missing.txt"], in: repoURL)
        try "created later\n".write(to: repoURL.appendingPathComponent("Missing.txt"), atomically: true, encoding: .utf8)
        try store.restore(snapshotID: snapshot.id, in: repoURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("Missing.txt").path))
    }

    func testCaptureRestoreAndDeleteInLinkedWorktree() throws {
        let repositoryURL = try makeGitRepository()
        let worktreeURL = repositoryURL.deletingLastPathComponent()
            .appendingPathComponent("linked-worktree-\(UUID().uuidString)", isDirectory: true)
        try runGit(["worktree", "add", "-b", "linked-worktree", worktreeURL.path], in: repositoryURL)
        addTeardownBlock {
            try? self.runGit(["worktree", "remove", "--force", worktreeURL.path], in: repositoryURL)
            try? FileManager.default.removeItem(at: repositoryURL)
        }

        let gitMarkerURL = worktreeURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitMarkerURL.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)

        let fileURL = worktreeURL.appendingPathComponent("Notes.md")
        try "before\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = GitFileUndoSnapshotStore()
        let snapshot = try store.capture(paths: ["Notes.md"], in: worktreeURL)

        try "after\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try store.restore(snapshotID: snapshot.id, in: worktreeURL)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "before\n")

        let snapshotDirectory = try store.undoRoot(in: worktreeURL)
            .appendingPathComponent(snapshot.id.uuidString, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotDirectory.path))
        try store.delete(snapshotID: snapshot.id, in: worktreeURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotDirectory.path))
    }

    private func makeRepoDirectory() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-file-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL.appendingPathComponent(".git"), withIntermediateDirectories: true)
        return repoURL
    }

    private func makeGitRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-file-snapshot-repository-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repositoryURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
        try "base\n".write(
            to: repositoryURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], in: repositoryURL)
        try runGit(["commit", "-m", "initial"], in: repositoryURL)
        return repositoryURL
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
            let output = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git failed"
            throw GitError.commandFailed(output)
        }
    }
}
