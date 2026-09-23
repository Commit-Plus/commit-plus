// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class CodeRenderWindowTests: XCTestCase {
    func testLargeEditorPolicyCoversFewLongLinesAndManyMediumLines() {
        XCTAssertTrue(CodeRenderWindow.usesWindowedHighlighting(lineCount: 1, longestLineLength: 1_000_000, documentLength: 1_000_000))
        XCTAssertTrue(CodeRenderWindow.usesWindowedHighlighting(lineCount: 10_000, longestLineLength: 10, documentLength: 100_000))
        XCTAssertTrue(CodeRenderWindow.usesWindowedHighlighting(lineCount: 100, longestLineLength: 4_000, documentLength: 400_000))
        XCTAssertFalse(CodeRenderWindow.usesWindowedHighlighting(lineCount: 10, longestLineLength: 100, documentLength: 1_000))
    }

    func testVisibleRowsStayBoundedAcrossLargeDocuments() {
        for count in [0, 1, 10_000, 1_000_000] {
            for y in [CGFloat(0), CGFloat(count) * 10, CGFloat(count) * 20] {
                let rows = CodeRenderWindow.rows(
                    count: count, viewport: CGRect(x: 100_000, y: y, width: 1_000, height: 400), rowHeight: 20
                )
                XCTAssertLessThanOrEqual(rows.count, 36)
                XCTAssertGreaterThanOrEqual(rows.lowerBound, 0)
                XCTAssertLessThanOrEqual(rows.upperBound, count)
            }
        }
    }

    func testNativeHighlightingSkipsMillionCharacterLineWithoutDroppingNeighbours() {
        let starts = [0, 10, 1_000_011, 1_000_020]
        let ranges = CodeRenderWindow.highlightRanges(lineStarts: starts, length: 1_000_025, rows: 0..<4)
        XCTAssertEqual(ranges, [
            NSRange(location: 0, length: 10),
            NSRange(location: 1_000_011, length: 9),
            NSRange(location: 1_000_020, length: 5),
        ])
        XCTAssertEqual(
            CodeRenderWindow.highlightRanges(lineStarts: [0], length: 1_000_000, rows: 0..<1),
            []
        )
    }

    func testHighlightingUsesUTF16OffsetsAndOnlyVisibleRows() {
        let source = "😀 first\nlet second = 2\n"
        let firstLength = ("😀 first\n" as NSString).length
        let length = (source as NSString).length
        let ranges = CodeRenderWindow.highlightRanges(
            lineStarts: [0, firstLength, length], length: length, rows: 1..<3
        )
        XCTAssertEqual(ranges, [NSRange(location: firstLength, length: length - firstLength)])
        XCTAssertEqual((source as NSString).substring(with: ranges[0]), "let second = 2\n")
    }
}
