// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class DiffGenerationalCacheTests: XCTestCase {
    func testBoundedAndPromotesRecentlyRead() {
        var cache = DiffGenerationalCache<Int, Int>(capacity: 4)
        for value in 0..<4 {
            cache.insert(value, for: value)
        }
        XCTAssertEqual(cache.value(for: 0), 0)
        for value in 4..<6 {
            cache.insert(value, for: value)
        }
        XCTAssertLessThanOrEqual(cache.count, 4)
        XCTAssertEqual(cache.value(for: 0), 0)
    }
}
