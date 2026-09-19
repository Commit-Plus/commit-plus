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

final class SubmoduleTreeTests: XCTestCase {
    func testNestedSubmodulePathsGroupIntoFolders() {
        let nodes = SidebarTreeBuilder.buildTree(from: [
            "app/package",
            "app/other",
            "libs/shared",
            "single"
        ])

        XCTAssertEqual(nodes.map(\.name), ["app", "libs", "single"])
        XCTAssertTrue(nodes[0].isFolder)
        XCTAssertTrue(nodes[1].isFolder)
        XCTAssertFalse(nodes[2].isFolder)
        XCTAssertEqual(nodes[0].children.map(\.name), ["other", "package"])
    }

    func testVisibleRowsExpandSelectedFolder() {
        let nodes = SidebarTreeBuilder.buildTree(from: [
            "app/package",
            "app/other",
            "libs/shared",
            "single"
        ])
        let rows = SidebarTreeBuilder.visibleRows(from: nodes, expandedFolders: ["app"])

        XCTAssertEqual(
            rows.map(\.fullPath),
            ["app", "app/other", "app/package", "libs", "single"]
        )
        XCTAssertEqual(rows.map(\.indent), [0, 1, 1, 0, 0])
    }

    func testRevealingPathsExpandParentsOfSelectedSubmodule() {
        XCTAssertEqual(
            SidebarTreeBuilder.expandedFolderPaths(revealing: "app/package"),
            ["app"]
        )
        XCTAssertEqual(
            SidebarTreeBuilder.expandedFolderPaths(revealing: "single"),
            []
        )
    }
}
