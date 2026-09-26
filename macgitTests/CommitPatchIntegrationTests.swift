// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class CommitPatchIntegrationTests: XCTestCase {
    private var repositories: [URL] = []
    private let service = GitStatusService.shared

    override func tearDown() {
        for url in repositories { try? FileManager.default.removeItem(at: url) }
        repositories = []
        super.tearDown()
    }

    func testSelectedFileLeavesOtherFilesAndIndexUntouchedAndSupportsUndoRedo() async throws {
        let repo = try repository()
        try write("one\n", "a.txt", repo); try write("two\n", "b.txt", repo)
        let base = try commit(repo)
        try write("ONE\n", "a.txt", repo); try write("TWO\n", "b.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let indexBefore = try git(["ls-files", "--stage"], repo)
        let prepared = try await prepare(source, "a.txt", repo)
        try await service.applyCommitPatch(prepared)
        XCTAssertEqual(try read("a.txt", repo), "ONE\n")
        XCTAssertEqual(try read("b.txt", repo), "two\n")
        XCTAssertEqual(try git(["ls-files", "--stage"], repo), indexBefore)
        XCTAssertEqual(try git(["rev-parse", "HEAD"], repo), base)
        let executor = GitUndoExecutor()
        try await executor.execute(.checkedWorkingTreePatch(patch: prepared.patch, reverse: true), in: repo)
        XCTAssertEqual(try read("a.txt", repo), "one\n")
        try await executor.execute(.checkedWorkingTreePatch(patch: prepared.patch, reverse: false), in: repo)
        XCTAssertEqual(try read("a.txt", repo), "ONE\n")
    }

    func testSelectedAdditionPreservesUnselectedRemovalInBothDirections() async throws {
        let repo = try repository()
        try write("before\nold\nafter\n", "a.txt", repo)
        let base = try commit(repo)
        try write("before\nnew\nafter\n", "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let selection: Set<CommitPatchRequest.Line> = [.init(old: nil, new: 2)]
        let forward = try await prepare(source, "a.txt", repo, lines: selection)
        try await service.applyCommitPatch(forward)
        XCTAssertEqual(try read("a.txt", repo), "before\nold\nnew\nafter\n")
        try git(["reset", "--hard", source], repo)
        let reverse = try await prepare(source, "a.txt", repo, direction: .revert, lines: selection)
        try await service.applyCommitPatch(reverse)
        XCTAssertEqual(try read("a.txt", repo), "before\nafter\n")
    }

    func testSelectedRemovalInBothDirections() async throws {
        let repo = try repository()
        try write("before\nold\nafter\n", "a.txt", repo)
        let base = try commit(repo)
        try write("before\nnew\nafter\n", "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let selection: Set<CommitPatchRequest.Line> = [.init(old: 2, new: nil)]
        let forward = try await prepare(source, "a.txt", repo, lines: selection)
        try await service.applyCommitPatch(forward)
        XCTAssertEqual(try read("a.txt", repo), "before\nafter\n")
        try git(["reset", "--hard", source], repo)
        let reverse = try await prepare(source, "a.txt", repo, direction: .revert, lines: selection)
        try await service.applyCommitPatch(reverse)
        XCTAssertEqual(try read("a.txt", repo), "before\nnew\nold\nafter\n")
    }

    func testOneHunkPreservesDirtyChangesElsewhereInSameFileAndStagedFile() async throws {
        let repo = try repository()
        let original = (1...40).map { "line\($0)" }.joined(separator: "\n") + "\n"
        try write(original, "a.txt", repo); try write("base\n", "other.txt", repo)
        let base = try commit(repo)
        try write(original.replacingOccurrences(of: "line2\n", with: "changed2\n")
            .replacingOccurrences(of: "line25\n", with: "changed25\n"), "a.txt", repo)
        let source = try commit(repo)
        let hunks = await service.diff(for: "a.txt", in: source, in: repo)
        XCTAssertEqual(hunks.count, 2)
        let lines = Set(try XCTUnwrap(hunks.first).lines.filter { $0.type == .added || $0.type == .removed }.map(CommitPatchRequest.Line.init))
        try git(["checkout", "--detach", base], repo)
        try write(original.replacingOccurrences(of: "line38\n", with: "local38\n"), "a.txt", repo)
        try git(["add", "a.txt"], repo)
        try write(original.replacingOccurrences(of: "line38\n", with: "local38\n")
            .replacingOccurrences(of: "line39\n", with: "unstaged39\n"), "a.txt", repo)
        try write("staged\n", "other.txt", repo); try git(["add", "other.txt"], repo)
        try write("unstaged too\n", "other.txt", repo)
        let index = try git(["ls-files", "--stage"], repo)
        let prepared = try await prepare(source, "a.txt", repo, lines: lines)
        try await service.applyCommitPatch(prepared)
        let content = try read("a.txt", repo)
        XCTAssertTrue(content.contains("changed2\n")); XCTAssertTrue(content.contains("line25\n"))
        XCTAssertTrue(content.contains("local38\n"))
        XCTAssertTrue(content.contains("unstaged39\n"))
        XCTAssertEqual(try read("other.txt", repo), "unstaged too\n")
        XCTAssertEqual(try git(["ls-files", "--stage"], repo), index)
    }

    func testPartialAddAndReverseAddPreserveFileWhenLinesRemain() async throws {
        let repo = try repository()
        try write("base\n", "base.txt", repo)
        let base = try commit(repo)
        try write("first\nsecond\nthird\n", "new.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let lines: Set<CommitPatchRequest.Line> = [.init(old: nil, new: 2)]
        let forward = try await prepare(source, "new.txt", repo, lines: lines)
        try await service.applyCommitPatch(forward)
        XCTAssertEqual(try read("new.txt", repo), "second\n")
        try FileManager.default.removeItem(at: repo.appendingPathComponent("new.txt"))
        try git(["reset", "--hard", source], repo)
        let reverse = try await prepare(source, "new.txt", repo, direction: .revert, lines: lines)
        try await service.applyCommitPatch(reverse)
        XCTAssertEqual(try read("new.txt", repo), "first\nthird\n")
    }

    func testPartialDeleteAndReverseDelete() async throws {
        let repo = try repository()
        try write("first\nsecond\nthird\n", "a.txt", repo)
        let base = try commit(repo)
        try git(["rm", "a.txt"], repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let lines: Set<CommitPatchRequest.Line> = [.init(old: 2, new: nil)]
        let forward = try await prepare(source, "a.txt", repo, lines: lines)
        try await service.applyCommitPatch(forward)
        XCTAssertEqual(try read("a.txt", repo), "first\nthird\n")
        try git(["reset", "--hard", source], repo)
        let reverse = try await prepare(source, "a.txt", repo, direction: .revert, lines: lines)
        try await service.applyCommitPatch(reverse)
        XCTAssertEqual(try read("a.txt", repo), "second\n")
    }

    func testWholeRenameWithEditsForwardAndReverse() async throws {
        let repo = try repository()
        try write("a\nb\nc\nd\ne\nf\ng\nh\n", "old name.txt", repo)
        let base = try commit(repo)
        try git(["mv", "old name.txt", "new name.txt"], repo)
        try write("a\nB\nc\nd\ne\nf\ng\nh\n", "new name.txt", repo)
        let source = try commit(repo)
        let files = await service.changedFiles(in: source, in: repo)
        XCTAssertEqual(files.first?.oldPath, "old name.txt")
        try git(["checkout", "--detach", base], repo)
        let forward = try await prepare(source, "new name.txt", repo)
        try await service.applyCommitPatch(forward)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("old name.txt").path))
        XCTAssertTrue(try read("new name.txt", repo).contains("B\n"))
        try await service.applyCheckedWorkingTreePatch(forward.patch, reverse: true, in: repo)
        XCTAssertTrue(try read("old name.txt", repo).contains("b\n"))
        try git(["reset", "--hard", source], repo)
        let reverse = try await prepare(source, "new name.txt", repo, direction: .revert)
        try await service.applyCommitPatch(reverse)
        XCTAssertTrue(try read("old name.txt", repo).contains("b\n"))
    }

    func testConflictRejectsEntireMultiFilePatchWithoutMutation() async throws {
        let repo = try repository()
        try write("old\n", "a.txt", repo); try write("old\n", "b.txt", repo)
        let base = try commit(repo)
        try write("new\n", "a.txt", repo); try write("new\n", "b.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        try write("local\n", "b.txt", repo)
        let files = await service.changedFiles(in: source, in: repo)
        let review = try await service.prepareCommitPatch(.init(commit: source, files: files, direction: .apply, lines: nil, scope: "Files"), in: repo)
        XCTAssertTrue(review.hasConflicts)
        XCTAssertEqual(review.reviewFiles.first { $0.file.path == "a.txt" }?.state, .ready)
        await reject { try await self.service.applyCommitPatch(review) }
        XCTAssertEqual(try read("a.txt", repo), "old\n")
        XCTAssertEqual(try read("b.txt", repo), "local\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("a.txt.rej").path))
    }

    func testRevalidationRejectsEditsAndBranchMovementAfterReview() async throws {
        let repo = try repository()
        try write("old\n", "a.txt", repo)
        let base = try commit(repo)
        try write("new\n", "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let prepared = try await prepare(source, "a.txt", repo)
        try write("local\n", "a.txt", repo)
        await reject { try await self.service.applyCommitPatch(prepared) }
        XCTAssertEqual(try read("a.txt", repo), "local\n")
        try git(["reset", "--hard", base], repo)
        try git(["checkout", "-b", "another"], repo)
        await reject { try await self.service.applyCommitPatch(prepared) }
        XCTAssertEqual(try read("a.txt", repo), "old\n")
    }

    func testRootCommitAndQuotedPathWithNoFinalNewline() async throws {
        let repo = try repository()
        let path = "odd\t\"name.txt"
        try write("hello", path, repo)
        let source = try commit(repo)
        let reverse = try await prepare(source, path, repo, direction: .revert)
        try await service.applyCommitPatch(reverse)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent(path).path))
        let forward = try await prepare(source, path, repo)
        try await service.applyCommitPatch(forward)
        XCTAssertEqual(try read(path, repo), "hello")
    }

    func testBinaryAndSubmoduleRejectedAndHaveDisabledReasons() async throws {
        let repo = try repository()
        try write("base\n", "base.txt", repo)
        let base = try commit(repo)
        try Data([0, 1, 2, 0]).write(to: repo.appendingPathComponent("binary.bin"))
        _ = try commit(repo)
        try git(["update-index", "--add", "--cacheinfo", "160000,\(base),module"], repo)
        try git(["commit", "-m", "gitlink"], repo)
        // Include the binary modification in the same source commit.
        try git(["reset", "--soft", base], repo)
        try git(["commit", "-m", "binary and gitlink"], repo)
        let source = try git(["rev-parse", "HEAD"], repo)
        let reasons = try await service.commitPatchUnavailableReasons(commit: source, in: repo)
        XCTAssertTrue(reasons["binary.bin"]?.contains("Binary") == true)
        XCTAssertTrue(reasons["module"]?.contains("Submodule") == true)
        await reject { _ = try await self.prepare(source, "binary.bin", repo, direction: .revert) }
        await reject { _ = try await self.prepare(source, "module", repo, direction: .revert) }
    }

    func testMergeCommitRejected() async throws {
        let repo = try repository()
        try write("base\n", "a.txt", repo); _ = try commit(repo)
        try git(["checkout", "-b", "side"], repo)
        try write("side\n", "side.txt", repo); _ = try commit(repo)
        try git(["checkout", "main"], repo)
        try write("main\n", "main.txt", repo); _ = try commit(repo)
        try git(["merge", "--no-ff", "side", "-m", "merge"], repo)
        let source = try git(["rev-parse", "HEAD"], repo)
        await reject {
            _ = try await self.service.prepareCommitPatch(.init(commit: source,
                files: [.init(path: "side.txt", status: .added)], direction: .revert, lines: nil, scope: "File"), in: repo)
        }
    }

    func testPartialRenameIncludesRenameAndOnlySelectedContentBothDirections() async throws {
        let repo = try repository()
        let text = "a\nb\nc\nd\ne\nf\ng\nh\n"
        try write(text, "old.txt", repo)
        let base = try commit(repo)
        try git(["mv", "old.txt", "new.txt"], repo)
        try write(text.replacingOccurrences(of: "b\n", with: "B\n"), "new.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let lines: Set<CommitPatchRequest.Line> = [.init(old: nil, new: 2)]
        let forward = try await prepare(source, "new.txt", repo, lines: lines)
        try await service.applyCommitPatch(forward)
        XCTAssertEqual(try read("new.txt", repo), text.replacingOccurrences(of: "b\n", with: "b\nB\n"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("old.txt").path))
        try await service.applyCheckedWorkingTreePatch(forward.patch, reverse: true, in: repo)
        XCTAssertEqual(try read("old.txt", repo), text)
        try git(["reset", "--hard", source], repo)
        let reverse = try await prepare(source, "new.txt", repo, direction: .revert, lines: lines)
        try await service.applyCommitPatch(reverse)
        XCTAssertEqual(try read("old.txt", repo), text.replacingOccurrences(of: "b\n", with: ""))
    }

    func testMultiplePartialHunksRecalculateOffsetsWithoutIncludingOtherChanges() async throws {
        let repo = try repository()
        let text = (1...40).map { "line\($0)" }.joined(separator: "\n") + "\n"
        try write(text, "a.txt", repo)
        let base = try commit(repo)
        let changed = text.replacingOccurrences(of: "line2\n", with: "line2\nextra\n")
            .replacingOccurrences(of: "line22\n", with: "changed22\n")
        try write(changed, "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let lines: Set<CommitPatchRequest.Line> = [.init(old: nil, new: 3), .init(old: nil, new: 23)]
        let forward = try await prepare(source, "a.txt", repo, lines: lines)
        try await service.applyCommitPatch(forward)
        XCTAssertEqual(try read("a.txt", repo), text.replacingOccurrences(of: "line2\n", with: "line2\nextra\n")
            .replacingOccurrences(of: "line22\n", with: "line22\nchanged22\n"))
        try await service.applyCheckedWorkingTreePatch(forward.patch, reverse: true, in: repo)
        XCTAssertEqual(try read("a.txt", repo), text)
        try git(["reset", "--hard", source], repo)
        let reverse = try await prepare(source, "a.txt", repo, direction: .revert, lines: lines)
        try await service.applyCommitPatch(reverse)
        XCTAssertEqual(try read("a.txt", repo), text.replacingOccurrences(of: "line22\n", with: ""))
    }

    func testPartialReplacementOfUnterminatedLine() async throws {
        let repo = try repository()
        try write("old", "a.txt", repo)
        let base = try commit(repo)
        try write("new", "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let forward = try await prepare(source, "a.txt", repo, lines: [.init(old: nil, new: 1)])
        try await service.applyCommitPatch(forward)
        XCTAssertEqual(try read("a.txt", repo), "old\nnew")
        try await service.applyCheckedWorkingTreePatch(forward.patch, reverse: true, in: repo)
        XCTAssertEqual(try read("a.txt", repo), "old")
    }

    func testPartialCRLFChangesPreserveLineEndings() async throws {
        let repo = try repository()
        try git(["config", "core.autocrlf", "false"], repo)
        try write("before\r\nold\r\nafter\r\n", "a.txt", repo)
        let base = try commit(repo)
        try write("before\r\nnew\r\nafter\r\n", "a.txt", repo)
        let source = try commit(repo)
        let hunks = await service.diff(for: "a.txt", in: source, in: repo)
        let added = try XCTUnwrap(hunks.flatMap(\.lines).first { $0.type == .added })
        XCTAssertEqual(added.newLineNumber, 2)
        try git(["checkout", "--detach", base], repo)
        let forward = try await prepare(source, "a.txt", repo, lines: [.init(added)])
        try await service.applyCommitPatch(forward)
        XCTAssertEqual(try read("a.txt", repo), "before\r\nold\r\nnew\r\nafter\r\n")
    }

    func testEmptyAndStaleLineSelectionsRejectWithoutApplyingWholeHunk() async throws {
        let repo = try repository()
        try write("old\n", "a.txt", repo)
        let base = try commit(repo)
        try write("new\n", "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        await reject { _ = try await self.prepare(source, "a.txt", repo, lines: []) }
        await reject { _ = try await self.prepare(source, "a.txt", repo, lines: [.init(old: nil, new: 200)]) }
        XCTAssertEqual(try read("a.txt", repo), "old\n")
    }

    func testIndexChangeAfterReviewRejectsAndOverlappingUndoPreservesLaterEdit() async throws {
        let repo = try repository()
        try write("old\n", "a.txt", repo); try write("other\n", "other.txt", repo)
        let base = try commit(repo)
        try write("new\n", "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let prepared = try await prepare(source, "a.txt", repo)
        try write("staged\n", "other.txt", repo); try git(["add", "other.txt"], repo)
        await reject { try await self.service.applyCommitPatch(prepared) }
        XCTAssertEqual(try read("a.txt", repo), "old\n")
        let reviewed = try await prepare(source, "a.txt", repo)
        try await service.applyCommitPatch(reviewed)
        try write("later edit\n", "a.txt", repo)
        await reject { try await self.service.applyCheckedWorkingTreePatch(reviewed.patch, reverse: true, in: repo) }
        XCTAssertEqual(try read("a.txt", repo), "later edit\n")
        XCTAssertTrue(try git(["show", ":other.txt"], repo).contains("staged"))
    }

    func testPartialContentDoesNotIncludeUnselectedExecutableBit() async throws {
        let repo = try repository()
        try git(["config", "core.filemode", "true"], repo)
        try write("old\n", "script.sh", repo)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: repo.appendingPathComponent("script.sh").path)
        let base = try commit(repo)
        try write("new\n", "script.sh", repo)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.appendingPathComponent("script.sh").path)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let partial = try await prepare(source, "script.sh", repo, lines: [.init(old: 1, new: nil), .init(old: nil, new: 1)])
        try await service.applyCommitPatch(partial)
        let mode = try FileManager.default.attributesOfItem(atPath: repo.appendingPathComponent("script.sh").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual((mode?.intValue ?? 0) & 0o111, 0)
        XCTAssertEqual(try read("script.sh", repo), "new\n")
        try git(["reset", "--hard", base], repo)
        let whole = try await prepare(source, "script.sh", repo)
        try await service.applyCommitPatch(whole)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: repo.appendingPathComponent("script.sh").path))
    }

    func testInProgressOperationAndUntrackedCollisionRejectWithoutMutation() async throws {
        let repo = try repository()
        try write("base\n", "a.txt", repo)
        let base = try commit(repo)
        try write("new\n", "new.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        try write("local untracked\n", "new.txt", repo)
        let review = try await prepare(source, "new.txt", repo)
        XCTAssertTrue(review.hasConflicts)
        XCTAssertNil(review.reviewFiles.first?.conflict?.markedResult)
        await reject { try await self.service.applyCommitPatch(review) }
        XCTAssertEqual(try read("new.txt", repo), "local untracked\n")
        try FileManager.default.removeItem(at: repo.appendingPathComponent("new.txt"))
        let state = repo.appendingPathComponent(".git/sequencer")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        await reject { _ = try await self.prepare(source, "new.txt", repo) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("new.txt").path))
    }

    private func prepare(_ commit: String, _ path: String, _ repo: URL,
                         direction: CommitPatchRequest.Direction = .apply,
                         lines: Set<CommitPatchRequest.Line>? = nil) async throws -> PreparedCommitPatch {
        let files = await service.changedFiles(in: commit, in: repo)
        let file = try XCTUnwrap(files.first { $0.path == path })
        return try await service.prepareCommitPatch(.init(commit: commit, files: [file], direction: direction,
            lines: lines, scope: lines == nil ? "File" : "Lines"), in: repo)
    }

    func testAlreadyPresentBatchIsANoopAndMixedBatchAppliesOnlyMissingChanges() async throws {
        let repo = try repository()
        try write("old a\n", "a.txt", repo); try write("old b\n", "b.txt", repo)
        let base = try commit(repo)
        try write("new a\n", "a.txt", repo); try write("new b\n", "b.txt", repo)
        let source = try commit(repo)
        let files = await service.changedFiles(in: source, in: repo)
        let request = CommitPatchRequest(commit: source, files: files, direction: .apply, lines: nil, scope: "Files")
        let index = try git(["ls-files", "--stage"], repo)
        let already = try await service.prepareCommitPatch(request, in: repo)
        XCTAssertFalse(already.hasConflicts)
        XCTAssertFalse(already.hasChanges)
        XCTAssertTrue(already.reviewFiles.allSatisfy { $0.state == .alreadyApplied })
        XCTAssertTrue(already.reviewFiles.allSatisfy { !DiffParser.parse($0.patch).isEmpty }, "Already-present changes remain previewable")
        XCTAssertTrue(already.patch.isEmpty, "Preview patches must not be applied again")
        try await service.applyCommitPatch(already)
        XCTAssertEqual(try git(["ls-files", "--stage"], repo), index)
        try git(["checkout", "--detach", base], repo)
        try write("new a\n", "a.txt", repo)
        let mixed = try await service.prepareCommitPatch(request, in: repo)
        XCTAssertEqual(mixed.reviewFiles.first { $0.file.path == "a.txt" }?.state, .alreadyApplied)
        XCTAssertEqual(mixed.reviewFiles.first { $0.file.path == "b.txt" }?.state, .ready)
        try await service.applyCommitPatch(mixed)
        XCTAssertEqual(try read("a.txt", repo), "new a\n")
        XCTAssertEqual(try read("b.txt", repo), "new b\n")
        try await service.applyCheckedWorkingTreePatch(mixed.patch, reverse: true, in: repo)
        XCTAssertEqual(try read("a.txt", repo), "new a\n")
        XCTAssertEqual(try read("b.txt", repo), "old b\n")
    }

    func testThreeWayMergePreservesDirtyContextAndOnlySelectedLines() async throws {
        let repo = try repository()
        let original = (1...20).map { "line\($0)" }.joined(separator: "\n") + "\n"
        try write(original, "a.txt", repo)
        let base = try commit(repo)
        try write(original.replacingOccurrences(of: "line5\n", with: "selected5\n")
            .replacingOccurrences(of: "line15\n", with: "unselected15\n"), "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let local = original.replacingOccurrences(of: "line2\n", with: "local2\n")
        try write(local, "a.txt", repo)
        try git(["add", "a.txt"], repo)
        let staged = try git(["ls-files", "--stage"], repo)
        let review = try await prepare(source, "a.txt", repo, lines: [.init(old: 5, new: nil), .init(old: nil, new: 5)])
        XCTAssertEqual(review.reviewFiles.first?.state, .merged)
        XCTAssertEqual(try read("a.txt", repo), local, "Preparation/Cancel must not change files")
        XCTAssertEqual(try git(["ls-files", "--stage"], repo), staged)
        try await service.applyCommitPatch(review)
        XCTAssertEqual(try read("a.txt", repo), local.replacingOccurrences(of: "line5\n", with: "selected5\n"))
        XCTAssertEqual(try git(["ls-files", "--stage"], repo), staged)
        try await service.applyCheckedWorkingTreePatch(review.patch, reverse: true, in: repo)
        XCTAssertEqual(try read("a.txt", repo), local)
    }

    func testReverseThreeWayMergePreservesDirtyContext() async throws {
        let repo = try repository()
        let original = (1...20).map { "line\($0)" }.joined(separator: "\n") + "\n"
        try write(original, "a.txt", repo); _ = try commit(repo)
        let changed = original.replacingOccurrences(of: "line5\n", with: "selected5\n")
        try write(changed, "a.txt", repo)
        let source = try commit(repo)
        try write(changed.replacingOccurrences(of: "line2\n", with: "local2\n"), "a.txt", repo)
        let review = try await prepare(source, "a.txt", repo, direction: .revert)
        XCTAssertEqual(review.reviewFiles.first?.state, .merged)
        try await service.applyCommitPatch(review)
        XCTAssertEqual(try read("a.txt", repo), original.replacingOccurrences(of: "line2\n", with: "local2\n"))
    }

    func testConflictResolutionStaysInPreviewUntilFinalApplyAndUndoRestoresLocalEdits() async throws {
        let repo = try repository()
        let original = (1...20).map { "line\($0)" }.joined(separator: "\n") + "\n"
        try write(original, "a.txt", repo)
        let base = try commit(repo)
        try write(original.replacingOccurrences(of: "line5\n", with: "selected5\n")
            .replacingOccurrences(of: "line15\n", with: "selected15\n"), "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        let local = original.replacingOccurrences(of: "line5\n", with: "local5\n")
        try write(local, "a.txt", repo)
        let index = try git(["ls-files", "--stage"], repo)
        let review = try await prepare(source, "a.txt", repo)
        let conflictFile = try XCTUnwrap(review.reviewFiles.first)
        let marked = try XCTUnwrap(conflictFile.conflict?.markedResult)
        XCTAssertTrue(review.hasConflicts)
        await reject { try await self.service.applyCommitPatch(review) }
        await reject { _ = try await self.service.resolveCommitPatch(review, fileID: conflictFile.id, result: marked) }
        var document = try ConflictResolutionDocument.parse(marked)
        document.selectAllConflicts(.current)
        let resolved = try await service.resolveCommitPatch(review, fileID: conflictFile.id, result: document.resolvedText)
        XCTAssertFalse(resolved.hasConflicts)
        XCTAssertEqual(try read("a.txt", repo), local)
        XCTAssertEqual(try git(["ls-files", "--stage"], repo), index)
        try await service.applyCommitPatch(resolved)
        XCTAssertEqual(try read("a.txt", repo), local.replacingOccurrences(of: "line15\n", with: "selected15\n"))
        XCTAssertEqual(try git(["ls-files", "--stage"], repo), index)
        try await service.applyCheckedWorkingTreePatch(resolved.patch, reverse: true, in: repo)
        XCTAssertEqual(try read("a.txt", repo), local)
    }

    func testSkippingConflictAppliesOtherFilesWithoutTouchingSkippedFile() async throws {
        let repo = try repository()
        try write("old\n", "a.txt", repo); try write("old\n", "b.txt", repo)
        let base = try commit(repo)
        try write("new\n", "a.txt", repo); try write("new\n", "b.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        try write("local\n", "b.txt", repo)
        let files = await service.changedFiles(in: source, in: repo)
        let review = try await service.prepareCommitPatch(.init(commit: source, files: files, direction: .apply, lines: nil, scope: "Files"), in: repo)
        let conflict = try XCTUnwrap(review.reviewFiles.first { $0.file.path == "b.txt" })
        let skipped = try await MainActor.run {
            let controller = CommitPatchController()
            controller.prepared = review
            controller.skip(fileID: conflict.id)
            return try XCTUnwrap(controller.prepared)
        }
        XCTAssertEqual(try read("a.txt", repo), "old\n", "Skip must not apply other files yet")
        XCTAssertEqual(try read("b.txt", repo), "local\n", "Skip must not change the working copy")
        XCTAssertFalse(skipped.hasConflicts)
        XCTAssertFalse(try XCTUnwrap(skipped.reviewFiles.first { $0.id == conflict.id }).patch.isEmpty,
            "Skipped changes remain previewable")
        try await service.applyCommitPatch(skipped)
        XCTAssertEqual(try read("a.txt", repo), "new\n")
        XCTAssertEqual(try read("b.txt", repo), "local\n")
    }

    func testChangedWorkingCopyRejectsResolutionAndFinalMergedApply() async throws {
        let repo = try repository()
        try write("old\n", "a.txt", repo)
        let base = try commit(repo)
        try write("new\n", "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        try write("local\n", "a.txt", repo)
        let review = try await prepare(source, "a.txt", repo)
        let file = try XCTUnwrap(review.reviewFiles.first)
        let resolved = try await service.resolveCommitPatch(review, fileID: file.id, result: "resolved\n")
        try write("newer edit\n", "a.txt", repo)
        await reject { _ = try await self.service.resolveCommitPatch(review, fileID: file.id, result: "resolved\n") }
        await reject { try await self.service.applyCommitPatch(resolved) }
        XCTAssertEqual(try read("a.txt", repo), "newer edit\n")
    }

    func testAlreadyPresentPartialChangeWithDifferentContextIsRecognizedByMerge() async throws {
        let repo = try repository()
        let original = (1...20).map { "line\($0)" }.joined(separator: "\n") + "\n"
        try write(original, "a.txt", repo); _ = try commit(repo)
        let selected = original.replacingOccurrences(of: "line5\n", with: "selected5\n")
        try write(selected, "a.txt", repo)
        let source = try commit(repo)
        let local = selected.replacingOccurrences(of: "line2\n", with: "local2\n")
        try write(local, "a.txt", repo)
        let review = try await prepare(source, "a.txt", repo, lines: [.init(old: 5, new: nil), .init(old: nil, new: 5)])
        XCTAssertEqual(review.reviewFiles.first?.state, .alreadyApplied)
        XCTAssertFalse(review.hasChanges)
        XCTAssertEqual(try read("a.txt", repo), local)
    }

    func testCRLFConflictUsesExistingResolutionDocumentWithoutLosingLines() async throws {
        let repo = try repository()
        try git(["config", "core.autocrlf", "false"], repo)
        try write("before\r\nold\r\nafter\r\n", "a.txt", repo)
        let base = try commit(repo)
        try write("before\r\nnew\r\nafter\r\n", "a.txt", repo)
        let source = try commit(repo)
        try git(["checkout", "--detach", base], repo)
        try write("before\r\nlocal\r\nafter\r\n", "a.txt", repo)
        let review = try await prepare(source, "a.txt", repo)
        let file = try XCTUnwrap(review.reviewFiles.first)
        var document = try ConflictResolutionDocument.parse(try XCTUnwrap(file.conflict?.markedResult))
        document.selectAllConflicts(.incoming)
        let resolved = try await service.resolveCommitPatch(review, fileID: file.id, result: document.resolvedText)
        try await service.applyCommitPatch(resolved)
        XCTAssertEqual(try read("a.txt", repo), "before\r\nnew\r\nafter\r\n")
    }

    private func reject(_ action: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("Expected rejection", file: file, line: line) }
        catch { /* Rejection must leave the working copy intact; each caller asserts its state. */ }
    }

    private func repository() throws -> URL {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("commit-patch-tests-\(UUID())")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        repositories.append(repo)
        try git(["init", "-b", "main"], repo)
        try git(["config", "user.name", "Tests"], repo)
        try git(["config", "user.email", "tests@example.com"], repo)
        try git(["config", "commit.gpgsign", "false"], repo)
        return repo
    }

    private func write(_ text: String, _ path: String, _ repo: URL) throws {
        try Data(text.utf8).write(to: repo.appendingPathComponent(path))
    }

    private func read(_ path: String, _ repo: URL) throws -> String {
        try String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)
    }

    private func commit(_ repo: URL) throws -> String {
        try git(["add", "-A"], repo)
        try git(["commit", "--allow-empty", "-m", "fixture"], repo)
        return try git(["rev-parse", "HEAD"], repo)
    }

    @discardableResult private func git(_ arguments: [String], _ repo: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repo
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw NSError(domain: "GitTest", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output]) }
        return output
    }
}
