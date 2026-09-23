// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import XCTest
@testable import macgit

final class DiffLongLineLayoutTests: XCTestCase {
    @MainActor
    func testMillionCharacterLineOnlyRendersViewportChunks() throws {
        let text = String(repeating: "const value = 123; ", count: 60_000)
        let fontName = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName
        let layout = try XCTUnwrap(DiffLongLineLayout.prepare(text: text, fontName: fontName))
        XCTAssertGreaterThan(layout.width, 1_000_000)
        XCTAssertEqual(layout.chunks.map { String(text[$0.range]) }.joined(), text)
        for x in [CGFloat(0), layout.width / 2, max(0, layout.width - 1_000)] {
            let viewport = CGRect(x: x, y: 0, width: 1_000, height: 22)
            let range = layout.visibleChunks(in: viewport)
            XCTAssertLessThan(range.count, 5)
            let first = try XCTUnwrap(range.first)
            let last = try XCTUnwrap(range.last)
            XCTAssertLessThanOrEqual(layout.chunks[first].offset, x)
            XCTAssertGreaterThanOrEqual(
                layout.chunks[last].offset + layout.chunks[last].width,
                min(layout.width, viewport.maxX)
            )
        }
    }

    @MainActor
    func testChunkBoundariesPreserveUnicodeAndWhitespace() throws {
        let text = String(repeating: "👨‍👩‍👧‍👦 tiếng Việt e\u{301} 漢字\t  ", count: 1_000)
        let fontName = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName
        let layout = try XCTUnwrap(DiffLongLineLayout.prepare(text: text, fontName: fontName))
        XCTAssertEqual(layout.chunks.map { String(text[$0.range]) }.joined(), text)
        XCTAssertTrue(layout.chunks.allSatisfy { text[$0.range].count <= DiffLongLineLayout.chunkSize })
        XCTAssertEqual(layout.chunks.first?.offset, 0)
        for index in 1..<layout.chunks.count {
            XCTAssertEqual(
                layout.chunks[index].offset,
                layout.chunks[index - 1].offset + layout.chunks[index - 1].width
            )
        }
    }

    func testLongLineThresholdDoesNotAffectNormalRows() {
        XCTAssertFalse(DiffLongLineLayout.isLong(String(repeating: "a", count: 4_096)))
        XCTAssertTrue(DiffLongLineLayout.isLong(String(repeating: "a", count: 4_097)))
    }
}
