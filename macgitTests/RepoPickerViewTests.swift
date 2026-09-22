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

final class RepoPickerViewTests: XCTestCase {
    func testMultipleBookmarksForOneLocalFolderProduceOneRow() {
        let github = makeRepository(name: "client", path: "/tmp/client", lastOpened: .distantPast)
        let gitlab = makeRepository(name: "client-mirror", path: "/tmp/client", lastOpened: .distantPast)
        let otherClone = makeRepository(name: "client", path: "/tmp/other-clone", lastOpened: .distantPast)
        let visible = RepoPickerView.visibleRepositories(
            from: [github, gitlab, otherClone],
            searchText: "",
            sortOption: .name,
            selectedFilterTypes: [],
            repoIcons: [:],
            rowStates: [:]
        )
        XCTAssertEqual(visible.count, 2)
        XCTAssertEqual(Set(visible.map(\.url)), [github.url, otherClone.url])
    }

    func testVisibleRepositoriesDefaultsToLastOpenedDescending() {
        let older = makeRepository(name: "Zeta", path: "/tmp/zeta", lastOpened: Date(timeIntervalSince1970: 100))
        let newer = makeRepository(name: "Alpha", path: "/tmp/alpha", lastOpened: Date(timeIntervalSince1970: 200))

        let visible = RepoPickerView.visibleRepositories(
            from: [older, newer],
            searchText: "",
            sortOption: .lastOpened,
            selectedFilterTypes: [],
            repoIcons: [:],
            rowStates: [:]
        )

        XCTAssertEqual(visible.map { $0.name }, ["Alpha", "Zeta"])
    }

    func testVisibleRepositoriesSortsByNameWhenRequested() {
        let zebra = makeRepository(name: "zebra", path: "/tmp/zebra", lastOpened: Date(timeIntervalSince1970: 300))
        let alpha = makeRepository(name: "Alpha", path: "/tmp/alpha", lastOpened: Date(timeIntervalSince1970: 100))

        let visible = RepoPickerView.visibleRepositories(
            from: [zebra, alpha],
            searchText: "",
            sortOption: .name,
            selectedFilterTypes: [],
            repoIcons: [:],
            rowStates: [:]
        )

        XCTAssertEqual(visible.map { $0.name }, ["Alpha", "zebra"])
    }

    func testVisibleRepositoriesMatchesBranchAndPathSearchText() {
        let worktreeRepo = makeRepository(
            name: "Workbench",
            path: "/Users/test/Work/Workbench",
            lastOpened: Date(timeIntervalSince1970: 100)
        )
        let docsRepo = makeRepository(
            name: "Docs",
            path: "/Users/test/Notes/Docs",
            lastOpened: Date(timeIntervalSince1970: 200)
        )
        let rowStates = [
            worktreeRepo.url: RepoPickerRowState(currentBranch: "feature/repo-picker", isMissing: false, isLoading: false),
            docsRepo.url: RepoPickerRowState(currentBranch: "main", isMissing: false, isLoading: false)
        ]

        let branchMatch = RepoPickerView.visibleRepositories(
            from: [worktreeRepo, docsRepo],
            searchText: "repo-picker",
            sortOption: .lastOpened,
            selectedFilterTypes: [],
            repoIcons: [:],
            rowStates: rowStates
        )
        let pathMatch = RepoPickerView.visibleRepositories(
            from: [worktreeRepo, docsRepo],
            searchText: "notes/docs",
            sortOption: .lastOpened,
            selectedFilterTypes: [],
            repoIcons: [:],
            rowStates: rowStates
        )

        XCTAssertEqual(branchMatch.map { $0.name }, ["Workbench"])
        XCTAssertEqual(pathMatch.map { $0.name }, ["Docs"])
    }

    func testCloneSheetDefaultsRepositoryNameFromHTTPRemoteURL() {
        let name = CloneSheetView.defaultRepositoryName(
            from: "https://gitlab.com/cki-project/cki-tools.git"
        )

        XCTAssertEqual(name, "cki-tools")
    }

    func testCloneSheetDefaultsRepositoryNameFromSSHRemoteURL() {
        let name = CloneSheetView.defaultRepositoryName(
            from: "git@github.com:owner/example-repo.git"
        )

        XCTAssertEqual(name, "example-repo")
    }

    func testCloneSheetFinalCloneURLAppendsRepositoryNameToDestinationFolder() throws {
        let finalURL = try XCTUnwrap(CloneSheetView.finalCloneURL(
            destinationPath: "/Users/thanhtran/Project",
            repositoryName: "test-repo"
        ))

        XCTAssertEqual(finalURL.path, "/Users/thanhtran/Project/test-repo")
    }

    func testCloneSheetFinalCloneURLRejectsNestedRepositoryName() {
        let finalURL = CloneSheetView.finalCloneURL(
            destinationPath: "/Users/thanhtran/Project",
            repositoryName: "../test-repo"
        )

        XCTAssertNil(finalURL)
    }

    func testRemoteBranchParserExtractsHeadNames() {
        let output = """
        abcdef1234567890\trefs/heads/main
        1234567890abcdef\trefs/heads/feature/clone-picker
        feedfacefeedface\trefs/tags/v1.0.0
        """

        let branches = GitStatusService.parseRemoteBranches(from: output)

        XCTAssertEqual(branches, ["feature/clone-picker", "main"])
    }

    private func makeRepository(name: String, path: String, lastOpened: Date) -> RecentRepository {
        var repo = RecentRepository(url: URL(fileURLWithPath: path), lastOpened: lastOpened)
        repo.name = name
        return repo
    }
}
