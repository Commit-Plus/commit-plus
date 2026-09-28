// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class BoundedMemoryCacheTests: XCTestCase {
    func testRecentlyReadValueSurvivesEviction() {
        var cache = BoundedMemoryCache<String, Int>(capacity: 2)
        cache.insert(1, for: "one")
        cache.insert(2, for: "two")

        XCTAssertEqual(cache.value(for: "one"), 1)
        let evicted = cache.insert(3, for: "three")

        XCTAssertEqual(evicted?.key, "two")
        XCTAssertNil(cache.value(for: "two"))
        XCTAssertEqual(cache.value(for: "one"), 1)
        XCTAssertEqual(cache.value(for: "three"), 3)
        XCTAssertEqual(cache.count, 2)
    }
}
