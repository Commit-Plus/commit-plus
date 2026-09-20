// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class DiffRenderBatchTests: XCTestCase {
    func testRenderWindowKeepsFourNeighboursInBothDirections() {
        let hunk = DiffHunk(header: "@@ -0,0 +1,20000 @@", lines: (1...20_000).map {
            DiffLine(oldLineNumber: nil, newLineNumber: $0, text: "line \($0)", type: .added)
        })
        let blocks = DiffRenderBlock.layout(hunks: [hunk])
        func window(at index: Int) -> Range<Int> {
            DiffRenderBlock.renderedRange(
                in: blocks,
                viewport: CGRect(x: 0, y: blocks[index].offset, width: 800, height: 400)
            )
        }
        XCTAssertEqual(blocks.count, 200)
        XCTAssertEqual(window(at: 0), 0..<5)
        XCTAssertEqual(window(at: 100), 96..<105)
        XCTAssertEqual(window(at: 50), 46..<55)
        XCTAssertEqual(window(at: 199), 195..<200)
        for index in 1..<blocks.count {
            XCTAssertEqual(blocks[index - 1].endOffset, blocks[index].offset)
        }
        XCTAssertEqual(
            DiffRenderBlock.renderedRange(in: [], viewport: .zero), 0..<0
        )
    }

    func testLargeDiffsHaveBoundedBatchesWithoutMissingOrDuplicatedLines() {
        for count in [0, 1, 99, 100, 101, 10_000, 20_003] {
            let ranges = DiffRenderBatch.ranges(lineCount: count)
            XCTAssertTrue(ranges.allSatisfy { !$0.isEmpty && $0.count <= 100 })
            XCTAssertEqual(ranges.flatMap { Array($0) }, Array(0..<count))
        }
    }

    func testLargeParsedHunkRetainsLineIdentityAndNumbersAcrossBatches() throws {
        let count = 10_000
        let raw = "@@ -0,0 +1,\(count) @@\n"
            + (1...count).map { "+line \($0)" }.joined(separator: "\n")
        let hunk = try XCTUnwrap(DiffParser.parse(raw).first)
        let renderedLines = DiffRenderBatch.ranges(lineCount: hunk.lines.count)
            .flatMap { Array(hunk.lines[$0]) }

        XCTAssertEqual(renderedLines.map(\.id), hunk.lines.map(\.id))
        XCTAssertEqual(renderedLines.compactMap(\.newLineNumber), Array(1...count))
        XCTAssertEqual(renderedLines.last?.text, "line 10000")
    }

    func testWholeHunkPatchStillIncludesLinesOutsideFirstDisplayBatch() throws {
        let count = 10_000
        let hunk = DiffHunk(
            header: "@@ -0,0 +1,\(count) @@",
            lines: (1...count).map {
                DiffLine(oldLineNumber: nil, newLineNumber: $0, text: "line \($0)", type: .added)
            }
        )
        XCTAssertEqual(DiffRenderBatch.ranges(lineCount: count).first?.count, 100)
        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: "large.txt")
        let parsed = try XCTUnwrap(DiffParser.parse(patch).first)
        let added = parsed.lines.filter { $0.type == .added }
        XCTAssertEqual(added.count, count)
        XCTAssertEqual(added.last?.text, "line 10000")
    }
}
