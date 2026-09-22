// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class BranchComparisonServiceTests: XCTestCase {
    private let service = GitStatusService.shared

    func testDirectionCountsUniqueCommitsAndReadOnlyWorktree() async throws {
        let repo = try makeRepository()
        try "uncommitted\n".write(to: repo.appendingPathComponent("dirty.txt"), atomically: true, encoding: .utf8)
        let statusBefore = try git(["status", "--porcelain=v1"], in: repo)
        let headBefore = try git(["rev-parse", "HEAD"], in: repo)
        let snapshot = try await compare(in: repo)
        XCTAssertEqual(snapshot.baseOnlyCount, 1)
        XCTAssertEqual(snapshot.targetOnlyCount, 1)
        let review = try await service.comparisonFiles(snapshot: snapshot, mode: .mergeBase, in: repo)
        let tips = try await service.comparisonFiles(snapshot: snapshot, mode: .tips, in: repo)
        XCTAssertFalse(review.contains { $0.path == "main.txt" })
        XCTAssertTrue(tips.contains { $0.path == "main.txt" && $0.status == .deleted })
        let target = try await service.comparisonCommits(snapshot: snapshot, targetSide: true, skip: 0, limit: 100, in: repo)
        let base = try await service.comparisonCommits(snapshot: snapshot, targetSide: false, skip: 0, limit: 100, in: repo)
        XCTAssertEqual(target.map(\.message), ["feature work"])
        XCTAssertEqual(base.map(\.message), ["main work"])
        let swapped = try await service.comparisonSnapshot(base: "refs/heads/feature", target: "refs/heads/main", branchesOnly: true, in: repo)
        let swappedFiles = try await service.comparisonFiles(snapshot: swapped, mode: .mergeBase, in: repo)
        XCTAssertEqual(swappedFiles.map(\.path), ["main.txt"])
        XCTAssertEqual(try git(["status", "--porcelain=v1"], in: repo), statusBefore)
        XCTAssertEqual(try git(["rev-parse", "HEAD"], in: repo), headBefore)
    }

    func testRenameUnusualPathsBinaryAndEmptyFiles() async throws {
        let repo = try makeRepository()
        let snapshot = try await compare(in: repo)
        let files = try await service.comparisonFiles(snapshot: snapshot, mode: .mergeBase, in: repo)
        let rename = try XCTUnwrap(files.first { $0.status == .renamed })
        XCTAssertEqual(rename.oldPath, "old\tname.txt")
        XCTAssertEqual(rename.path, "new\nname.txt")
        let renamePatch = try await service.comparisonPatch(file: rename, snapshot: snapshot, mode: .mergeBase, in: repo)
        XCTAssertTrue(renamePatch.hunks.isEmpty)
        let binary = try XCTUnwrap(files.first { $0.path == "binary.dat" })
        let binaryPatch = try await service.comparisonPatch(file: binary, snapshot: snapshot, mode: .mergeBase, in: repo)
        XCTAssertTrue(binaryPatch.isBinary)
        let empty = try XCTUnwrap(files.first { $0.path == "empty.txt" })
        XCTAssertEqual(empty.status, .added)
        let emptyPatch = try await service.comparisonPatch(file: empty, snapshot: snapshot, mode: .mergeBase, in: repo)
        XCTAssertFalse(emptyPatch.isBinary)
        XCTAssertTrue(emptyPatch.hunks.isEmpty)
        XCTAssertTrue(files.contains { $0.path == "deleted.txt" && $0.status == .deleted })
        let modified = try XCTUnwrap(files.first { $0.path == "tracked.txt" })
        XCTAssertEqual(modified.status, .modified)
        let modifiedPatch = try await service.comparisonPatch(file: modified, snapshot: snapshot, mode: .mergeBase, in: repo)
        XCTAssertTrue(modifiedPatch.hunks.flatMap(\.lines).contains { $0.type == .added && $0.text == "feature" })
    }

    func testAvailableRemoteBranchesAndRefValidation() async throws {
        let repo = try makeRepository()
        try git(["update-ref", "refs/remotes/origin/feature", "feature"], in: repo)
        try git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/feature"], in: repo)
        let branches = try await service.comparisonBranches(in: repo)
        XCTAssertTrue(branches.contains { $0.ref == "refs/remotes/origin/feature" })
        XCTAssertFalse(branches.contains { $0.ref == "refs/remotes/origin/HEAD" })
        let remote = try await service.comparisonSnapshot(base: "refs/heads/main", target: "refs/remotes/origin/feature", branchesOnly: true, in: repo)
        XCTAssertEqual(remote.targetOnlyCount, 1)
        for invalid in ["main", "--all", "refs/heads/missing", "refs/heads/main^", "refs/tags/release"] {
            do {
                _ = try await service.comparisonSnapshot(base: invalid, target: "refs/heads/main", branchesOnly: true, in: repo)
                XCTFail("Accepted invalid branch: \(invalid)")
            } catch { XCTAssertFalse(error is CancellationError) }
        }
    }

    func testIdenticalRefsAndUnrelatedHistories() async throws {
        let repo = try makeRepository()
        let identical = try await service.comparisonSnapshot(base: "refs/heads/main", target: "refs/heads/main", branchesOnly: true, in: repo)
        let files = try await service.comparisonFiles(snapshot: identical, mode: .mergeBase, in: repo)
        XCTAssertTrue(files.isEmpty)
        XCTAssertEqual(identical.baseOnlyCount + identical.targetOnlyCount, 0)
        try git(["checkout", "--orphan", "unrelated"], in: repo)
        try git(["commit", "-m", "other root"], in: repo)
        let unrelated = try await service.comparisonSnapshot(base: "refs/heads/main", target: "refs/heads/unrelated", branchesOnly: true, in: repo)
        XCTAssertTrue(unrelated.mergeBases.isEmpty)
        do {
            _ = try await service.comparisonFiles(snapshot: unrelated, mode: .mergeBase, in: repo)
            XCTFail("Expected missing merge-base error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("no common ancestor")) }
        _ = try await service.comparisonFiles(snapshot: unrelated, mode: .tips, in: repo)
    }

    func testSnapshotSurvivesBranchMovementAndCommitPagination() async throws {
        let repo = try makeRepository()
        let snapshot = try await compare(in: repo)
        try git(["checkout", "feature"], in: repo)
        try git(["commit", "--allow-empty", "-m", "second"], in: repo)
        try git(["commit", "--allow-empty", "-m", "third"], in: repo)
        let original = try await service.comparisonCommits(snapshot: snapshot, targetSide: true, skip: 0, limit: 100, in: repo)
        XCTAssertEqual(original.map(\.message), ["feature work"])
        let updated = try await compare(in: repo)
        let first = try await service.comparisonCommits(snapshot: updated, targetSide: true, skip: 0, limit: 2, in: repo)
        let next = try await service.comparisonCommits(snapshot: updated, targetSide: true, skip: 2, limit: 2, in: repo)
        XCTAssertEqual(first.map(\.message), ["third", "second"])
        XCTAssertEqual(next.map(\.message), ["feature work"])
    }

    func testTagComparisonRemainsTipToTip() async throws {
        let repo = try makeRepository()
        try git(["tag", "release", "feature"], in: repo)
        let snapshot = try await service.comparisonSnapshot(base: "release", target: "HEAD", branchesOnly: false, in: repo)
        let files = try await service.comparisonFiles(snapshot: snapshot, mode: .tips, in: repo)
        XCTAssertTrue(files.contains { $0.path == "main.txt" && $0.status == .added })
        XCTAssertTrue(files.contains { $0.path == "empty.txt" && $0.status == .deleted })
    }

    func testParserRejectsIncompleteRenameRecord() throws {
        XCTAssertThrowsError(try GitStatusService.parseComparisonFiles(Data("R100\0old\0".utf8)))
    }

    func testPathComparisonWorkingTreeIncludesStagedAndUnstagedWithoutMutation() async throws {
        let repo = try makeRepository()
        try "staged\n".write(to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try git(["add", "tracked.txt"], in: repo)
        try "working\n".write(to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "new staged\n".write(to: repo.appendingPathComponent("added.txt"), atomically: true, encoding: .utf8)
        try git(["add", "added.txt"], in: repo)
        try "ignored untracked\n".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        let indexBefore = try Data(contentsOf: repo.appendingPathComponent(".git/index"))
        let headBefore = try git(["rev-parse", "HEAD"], in: repo)
        let path = ComparisonPath(path: ".", isDirectory: true)
        let snapshot = try await service.pathComparisonSnapshot(base: "HEAD", target: .workingTree, path: path, in: repo)
        let files = try await service.comparisonFiles(snapshot: snapshot, mode: .tips, in: repo)
        XCTAssertEqual(Set(files.map(\.path)), ["tracked.txt", "added.txt"])
        let file = try XCTUnwrap(files.first { $0.path == "tracked.txt" })
        let patch = try await service.comparisonPatch(file: file, snapshot: snapshot, mode: .tips, in: repo)
        XCTAssertTrue(patch.hunks.flatMap(\.lines).contains { $0.type == .added && $0.text == "working" })
        let staged = try await service.pathComparisonSnapshot(base: "HEAD", target: .index, path: path, in: repo)
        let stagedPatch = try await service.comparisonPatch(file: file, snapshot: staged, mode: .tips, in: repo)
        XCTAssertTrue(stagedPatch.hunks.flatMap(\.lines).contains { $0.type == .added && $0.text == "staged" })
        XCTAssertEqual(try Data(contentsOf: repo.appendingPathComponent(".git/index")), indexBefore)
        XCTAssertEqual(try git(["rev-parse", "HEAD"], in: repo), headBefore)
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent("tracked.txt"), encoding: .utf8), "working\n")
    }

    func testFolderComparisonIncludesCrossBoundaryRenamesAndExcludesSiblingPrefix() async throws {
        let repo = try makeRepository()
        for folder in ["src", "src-other"] {
            try FileManager.default.createDirectory(at: repo.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try "move out\n".write(to: repo.appendingPathComponent("src/out.txt"), atomically: true, encoding: .utf8)
        try "sibling\n".write(to: repo.appendingPathComponent("src-other/file.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "folders"], in: repo)
        try git(["mv", "src/out.txt", "outside.txt"], in: repo)
        try git(["mv", "tracked.txt", "src/in.txt"], in: repo)
        try "changed\n".write(to: repo.appendingPathComponent("src-other/file.txt"), atomically: true, encoding: .utf8)
        let snapshot = try await service.pathComparisonSnapshot(base: "HEAD", target: .workingTree,
            path: ComparisonPath(path: "src", isDirectory: true), in: repo)
        let files = try await service.comparisonFiles(snapshot: snapshot, mode: .tips, in: repo)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy { $0.status == .renamed })
        XCTAssertTrue(files.contains { $0.oldPath == "src/out.txt" && $0.path == "outside.txt" })
        XCTAssertTrue(files.contains { $0.oldPath == "tracked.txt" && $0.path == "src/in.txt" })
    }

    func testPathComparisonSupportsTagsRemoteRefsAndBinaryRevisionChanges() async throws {
        let repo = try makeRepository()
        try git(["tag", "-a", "release", "-m", "release", "feature"], in: repo)
        try git(["update-ref", "refs/remotes/origin/feature", "feature"], in: repo)
        let revisions = try await service.comparisonRevisions(in: repo)
        XCTAssertTrue(revisions.contains("refs/tags/release"))
        XCTAssertTrue(revisions.contains("refs/remotes/origin/feature"))
        let snapshot = try await service.pathComparisonSnapshot(base: "HEAD", target: .revision("refs/tags/release"),
            path: ComparisonPath(path: "binary.dat", isDirectory: false), in: repo)
        let files = try await service.comparisonFiles(snapshot: snapshot, mode: .tips, in: repo)
        XCTAssertEqual(files.map(\.path), ["binary.dat"])
        XCTAssertEqual(files.first?.status, .added)
        let patch = try await service.comparisonPatch(file: XCTUnwrap(files.first), snapshot: snapshot, mode: .tips, in: repo)
        XCTAssertTrue(patch.isBinary)
    }

    func testLiteralPathComparisonAndMissingSide() async throws {
        let repo = try makeRepository()
        let paths = ["-option.txt", ":(glob)*", "space 日本語.txt", "tab\tline\n.txt"]
        for path in paths {
            try "before\n".write(to: repo.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "unusual paths"], in: repo)
        for path in paths {
            try "after\n".write(to: repo.appendingPathComponent(path), atomically: true, encoding: .utf8)
            let snapshot = try await service.pathComparisonSnapshot(base: "HEAD", target: .workingTree,
                path: ComparisonPath(path: path, isDirectory: false), in: repo)
            let files = try await service.comparisonFiles(snapshot: snapshot, mode: .tips, in: repo)
            XCTAssertEqual(files.map(\.path), [path])
            let patch = try await service.comparisonPatch(file: XCTUnwrap(files.first), snapshot: snapshot, mode: .tips, in: repo)
            XCTAssertEqual(patch.hunks.flatMap(\.lines).filter { $0.type == .added }.map(\.text), ["after"])
        }
        try FileManager.default.removeItem(at: repo.appendingPathComponent("deleted.txt"))
        let snapshot = try await service.pathComparisonSnapshot(base: "HEAD", target: .workingTree,
            path: ComparisonPath(path: "deleted.txt", isDirectory: false), in: repo)
        let files = try await service.comparisonFiles(snapshot: snapshot, mode: .tips, in: repo)
        XCTAssertEqual(files.first?.status, .deleted)
        let empty = try await service.pathComparisonSnapshot(base: "HEAD", target: .revision("HEAD"),
            path: ComparisonPath(path: "missing", isDirectory: true), in: repo)
        let emptyFiles = try await service.comparisonFiles(snapshot: empty, mode: .tips, in: repo)
        XCTAssertTrue(emptyFiles.isEmpty)
        for ref in ["--all", "missing-revision", "HEAD:tracked.txt"] {
            do {
                _ = try await service.pathComparisonSnapshot(base: ref, target: .workingTree,
                    path: ComparisonPath(path: ".", isDirectory: true), in: repo)
                XCTFail("Accepted invalid revision")
            } catch { XCTAssertFalse(error is CancellationError) }
        }
        for path in ["../escape", "/absolute", "a/../b", "a\0b"] {
            XCTAssertThrowsError(try ComparisonPath(path: path, isDirectory: false).validate())
        }
    }

    private func compare(in repo: URL) async throws -> ReferenceComparisonSnapshot {
        try await service.comparisonSnapshot(base: "refs/heads/main", target: "refs/heads/feature", branchesOnly: true, in: repo)
    }

    private func makeRepository() throws -> URL {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("compare-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: repo) }
        try git(["init", "-b", "main"], in: repo)
        try git(["config", "user.name", "Comparison Tests"], in: repo)
        try git(["config", "user.email", "tests@example.com"], in: repo)
        try git(["config", "commit.gpgsign", "false"], in: repo)
        for path in ["tracked.txt", "deleted.txt", "old\tname.txt"] {
            try "base \(path)\n".write(to: repo.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "initial"], in: repo)
        try git(["checkout", "-b", "feature"], in: repo)
        try "feature\n".write(to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: repo.appendingPathComponent("deleted.txt"))
        try FileManager.default.moveItem(at: repo.appendingPathComponent("old\tname.txt"), to: repo.appendingPathComponent("new\nname.txt"))
        try Data([0, 1, 2, 3]).write(to: repo.appendingPathComponent("binary.dat"))
        try Data().write(to: repo.appendingPathComponent("empty.txt"))
        try git(["add", "-A"], in: repo)
        try git(["commit", "-m", "feature work"], in: repo)
        try git(["checkout", "main"], in: repo)
        try "main\n".write(to: repo.appendingPathComponent("main.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "main work"], in: repo)
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
