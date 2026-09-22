// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class RevisionBrowserServiceTests: XCTestCase {
    private let service = GitStatusService.shared

    func testSnapshotNestedUnusualPathsAndReadOnlyState() async throws {
        let repo = try makeRepository()
        let names = ["tab\tline\n日本語.txt", "space name.txt", "-option", ":(glob)*"]
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("nested/deep"), withIntermediateDirectories: true)
        let original = "first\r\n\nlast without newline"
        for name in names { try original.write(to: repo.appendingPathComponent("nested/deep/" + name), atomically: true, encoding: .utf8) }
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "snapshot"], in: repo)
        let snapshot = try await service.browserSnapshot(revision: "HEAD", in: repo)
        try git(["rm", "-r", "nested"], in: repo)
        try git(["commit", "-m", "delete files"], in: repo)
        try "staged".write(to: repo.appendingPathComponent("dirty.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try "unstaged".write(to: repo.appendingPathComponent("dirty.txt"), atomically: true, encoding: .utf8)
        let indexBefore = try Data(contentsOf: repo.appendingPathComponent(".git/index"))
        let headBefore = try git(["rev-parse", "HEAD"], in: repo)
        let root = try await service.browserEntries(treeID: snapshot.commitID, parentPath: "", in: repo)
        XCTAssertEqual(root.map(\.path), ["nested"])
        XCTAssertTrue(snapshot.changedNodePaths.contains("nested"))
        XCTAssertTrue(snapshot.changedNodePaths.contains("nested/deep"))
        for name in names { XCTAssertTrue(snapshot.changedNodePaths.contains("nested/deep/" + name)) }
        let nested = try await service.browserEntries(treeID: XCTUnwrap(root.first).objectID, parentPath: "nested", in: repo)
        let files = try await service.browserEntries(treeID: XCTUnwrap(nested.first).objectID, parentPath: "nested/deep", in: repo)
        XCTAssertEqual(Set(files.map(\.name)), Set(names))
        for file in files {
            let preview = try await service.browserPreview(entry: file, in: repo)
            XCTAssertEqual(preview.text, original)
            XCTAssertNil(preview.message)
        }
        XCTAssertEqual(try Data(contentsOf: repo.appendingPathComponent(".git/index")), indexBefore)
        XCTAssertEqual(try git(["rev-parse", "HEAD"], in: repo), headBefore)
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("dirty.txt"), encoding: .utf8), "unstaged")
    }

    func testSpecialObjectsAndLargeBlob() async throws {
        let repo = try makeRepository()
        try git(["commit", "--allow-empty", "-m", "root"], in: repo)
        let sha = try git(["rev-parse", "HEAD"], in: repo)
        try FileManager.default.createSymbolicLink(atPath: repo.appendingPathComponent("link").path, withDestinationPath: "missing-target")
        try Data([0, 255, 1]).write(to: repo.appendingPathComponent("binary"))
        try Data(repeating: 65, count: 2_000_001).write(to: repo.appendingPathComponent("large"))
        try Data().write(to: repo.appendingPathComponent("empty"))
        try "version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 123\n".write(to: repo.appendingPathComponent("lfs"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try git(["update-index", "--add", "--cacheinfo", "160000", sha, "submodule"], in: repo)
        try git(["commit", "-m", "objects"], in: repo)
        let snapshot = try await service.browserSnapshot(revision: "HEAD", in: repo)
        let entries = try await service.browserEntries(treeID: snapshot.commitID, parentPath: "", in: repo)
        var results: [String: RevisionFilePreview] = [:]
        for entry in entries { results[entry.path] = try await service.browserPreview(entry: entry, in: repo) }
        XCTAssertEqual(results["link"]?.text, "missing-target")
        XCTAssertTrue(results["link"]?.message?.contains("Symbolic link") == true)
        XCTAssertTrue(results["binary"]?.message?.contains("Binary") == true)
        XCTAssertTrue(results["large"]?.message?.contains("2 MB") == true)
        XCTAssertNil(results["large"]?.text)
        XCTAssertEqual(results["empty"]?.text, "")
        XCTAssertTrue(results["lfs"]?.message?.contains("LFS pointer") == true)
        XCTAssertTrue(results["submodule"]?.message?.contains(sha) == true)
        // An incorrect caller-provided size must not bypass the process output bound.
        let large = try XCTUnwrap(entries.first { $0.path == "large" })
        let spoofed = RevisionTreeEntry(path: large.path, objectID: large.objectID, mode: large.mode, objectType: "blob", size: 1)
        do { _ = try await service.browserPreview(entry: spoofed, in: repo); XCTFail("Expected output limit") }
        catch { XCTAssertTrue(error.localizedDescription.contains("limit")) }
    }

    func testEmptyRepositoryEmptyTreeInvalidRefAndMissingObject() async throws {
        let repo = try makeRepository()
        do { _ = try await service.browserSnapshot(revision: "HEAD", in: repo); XCTFail("Unborn HEAD") } catch {}
        try git(["commit", "--allow-empty", "-m", "empty"], in: repo)
        try git(["tag", "-a", "release", "-m", "release"], in: repo)
        let snapshot = try await service.browserSnapshot(revision: "release", in: repo)
        let entries = try await service.browserEntries(treeID: snapshot.commitID, parentPath: "", in: repo)
        XCTAssertTrue(entries.isEmpty)
        for ref in ["--all", "missing", "HEAD:file"] {
            do { _ = try await service.browserSnapshot(revision: ref, in: repo); XCTFail("Invalid revision") } catch {}
        }
        do {
            _ = try await service.browserPreview(entry: RevisionTreeEntry(path: "missing", objectID: String(repeating: "a", count: 40), mode: "100644", objectType: "blob", size: 1), in: repo)
            XCTFail("Missing object")
        } catch {}
    }

    func testChangedNodesIncludeRenameAndDeletionAncestorsButNotUnchangedFiles() async throws {
        let repo = try makeRepository()
        for folder in ["old", "new", "deleted"] {
            try FileManager.default.createDirectory(at: repo.appendingPathComponent(folder), withIntermediateDirectories: true)
            try "unchanged".write(to: repo.appendingPathComponent(folder + "/keep"), atomically: true, encoding: .utf8)
        }
        try "rename content".write(to: repo.appendingPathComponent("old/file"), atomically: true, encoding: .utf8)
        try "delete".write(to: repo.appendingPathComponent("deleted/file"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "initial"], in: repo)
        try git(["mv", "old/file", "new/file"], in: repo)
        try git(["rm", "deleted/file"], in: repo)
        try git(["commit", "-m", "rename and delete"], in: repo)
        let snapshot = try await service.browserSnapshot(revision: "HEAD", in: repo)
        XCTAssertEqual(snapshot.changedNodePaths, ["old", "old/file", "new", "new/file", "deleted", "deleted/file"])
        try git(["commit", "--allow-empty", "-m", "empty"], in: repo)
        let empty = try await service.browserSnapshot(revision: "HEAD", in: repo)
        XCTAssertTrue(empty.changedNodePaths.isEmpty)
    }

    func testMergeHighlightsChangesRelativeToFirstParent() async throws {
        let repo = try makeRepository()
        try git(["commit", "--allow-empty", "-m", "initial"], in: repo)
        try git(["checkout", "-b", "feature"], in: repo)
        try "feature".write(to: repo.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "feature"], in: repo)
        try git(["checkout", "main"], in: repo)
        try "main".write(to: repo.appendingPathComponent("main.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "main"], in: repo)
        try git(["merge", "--no-ff", "feature", "-m", "merge"], in: repo)
        let snapshot = try await service.browserSnapshot(revision: "HEAD", in: repo)
        XCTAssertEqual(snapshot.changedNodePaths, ["feature.txt"])
    }

    func testMalformedTreeAndTextLimits() throws {
        XCTAssertThrowsError(try GitStatusService.parseBrowserEntries(Data("bad record".utf8), parentPath: ""))
        XCTAssertThrowsError(try GitStatusService.validateBrowserObjectID("--help"))
        let invalid = try GitStatusService.decodeBrowserPreview(Data([255]), isSymlink: false)
        XCTAssertNil(invalid.text)
        let longLine = String(repeating: "a", count: 16_001)
        let preview = try GitStatusService.decodeBrowserPreview(Data(longLine.utf8), isSymlink: false)
        XCTAssertEqual(preview.text, longLine)
        XCTAssertTrue(preview.lines.isEmpty)
        XCTAssertNotNil(preview.message)
    }

    private func makeRepository() throws -> URL {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("revision-tests-\(UUID())")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: repo) }
        try git(["init", "-b", "main"], in: repo)
        try git(["config", "user.name", "Tests"], in: repo)
        try git(["config", "user.email", "tests@example.com"], in: repo)
        try git(["config", "commit.gpgsign", "false"], in: repo)
        return repo
    }

    @discardableResult private func git(_ arguments: [String], in repo: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repo
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw GitError.commandFailed(output) }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
