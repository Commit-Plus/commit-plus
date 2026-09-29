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
final class HistoryPaginationTests: XCTestCase {
    func testCommitHistoryPageSkipsOlderCommits() async throws {
        let repoURL = try makeRepoWithLinearHistory(commitCount: 6)

        let firstPage = await GitStatusService.shared.commitHistory(
            branch: "main",
            limit: 3,
            skip: 0,
            in: repoURL
        )
        let secondPage = await GitStatusService.shared.commitHistory(
            branch: "main",
            limit: 3,
            skip: 3,
            in: repoURL
        )

        XCTAssertEqual(firstPage.map(\.message), ["commit 6", "commit 5", "commit 4"])
        XCTAssertEqual(secondPage.map(\.message), ["commit 3", "commit 2", "commit 1"])
    }

    func testBranchHistoryPageReturnsBranchTipFirst() async throws {
        let repoURL = try makeRepoWithOlderFeatureBranchTip()

        let featurePage = await GitStatusService.shared.commitHistory(
            branch: "feature",
            limit: 2,
            skip: 0,
            in: repoURL
        )

        XCTAssertEqual(featurePage.first?.message, "feature tip")
    }

    func testHistoryPagingStateTracksLoadedPages() {
        var state = HistoryPagingState(pageSize: 100)
        XCTAssertTrue(state.beginLoadingMore())
        state.finishLoadingMore(loaded: 100)

        XCTAssertEqual(state.loadedCount, 100)
        XCTAssertEqual(state.startIndex, 0)
        XCTAssertTrue(state.hasMore)
        XCTAssertFalse(state.isLoadingMore)

        XCTAssertTrue(state.beginLoadingMore())
        state.cancelLoadingMore()

        XCTAssertFalse(state.isLoadingMore)

        state.replaceLoadedHistory(count: 175, hasMore: true)
        XCTAssertEqual(state.loadedCount, 175)
        XCTAssertEqual(state.startIndex, 0)
        XCTAssertTrue(state.hasMore)
        XCTAssertFalse(state.isLoadingMore)

        state.reset()
        XCTAssertEqual(state.loadedCount, 0)
        XCTAssertEqual(state.startIndex, 0)
        XCTAssertTrue(state.hasMore)
        XCTAssertFalse(state.isLoadingMore)
    }

    func testHistoryPagingStateTracksBoundedWindowInBothDirections() {
        var state = HistoryPagingState(pageSize: 100)
        state.replaceWindow(startIndex: 0, count: 300, hasMore: true)

        XCTAssertEqual(state.maximumLoadedCount, 300)
        XCTAssertEqual(state.olderPageStartIndex, 300)
        XCTAssertFalse(state.canLoadNewer)

        XCTAssertTrue(state.beginLoadingMore())
        state.finishLoadingMore(loaded: 100)

        XCTAssertTrue(state.needsTrimming)
        XCTAssertFalse(state.beginLoadingMore())

        state.discardNewerCommits(count: 100)

        XCTAssertEqual(state.startIndex, 100)
        XCTAssertEqual(state.loadedCount, 300)
        XCTAssertEqual(state.olderPageStartIndex, 400)
        XCTAssertTrue(state.canLoadNewer)

        XCTAssertTrue(state.beginLoadingNewer())
        state.replaceWindow(startIndex: 0, count: 300, hasMore: true)

        XCTAssertEqual(state.startIndex, 0)
        XCTAssertEqual(state.loadedCount, 300)
        XCTAssertFalse(state.canLoadNewer)
        XCTAssertFalse(state.isLoadingMore)
    }

    func testHistoryPagingStateTrimsOlderOverflow() {
        var state = HistoryPagingState(pageSize: 100)
        state.replaceWindow(startIndex: 100, count: 400, hasMore: false)

        XCTAssertTrue(state.needsTrimming)
        XCTAssertFalse(state.beginLoadingNewer())

        state.discardOlderCommits(count: 100)

        XCTAssertEqual(state.startIndex, 100)
        XCTAssertEqual(state.loadedCount, 300)
        XCTAssertTrue(state.hasMore)
        XCTAssertFalse(state.needsTrimming)
    }

    func testCommitHistoryUsesTopoOrder() async throws {
        let url = try makeRepoWithMergeTopology()

        let allCommits = await GitStatusService.shared.commitHistory(allBranches: true, limit: 100, in: url)
        let allMessages = allCommits.map { $0.message }

        let featureIndex = try XCTUnwrap(allMessages.firstIndex(of: "feature work"))
        let mainAfterMergeIndex = try XCTUnwrap(allMessages.firstIndex(of: "main after merge"))

        XCTAssertGreaterThan(featureIndex, mainAfterMergeIndex)

        let branchCommits = await GitStatusService.shared.commitHistory(branch: "main", limit: 100, in: url)
        let branchMessages = branchCommits.map { $0.message }

        let branchFeatureIndex = try XCTUnwrap(branchMessages.firstIndex(of: "feature work"))
        let branchMainAfterMergeIndex = try XCTUnwrap(branchMessages.firstIndex(of: "main after merge"))

        XCTAssertGreaterThan(branchFeatureIndex, branchMainAfterMergeIndex)
    }

    func testSearchCommitHistoryMatchesAuthorEmailOnCurrentBranch() async throws {
        let repoURL = try makeRepoWithAuthorHistory()

        let matches = await GitStatusService.shared.searchCommitHistory(
            allBranches: false,
            query: "bob@example.com",
            limit: 20,
            in: repoURL
        )

        XCTAssertEqual(matches.map(\.message), ["bob main"])
    }

    func testSearchCommitHistoryMatchesHashPrefix() async throws {
        let repoURL = try makeRepoWithAuthorHistory()
        let commits = await GitStatusService.shared.commitHistory(
            allBranches: false,
            limit: 20,
            in: repoURL
        )
        let bobCommit = try XCTUnwrap(commits.first(where: { $0.message == "bob main" }))

        let matches = await GitStatusService.shared.searchCommitHistory(
            allBranches: false,
            query: String(bobCommit.hash.prefix(7)),
            limit: 20,
            in: repoURL
        )

        XCTAssertEqual(matches.first?.hash, bobCommit.hash)
    }

    func testGraphLayoutStableAcrossPagination() async throws {
        let url = try makeRepoWithFeatureBranch()
        let headHash = await GitStatusService.shared.tipHash(for: "HEAD", in: url)

        let page1 = await GitStatusService.shared.commitHistory(allBranches: true, limit: 3, skip: 0, in: url)
        XCTAssertEqual(page1.count, 3)
        let model1 = CommitGraphGenerator.generate(
            commits: page1,
            highlighting: .all,
            headHash: headHash,
            highlightRootHash: nil
        )

        let page2 = await GitStatusService.shared.commitHistory(allBranches: true, limit: 3, skip: 3, in: url)
        let combined = page1 + page2
        let model2 = CommitGraphGenerator.generate(
            commits: combined,
            highlighting: .all,
            headHash: headHash,
            highlightRootHash: nil
        )

        XCTAssertEqual(model1.dots.count, 3)
        XCTAssertEqual(model2.dots.count, 6)
        XCTAssertEqual(
            model2.rowIndexByHash,
            Dictionary(uniqueKeysWithValues: combined.enumerated().map { ($0.element.hash, $0.offset) })
        )

        for index in model1.dots.indices {
            XCTAssertEqual(model1.dots[index].lane, model2.dots[index].lane)
            XCTAssertEqual(model1.dots[index].center.x, model2.dots[index].center.x)
        }
    }

    // MARK: - Helpers

    private func makeRepoWithLinearHistory(commitCount: Int) throws -> URL {
        let repoURL = try makeTempRepo(named: "macgit-history-linear")
        try runGit(["init", "-b", "main"], in: repoURL)
        try configureGit(in: repoURL)

        let fileURL = repoURL.appendingPathComponent("tracked.txt")
        try "seed\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "commit 0"], in: repoURL)

        for index in 1...commitCount {
            try "commit \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            try runGit(["add", "tracked.txt"], in: repoURL)
            try runGit(["commit", "-m", "commit \(index)"], in: repoURL)
        }

        return repoURL
    }

    private func makeRepoWithOlderFeatureBranchTip() throws -> URL {
        let repoURL = try makeTempRepo(named: "macgit-history-feature-tip")
        try runGit(["init", "-b", "main"], in: repoURL)
        try configureGit(in: repoURL)

        let fileURL = repoURL.appendingPathComponent("tracked.txt")
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "base"], in: repoURL)

        try runGit(["checkout", "-b", "feature"], in: repoURL)
        try "feature tip\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature tip"], in: repoURL)

        try runGit(["checkout", "main"], in: repoURL)
        for index in 1...3 {
            try "main \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            try runGit(["add", "tracked.txt"], in: repoURL)
            try runGit(["commit", "-m", "main \(index)"], in: repoURL)
        }

        return repoURL
    }

    private func makeRepoWithFeatureBranch() throws -> URL {
        let repoURL = try makeTempRepo(named: "macgit-pagination-graph")
        try runGit(["init", "-b", "main"], in: repoURL)
        try configureGit(in: repoURL)

        let fileURL = repoURL.appendingPathComponent("tracked.txt")

        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "base"], in: repoURL)

        try runGit(["checkout", "-b", "feature"], in: repoURL)
        for index in 1...2 {
            try "feature \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            try runGit(["add", "tracked.txt"], in: repoURL)
            try runGit(["commit", "-m", "feature \(index)"], in: repoURL)
        }

        try runGit(["checkout", "main"], in: repoURL)
        for index in 1...4 {
            try "main \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            try runGit(["add", "tracked.txt"], in: repoURL)
            try runGit(["commit", "-m", "main \(index)"], in: repoURL)
        }

        return repoURL
    }

    private func makeRepoWithMergeTopology() throws -> URL {
        let repoURL = try makeTempRepo(named: "macgit-topo-order")
        try runGit(["init", "-b", "main"], in: repoURL)
        try configureGit(in: repoURL)

        let fileURL = repoURL.appendingPathComponent("tracked.txt")

        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "main before merge"], in: repoURL)

        try runGit(["checkout", "-b", "feature"], in: repoURL)
        try "feature\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature work"], in: repoURL)

        try runGit(["checkout", "main"], in: repoURL)
        try runGit(["merge", "--no-ff", "feature", "-m", "merge feature"], in: repoURL)
        try "after\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "main after merge"], in: repoURL)

        return repoURL
    }

    private func makeRepoWithAuthorHistory() throws -> URL {
        let repoURL = try makeTempRepo(named: "macgit-history-search")
        try runGit(["init", "-b", "main"], in: repoURL)
        try configureGit(in: repoURL)

        let fileURL = repoURL.appendingPathComponent("tracked.txt")

        try "alice\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(
            ["-c", "user.name=Alice", "-c", "user.email=alice@example.com", "commit", "-m", "alice base"],
            in: repoURL
        )

        try "bob\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(
            ["-c", "user.name=Bob", "-c", "user.email=bob@example.com", "commit", "-m", "bob main"],
            in: repoURL
        )

        return repoURL
    }

    private func makeTempRepo(named prefix: String) throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        return repoURL
    }

    private func configureGit(in repositoryURL: URL) throws {
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
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
