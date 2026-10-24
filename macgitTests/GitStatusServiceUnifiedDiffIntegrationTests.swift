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

final class GitStatusServiceUnifiedDiffIntegrationTests: XCTestCase {
    func testModifiedFileProducesHunkWithRepositoryPath() async throws {
        let diff = try await GitStatusService.shared.unifiedDiff(
            original: Data("one\ntwo\nthree\n".utf8),
            modified: Data("one\n2\nthree\n".utf8),
            path: "Sources/App.swift"
        )

        XCTAssertTrue(diff.contains("diff --git a/Sources/App.swift b/Sources/App.swift"))
        XCTAssertTrue(diff.contains("--- a/Sources/App.swift"))
        XCTAssertTrue(diff.contains("+++ b/Sources/App.swift"))
        let hunks = await MainActor.run { DiffParser.parse(diff) }
        XCTAssertEqual(hunks.count, 1)
        let lines = hunks.flatMap(\.lines)
        XCTAssertEqual(lines.filter { $0.type == .removed }.map(\.text), ["two"])
        XCTAssertEqual(lines.filter { $0.type == .added }.map(\.text), ["2"])
    }

    func testAddedFileDiffsAgainstEmptyContent() async throws {
        let diff = try await GitStatusService.shared.unifiedDiff(
            original: Data(),
            modified: Data("first\nsecond\n".utf8),
            path: "new.txt"
        )

        XCTAssertTrue(diff.contains("+first"))
        XCTAssertTrue(diff.contains("+second"))
        XCTAssertTrue(diff.contains("+++ b/new.txt"))
        let hunks = await MainActor.run { DiffParser.parse(diff) }
        XCTAssertEqual(hunks.count, 1)
    }

    func testIdenticalContentProducesEmptyDiff() async throws {
        let content = Data("same\n".utf8)

        let diff = try await GitStatusService.shared.unifiedDiff(original: content, modified: content, path: "same.txt")

        XCTAssertEqual(diff, "")
    }
}
