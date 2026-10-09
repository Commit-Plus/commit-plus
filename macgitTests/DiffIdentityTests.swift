// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class DiffIdentityTests: XCTestCase {
    private let patch = """
    @@ -1,3 +1,3 @@
     a
    -b
    +c
    @@ -10,2 +10,3 @@
     x
    +y
    """

    func testReparsingSameDiffYieldsSameHunkIDs() {
        XCTAssertEqual(DiffParser.parse(patch).map(\.id), DiffParser.parse(patch).map(\.id))
    }

    func testEditedSameCountHunkChangesRevisionButNotParsedIdentity() {
        let first = DiffParser.parse(patch)
        let second = DiffParser.parse(patch.replacing("+c", with: "+changed"))
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertNotEqual(first[0].contentRevision, second[0].contentRevision)
    }

    func testHeaderCounts() {
        let hunk = DiffParser.parse(patch)[0]
        XCTAssertEqual(hunk.addedCount, 1)
        XCTAssertEqual(hunk.removedCount, 1)
    }

    func testFingerprintEqualityChecksExactTextAfterHashCollision() {
        let first = DiffTextFingerprint(text: "first", precomputedHash: 7)
        let second = DiffTextFingerprint(text: "second", precomputedHash: 7)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual([first: 1, second: 2].count, 2)
    }
}
