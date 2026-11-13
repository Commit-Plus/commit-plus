// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class FileHistoryParsingTests: XCTestCase {
    func testFileHistoryFollowsRenames() {
        let a = String(repeating: "a", count: 40), b = String(repeating: "b", count: 40)
        let raw = "\u{1}\(a)\u{1f}\(b)\u{1f}Edit\u{1f}Ann\u{1f}ann@example.com\u{1f}2026-11-11T16:25:29+07:00\u{1f}HEAD -> main, tag: v1\u{2}\u{0}\nM\u{0}new/name.swift\u{0}"
            + "\u{1}\(b)\u{1f}\u{1f}Move\u{1f}Bob\u{1f}bob@example.com\u{1f}2026-10-16T10:00:00+07:00\u{1f}\u{2}\u{0}\nR090\u{0}old/name.swift\u{0}new/name.swift\u{0}"
        let entries = GitStatusService.parseFileHistory(Data(raw.utf8), path: "new/name.swift")
        XCTAssertEqual(entries.map(\.commit.hash), [a, b])
        XCTAssertEqual(entries[0].commit.parents, [b])
        XCTAssertEqual(entries[0].commit.refs, ["HEAD -> main", "tag: v1"])
        XCTAssertEqual(entries[0].status, .modified)
        XCTAssertEqual(entries[0].path, "new/name.swift")
        XCTAssertEqual(entries[1].status, .renamed)
        XCTAssertEqual(entries[1].oldPath, "old/name.swift")
        XCTAssertEqual(entries[1].path, "new/name.swift")
        XCTAssertTrue(entries[1].commit.parents.isEmpty)
    }

    func testBlamePorcelainReusesCommitMetadata() throws {
        let a = String(repeating: "a", count: 40), b = String(repeating: "b", count: 40)
        let raw = """
        \(a) 1 1 1
        author Ann
        author-mail <ann@example.com>
        author-time 1700000000
        summary First
        filename file.txt
        \tline one
        \(b) 2 2 1
        author Bob
        author-mail <bob@example.com>
        author-time 1700000100
        summary Second
        filename file.txt
        \t\tindented
        \(a) 3 3 1
        \tline three
        """
        let blame = try GitStatusService.parseFileBlame(Data(raw.utf8))
        XCTAssertEqual(blame.lines.map(\.hash), [a, b, a])
        XCTAssertEqual(blame.lines.map(\.text), ["line one", "\tindented", "line three"])
        XCTAssertEqual(blame.lines.map(\.lineNumber), [1, 2, 3])
        XCTAssertEqual(blame.commits[a]?.author, "Ann")
        XCTAssertEqual(blame.commits[b]?.email, "bob@example.com")
        XCTAssertEqual(blame.commits[b]?.summary, "Second")
    }

    func testRenameEntryDiffPairsOldAndNewPaths() async throws {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("file-history-\(UUID())")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("old"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: repo) }
        for arguments in [["init", "-b", "main"], ["config", "user.name", "Tests"],
                          ["config", "user.email", "tests@example.com"], ["config", "commit.gpgsign", "false"]] {
            try git(arguments, in: repo)
        }
        let lines = (1...20).map { "line \($0)" }
        try lines.joined(separator: "\n").write(to: repo.appendingPathComponent("old/a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "add"], in: repo)
        try git(["mv", "old", "new"], in: repo)
        var edited = lines
        edited[9] = "line ten"
        try edited.joined(separator: "\n").write(to: repo.appendingPathComponent("new/a.txt"), atomically: true, encoding: .utf8)
        try git(["commit", "-am", "move"], in: repo)

        let entries = try await GitStatusService.shared.fileHistory(path: "new/a.txt", revision: "HEAD", in: repo)
        let rename = try XCTUnwrap(entries.first)
        XCTAssertEqual(rename.oldPath, "old/a.txt")
        let hunks = try await GitStatusService.shared.commitDiff(for: rename.path, oldPath: rename.oldPath,
            in: rename.commit.hash, in: repo)
        let changed = hunks.flatMap(\.lines).filter { $0.type == .added || $0.type == .removed }
        XCTAssertEqual(changed.map(\.text).sorted(), ["line 10", "line ten"])
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
        return output
    }
}
