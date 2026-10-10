// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class DiffTextMetricsTests: XCTestCase {
    func testASCIIColumnsExpandTabsToFourColumnStops() {
        XCTAssertEqual(DiffTextMetrics.asciiColumns("abc"), 3)
        XCTAssertEqual(DiffTextMetrics.asciiColumns("\tx"), 5)
        XCTAssertEqual(DiffTextMetrics.asciiColumns("ab\tx"), 5)
        XCTAssertEqual(DiffTextMetrics.asciiColumns("abcd\tx"), 9)
    }

    func testTrailingCarriageReturnIsIgnored() {
        XCTAssertEqual(DiffTextMetrics.asciiColumns("abc\r"), 3)
    }

    func testNonASCIIReturnsNil() {
        XCTAssertNil(DiffTextMetrics.asciiColumns("café"))
        XCTAssertNil(DiffTextMetrics.asciiColumns("中文"))
        XCTAssertNil(DiffTextMetrics.asciiColumns("a\u{0007}b"))
    }

    func testExpandTabsMatchesColumns() {
        let text = "a\tbc\t\td\r"
        XCTAssertEqual(
            DiffTextMetrics.expandTabs(text).count,
            DiffTextMetrics.asciiColumns(text)
        )
    }
}
