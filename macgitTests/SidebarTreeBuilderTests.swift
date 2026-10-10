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

final class SidebarTreeBuilderTests: XCTestCase {
    func testBuildTreeGroupsSlashDelimitedRefs() {
        let nodes = SidebarTreeBuilder.buildTree(from: [
            "main",
            "feature/login",
            "feature/sidebar/remotes"
        ])

        XCTAssertEqual(nodes.map(\.name), ["feature", "main"])
        XCTAssertTrue(nodes[0].isFolder)
        XCTAssertEqual(nodes[0].children.map(\.name), ["sidebar", "login"])
        XCTAssertEqual(nodes[0].children[0].children.map(\.fullPath), ["feature/sidebar/remotes"])
    }

    func testRemoteTreeUsesRemoteAsTopLevelFolderAndNormalizesHead() {
        let nodes = SidebarTreeBuilder.buildRemoteTree(remoteBranchesByRemote: [
            "origin": ["HEAD -> origin/main", "main", "feature/api"],
            "upstream": ["develop"]
        ])

        XCTAssertEqual(nodes.map(\.name), ["origin", "upstream"])
        XCTAssertEqual(nodes[0].fullPath, "origin")
        XCTAssertTrue(nodes[0].isFolder)
        XCTAssertEqual(nodes[0].children.map(\.name), ["feature", "HEAD", "main"])
        XCTAssertEqual(nodes[0].children.first { $0.name == "HEAD" }?.fullPath, "origin/HEAD")
        XCTAssertEqual(nodes[0].children.first { $0.name == "main" }?.fullPath, "origin/main")
    }

    func testExpandedFolderPathsRevealCurrentBranchAncestorsOnly() {
        let paths = SidebarTreeBuilder.expandedFolderPaths(
            revealing: "feature/2026/v1/implement-storage"
        )

        XCTAssertEqual(paths, [
            "feature",
            "feature/2026",
            "feature/2026/v1"
        ])
    }

    func testVisibleRowsIncludeNestedCurrentBranchWhenAncestorFoldersAreExpanded() {
        let nodes = SidebarTreeBuilder.buildTree(from: [
            "master",
            "feature/2026/v1/implement-storage",
            "feature/2026/v2/update-search",
            "test/sidebar"
        ])
        let expandedFolders = SidebarTreeBuilder.expandedFolderPaths(
            revealing: "feature/2026/v1/implement-storage"
        )

        let rows = SidebarTreeBuilder.visibleRows(from: nodes, expandedFolders: expandedFolders)

        XCTAssertTrue(rows.contains { $0.fullPath == "feature/2026/v1/implement-storage" })
        XCTAssertFalse(rows.contains { $0.fullPath == "feature/2026/v2/update-search" })
        XCTAssertFalse(rows.contains { $0.fullPath == "test/sidebar" })
    }

    func testTreeIdentityIsStableAcrossEquivalentRebuilds() {
        let refs = ["main", "feature/sidebar", "feature/history"]

        let first = SidebarTreeBuilder.buildTree(from: refs)
        let second = SidebarTreeBuilder.buildTree(from: refs.reversed())

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.flatMap(\.children).map(\.id), second.flatMap(\.children).map(\.id))
    }

    func testFolderAndLeafWithSamePathHaveDistinctIdentity() {
        let nodes = SidebarTreeBuilder.buildTree(from: ["feature", "feature/sidebar"])
        let featureFolder = try? XCTUnwrap(nodes.first { $0.fullPath == "feature" && $0.isFolder })
        let featureLeaf = featureFolder?.children.first { $0.fullPath == "feature" && !$0.isFolder }

        XCTAssertNotNil(featureLeaf)
        XCTAssertNotEqual(featureFolder?.id, featureLeaf?.id)
    }
}
