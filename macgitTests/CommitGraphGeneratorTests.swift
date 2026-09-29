//
//  CommitGraphGeneratorTests.swift
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

@MainActor
final class CommitGraphGeneratorTests: XCTestCase {
    private func makeCommit(
        hash: String,
        parents: [String] = [],
        refs: [String] = []
    ) -> Commit {
        Commit(
            hash: hash,
            parents: parents,
            message: "",
            author: "",
            email: "",
            date: Date(),
            refs: refs
        )
    }

    private func assertModelsEqual(
        _ actual: CommitGraphModel,
        _ expected: CommitGraphModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.paths.count, expected.paths.count, file: file, line: line)
        for (actualPath, expectedPath) in zip(actual.paths, expected.paths) {
            XCTAssertEqual(actualPath.points, expectedPath.points, file: file, line: line)
            XCTAssertEqual(actualPath.colorIndex, expectedPath.colorIndex, file: file, line: line)
            XCTAssertEqual(actualPath.isHighlighted, expectedPath.isHighlighted, file: file, line: line)
        }

        XCTAssertEqual(actual.links.count, expected.links.count, file: file, line: line)
        for (actualLink, expectedLink) in zip(actual.links, expected.links) {
            XCTAssertEqual(actualLink.start, expectedLink.start, file: file, line: line)
            XCTAssertEqual(actualLink.control, expectedLink.control, file: file, line: line)
            XCTAssertEqual(actualLink.end, expectedLink.end, file: file, line: line)
            XCTAssertEqual(actualLink.colorIndex, expectedLink.colorIndex, file: file, line: line)
            XCTAssertEqual(actualLink.isHighlighted, expectedLink.isHighlighted, file: file, line: line)
        }

        XCTAssertEqual(actual.dots.count, expected.dots.count, file: file, line: line)
        for (actualDot, expectedDot) in zip(actual.dots, expected.dots) {
            XCTAssertEqual(actualDot.center, expectedDot.center, file: file, line: line)
            XCTAssertEqual(actualDot.lane, expectedDot.lane, file: file, line: line)
            XCTAssertEqual(actualDot.type, expectedDot.type, file: file, line: line)
            XCTAssertEqual(actualDot.colorIndex, expectedDot.colorIndex, file: file, line: line)
            XCTAssertEqual(actualDot.isHighlighted, expectedDot.isHighlighted, file: file, line: line)
        }

        XCTAssertEqual(actual.rowSlices, expected.rowSlices, file: file, line: line)
        XCTAssertEqual(actual.laneCount, expected.laneCount, file: file, line: line)
        XCTAssertEqual(actual.rowIndexByHash, expected.rowIndexByHash, file: file, line: line)
        XCTAssertEqual(actual.commitMetadata.count, expected.commitMetadata.count, file: file, line: line)
        for (hash, expectedMetadata) in expected.commitMetadata {
            let actualMetadata = actual.commitMetadata[hash]
            XCTAssertEqual(actualMetadata?.colorIndex, expectedMetadata.colorIndex, file: file, line: line)
            XCTAssertEqual(actualMetadata?.isHighlighted, expectedMetadata.isHighlighted, file: file, line: line)
            XCTAssertEqual(actualMetadata?.leftMargin, expectedMetadata.leftMargin, file: file, line: line)
        }
    }

    func testLinearHistory() {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"])
        let c = makeCommit(hash: "c", parents: ["b"])

        let model = CommitGraphGenerator.generate(
            commits: [c, b, a],
            highlighting: .all,
            headHash: "c",
            highlightRootHash: nil
        )

        XCTAssertEqual(model.dots.count, 3)
        XCTAssertEqual(model.paths.count, 1)
        XCTAssertEqual(model.links.count, 0)
        XCTAssertEqual(model.laneCount, 1)
        XCTAssertTrue(model.dots.allSatisfy(\.isHighlighted))
    }

    func testFeatureBranchAndMerge() {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"])
        let c = makeCommit(hash: "c", parents: ["b"], refs: ["main"])
        let f = makeCommit(hash: "f", parents: ["b"])
        let m = makeCommit(hash: "m", parents: ["c", "f"])

        let model = CommitGraphGenerator.generate(
            commits: [m, f, c, b, a],
            highlighting: .all,
            headHash: "m",
            highlightRootHash: nil
        )

        XCTAssertEqual(model.dots.count, 5)
        XCTAssertEqual(model.links.count, 1)
        XCTAssertGreaterThanOrEqual(model.laneCount, 2)
    }

    func testOctopusMerge() {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"])
        let c = makeCommit(hash: "c", parents: ["a"])
        let d = makeCommit(hash: "d", parents: ["a"])
        let m = makeCommit(hash: "m", parents: ["b", "c", "d"])

        let model = CommitGraphGenerator.generate(
            commits: [m, b, c, d, a],
            highlighting: .all,
            headHash: "m",
            highlightRootHash: nil
        )

        XCTAssertEqual(model.links.count, 2)
        XCTAssertGreaterThanOrEqual(model.laneCount, 3)
    }

    func testCurrentBranchOnlyHighlighting() {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"])
        let c = makeCommit(hash: "c", parents: ["b"], refs: ["main"])
        let f = makeCommit(hash: "f", parents: ["b"])
        let m = makeCommit(hash: "m", parents: ["c", "f"])

        let model = CommitGraphGenerator.generate(
            commits: [m, f, c, b, a],
            highlighting: .currentBranchOnly,
            headHash: "c",
            highlightRootHash: "c"
        )

        let highlightedDots = model.dots.filter(\.isHighlighted)
        XCTAssertEqual(highlightedDots.count, 3)
        XCTAssertEqual(
            model.commitMetadata.filter(\.value.isHighlighted).map(\.key).sorted(),
            ["a", "b", "c"]
        )
    }

    func testMissingParentDrawsContinuationPath() {
        let a = makeCommit(hash: "a", parents: ["missing"])
        let model = CommitGraphGenerator.generate(
            commits: [a],
            highlighting: .all,
            headHash: "a",
            highlightRootHash: nil
        )

        XCTAssertEqual(model.dots.count, 1)
        XCTAssertEqual(model.paths.count, 1)
        let lastPoint = model.paths.first?.points.last
        XCTAssertEqual(lastPoint?.y, 0.5)
    }

    func testRemoteBranchHeadCreatesNewPath() {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"], refs: ["origin/main"])
        let c = makeCommit(hash: "c", parents: ["a"], refs: ["main"])

        let model = CommitGraphGenerator.generate(
            commits: [c, b, a],
            highlighting: .all,
            headHash: "c",
            highlightRootHash: nil
        )

        XCTAssertGreaterThanOrEqual(model.laneCount, 2)
    }

    func testHeadAndMergeDotTypes() {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"])
        let c = makeCommit(hash: "c", parents: ["a"])
        let m = makeCommit(hash: "m", parents: ["b", "c"], refs: ["HEAD -> main"])

        let model = CommitGraphGenerator.generate(
            commits: [m, b, c, a],
            highlighting: .all,
            headHash: "m",
            highlightRootHash: nil
        )

        XCTAssertEqual(model.dots.first?.type, .head)
        XCTAssertEqual(model.dots[1].type, .default)
    }

    func testEmptyHistoryReturnsOneLane() {
        let model = CommitGraphGenerator.generate(
            commits: [],
            highlighting: .all,
            headHash: nil,
            highlightRootHash: nil
        )

        XCTAssertTrue(model.paths.isEmpty)
        XCTAssertTrue(model.links.isEmpty)
        XCTAssertTrue(model.dots.isEmpty)
        XCTAssertEqual(model.laneCount, 1)
    }

    func testSelectedBranchHighlightUsesSeparateRootFromHead() {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"])
        let c = makeCommit(hash: "c", parents: ["b"], refs: ["main"])
        let f = makeCommit(hash: "f", parents: ["b"], refs: ["feature"])

        let model = CommitGraphGenerator.generate(
            commits: [c, f, b, a],
            highlighting: .currentBranchOnly,
            headHash: "c",
            highlightRootHash: "f"
        )

        XCTAssertEqual(model.dots.first?.type, .head)
        XCTAssertEqual(
            model.commitMetadata.filter(\.value.isHighlighted).map(\.key).sorted(),
            ["a", "b", "f"]
        )
        XCTAssertFalse(model.commitMetadata["c"]?.isHighlighted ?? true)
    }

    func testIncrementalLinearHistoryMatchesFullGeneration() throws {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"])
        let c = makeCommit(hash: "c", parents: ["b"])
        let d = makeCommit(hash: "d", parents: ["c"])
        let commits = [d, c, b, a]

        let initial = CommitGraphGenerator.generateIncremental(
            commits: Array(commits.prefix(2)),
            highlighting: .all,
            headHash: "d",
            highlightRootHash: nil
        )
        let incremental = try XCTUnwrap(
            CommitGraphGenerator.append(
                commits: Array(commits.dropFirst(2)),
                to: initial.state,
                allCommits: commits,
                highlighting: .all,
                headHash: "d",
                highlightRootHash: nil
            )
        )
        let full = CommitGraphGenerator.generate(
            commits: commits,
            highlighting: .all,
            headHash: "d",
            highlightRootHash: nil
        )

        assertModelsEqual(incremental.model, full)
    }

    func testIncrementalMergeHistoryMatchesFullGeneration() throws {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"])
        let c = makeCommit(hash: "c", parents: ["b"], refs: ["main"])
        let f = makeCommit(hash: "f", parents: ["b"], refs: ["feature"])
        let m = makeCommit(hash: "m", parents: ["c", "f"])
        let commits = [m, f, c, b, a]

        let initial = CommitGraphGenerator.generateIncremental(
            commits: Array(commits.prefix(2)),
            highlighting: .currentBranchOnly,
            headHash: "m",
            highlightRootHash: "c"
        )
        let incremental = try XCTUnwrap(
            CommitGraphGenerator.append(
                commits: Array(commits.dropFirst(2)),
                to: initial.state,
                allCommits: commits,
                highlighting: .currentBranchOnly,
                headHash: "m",
                highlightRootHash: "c"
            )
        )
        let full = CommitGraphGenerator.generate(
            commits: commits,
            highlighting: .currentBranchOnly,
            headHash: "m",
            highlightRootHash: "c"
        )

        assertModelsEqual(incremental.model, full)
    }

    func testIncrementalAppendRejectsNonSuffixChanges() {
        let a = makeCommit(hash: "a")
        let b = makeCommit(hash: "b", parents: ["a"])
        let c = makeCommit(hash: "c", parents: ["b"])
        let initial = CommitGraphGenerator.generateIncremental(
            commits: [c, b],
            highlighting: .all,
            headHash: "c",
            highlightRootHash: nil
        )

        XCTAssertNil(
            CommitGraphGenerator.append(
                commits: [a],
                to: initial.state,
                allCommits: [c, a, b],
                highlighting: .all,
                headHash: "c",
                highlightRootHash: nil
            )
        )
    }
}
