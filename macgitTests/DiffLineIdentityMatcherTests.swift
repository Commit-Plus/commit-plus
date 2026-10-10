// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class DiffLineIdentityMatcherTests: XCTestCase {
    func testInsertionAbovePreservesUnambiguousLineIDs() {
        let id = UUID()
        let old = DiffHunk(id: id, header: "@@", lines: [line("one"), line("two"), line("three")])
        let fresh = DiffHunk(id: id, header: "@@", lines: [line("inserted"), line("one"), line("two"), line("three")])
        let restored = DiffLineIdentityMatcher.restoringIDs(from: old, in: fresh)
        XCTAssertEqual(Array(restored.lines.dropFirst().map(\.id)), old.lines.map(\.id))
    }

    func testAmbiguousDuplicateDoesNotRestoreWrongID() {
        let id = UUID()
        let old = DiffHunk(id: id, header: "@@", lines: [line("same"), line("same")])
        let fresh = DiffHunk(id: id, header: "@@", lines: [line("same")])
        let restored = DiffLineIdentityMatcher.restoringIDs(from: old, in: fresh)
        XCTAssertFalse(old.lines.map(\.id).contains(restored.lines[0].id))
    }

    func testIDNeverMovesToDifferentText() {
        let id = UUID()
        let old = DiffHunk(id: id, header: "@@", lines: [line("selected")])
        let fresh = DiffHunk(id: id, header: "@@", lines: [line("different")])
        let restored = DiffLineIdentityMatcher.restoringIDs(from: old, in: fresh)
        XCTAssertNotEqual(restored.lines[0].id, old.lines[0].id)
    }

    private func line(_ text: String) -> DiffLine {
        DiffLine(oldLineNumber: nil, newLineNumber: 1, text: text, type: .added)
    }
}
