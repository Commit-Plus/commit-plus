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
import AppKit
import XCTest
@testable import macgit

@MainActor
final class HistoryViewTests: XCTestCase {
    func testBranchFilterMapsToGraphHighlighting() {
        XCTAssertEqual(HistoryLoadPolicy.highlighting(for: .all), .all)
        XCTAssertEqual(HistoryLoadPolicy.highlighting(for: .branch("feature/login")), .currentBranchOnly)
    }

    func testHighlightRootHashUsesSelectedBranchTipFromLoadedCommits() async {
        let commits = [
            makeCommit(hash: "feature-tip"),
            makeCommit(hash: "base")
        ]

        let rootHash = await HistoryLoadPolicy.highlightRootHash(
            for: .branch("feature/login"),
            commits: commits,
            repositoryURL: URL(fileURLWithPath: "/tmp/repo")
        )

        XCTAssertEqual(rootHash, "feature-tip")
    }

    func testBranchFilterUsesSelectedBranch() {
        let scope = HistoryLoadPolicy.historyScope(branchFilter: .branch("origin/feature/login"))

        if case .ref(let branch) = scope {
            XCTAssertEqual(branch, "origin/feature/login")
        } else {
            XCTFail("Expected selected branch scope")
        }
    }

    func testAllBranchFilterUsesAllBranches() {
        let scope = HistoryLoadPolicy.historyScope(branchFilter: .all)

        if case .allBranches = scope {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected all branches scope")
        }
    }

    func testCurrentBranchFilterUsesCurrentBranch() {
        let scope = HistoryLoadPolicy.historyScope(branchFilter: .current)

        if case .currentBranch = scope {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected current branch scope")
        }
    }

    func testTipCommitFindsBranchInLoadedAllBranchesSnapshot() {
        let commits = [
            makeCommit(hash: "main-tip", refs: ["HEAD -> main", "origin/main"]),
            makeCommit(hash: "feature-tip", refs: ["feature/login"]),
            makeCommit(hash: "base")
        ]

        XCTAssertEqual(HistoryLoadPolicy.tipCommit(for: "main", in: commits)?.hash, "main-tip")
        XCTAssertEqual(HistoryLoadPolicy.tipCommit(for: "feature/login", in: commits)?.hash, "feature-tip")
        XCTAssertNil(HistoryLoadPolicy.tipCommit(for: "missing", in: commits))
    }

    func testSidebarBranchSelectionUsesCurrentOnlyForCheckedOutBranch() {
        XCTAssertEqual(
            SidebarView.historyFilter(
                afterSelecting: "main",
                currentBranch: "main",
                currentFilter: .current
            ),
            .current
        )
        XCTAssertEqual(
            SidebarView.historyFilter(
                afterSelecting: "feature/login",
                currentBranch: "main",
                currentFilter: .current
            ),
            .all
        )
        XCTAssertEqual(
            SidebarView.historyFilter(
                afterSelecting: "main",
                currentBranch: "main",
                currentFilter: .all
            ),
            .all
        )
    }

    func testHistorySearchRequiresAtLeastThreeCharacters() {
        XCTAssertEqual(HistoryLoadPolicy.normalizedSearchQuery("ab"), "")
        XCTAssertEqual(HistoryLoadPolicy.normalizedSearchQuery("  ab "), "")
        XCTAssertEqual(HistoryLoadPolicy.normalizedSearchQuery("abc"), "abc")
        XCTAssertEqual(HistoryLoadPolicy.normalizedSearchQuery("  bob@example.com  "), "bob@example.com")
    }

    func testSquashRequiresHeadContiguousNonMergeCommits() {
        let commits = [
            makeCommit(hash: "head", parents: ["middle"]),
            makeCommit(hash: "middle", parents: ["base"])
        ]

        XCTAssertTrue(
            HistoryLoadPolicy.canSquashCommits(
                commits,
                selectedHashes: commits.map(\.hash),
                headHash: "head"
            )
        )
        XCTAssertFalse(
            HistoryLoadPolicy.canSquashCommits(
                [commits[1], commits[0]],
                selectedHashes: commits.map(\.hash),
                headHash: "head"
            )
        )
    }

    func testSquashRejectsMergeCommitsAndNonHeadSelection() {
        let merge = makeCommit(hash: "merge", parents: ["left", "right"])
        let regular = makeCommit(hash: "regular", parents: ["base"])

        XCTAssertFalse(
            HistoryLoadPolicy.canSquashCommits(
                [merge, regular],
                selectedHashes: ["merge", "regular"],
                headHash: "merge"
            )
        )
        XCTAssertFalse(
            HistoryLoadPolicy.canSquashCommits(
                [regular],
                selectedHashes: ["regular"],
                headHash: "head"
            )
        )
    }

    func testBranchReloadStartsSelectionAndScrollAtNewBranchTip() {
        XCTAssertEqual(
            HistoryLoadPolicy.reloadTargetHash(
                reset: true,
                selectedCommitHash: "shared-ancestor",
                newScrollTarget: "branch-tip"
            ),
            "branch-tip"
        )
    }

    func testDraggedCommitsUseSelectionForSelectedRowInOldestFirstOrder() {
        let commits = [
            makeCommit(hash: "newest", message: "Newest"),
            makeCommit(hash: "middle", message: "Middle"),
            makeCommit(hash: "oldest", message: "Oldest", parents: ["p1", "p2"])
        ]
        let selection = HistoryCommitSelection(
            selectedHashes: ["newest", "oldest"],
            primaryHash: "newest",
            anchorHash: "oldest"
        )

        XCTAssertEqual(
            HistoryLoadPolicy.draggedCommits(
                startingAt: "newest",
                commits: commits,
                selection: selection
            ),
            [
                GitDraggedCommit(hash: "oldest", message: "Oldest", isMerge: true),
                GitDraggedCommit(hash: "newest", message: "Newest", isMerge: false)
            ]
        )
    }

    func testMultiCommitDragPayloadContainsEverySelectedCommit() {
        let commits = [
            makeCommit(hash: "newest", message: "Newest"),
            makeCommit(hash: "middle", message: "Middle"),
            makeCommit(hash: "oldest", message: "Oldest")
        ]
        let selection = HistoryCommitSelection(
            selectedHashes: commits.map(\.hash),
            primaryHash: "oldest",
            anchorHash: "newest"
        )

        let draggedCommits = HistoryLoadPolicy.draggedCommits(
            startingAt: "middle",
            commits: commits,
            selection: selection
        )
        let payload = GitDragPayload.commits(
            draggedCommits,
            repositoryURL: URL(fileURLWithPath: "/tmp/repo")
        )

        XCTAssertEqual(payload.commits.map(\.hash), ["oldest", "middle", "newest"])
    }

    func testDraggedCommitsFallBackToDraggedRowWhenRowIsNotSelected() {
        let commits = [
            makeCommit(hash: "newest", message: "Newest"),
            makeCommit(hash: "middle", message: "Middle"),
            makeCommit(hash: "oldest", message: "Oldest")
        ]
        let selection = HistoryCommitSelection(
            selectedHashes: ["newest"],
            primaryHash: "newest",
            anchorHash: "newest"
        )

        XCTAssertEqual(
            HistoryLoadPolicy.draggedCommits(
                startingAt: "middle",
                commits: commits,
                selection: selection
            ),
            [GitDraggedCommit(hash: "middle", message: "Middle", isMerge: false)]
        )
    }

    func testCherryPickOrdersSelectedCommitsFromOldestToNewest() {
        let selectedCommits = [
            makeCommit(hash: "newest"),
            makeCommit(hash: "middle"),
            makeCommit(hash: "oldest")
        ]

        XCTAssertEqual(
            HistoryLoadPolicy.cherryPickCommits(from: selectedCommits).map(\.hash),
            ["oldest", "middle", "newest"]
        )
    }

    func testSingleCommitDragPreviewIncludesCommitMetadata() {
        let date = Date(timeIntervalSince1970: 1_234)
        let commit = Commit(
            hash: "1234567890abcdef",
            parents: [],
            message: "Polish commit drag preview",
            author: "Taylor",
            email: "taylor@example.com",
            date: date,
            refs: []
        )

        let presentation = CommitDragPreviewPresentation(commit: commit, commitCount: 1)

        XCTAssertEqual(presentation.subject, "Polish commit drag preview")
        XCTAssertEqual(presentation.shortHash, "1234567")
        XCTAssertEqual(presentation.author, "Taylor <taylor@example.com>")
        XCTAssertEqual(presentation.date, date)
        XCTAssertFalse(presentation.showsStack)
        XCTAssertNil(presentation.countBadgeText)
    }

    func testMultiCommitDragPreviewShowsStackAndCountBadge() {
        let commit = makeCommit(hash: "newest", message: "Newest")

        let presentation = CommitDragPreviewPresentation(commit: commit, commitCount: 3)

        XCTAssertTrue(presentation.showsStack)
        XCTAssertEqual(presentation.countBadgeText, "3 commits")
    }

    func testNativeTableSelectionMakesNewlyAddedRowPrimary() {
        XCTAssertEqual(
            HistoryLoadPolicy.primaryHashForTableSelection(
                oldSelection: ["newest"],
                newSelection: ["newest", "middle"],
                previousPrimaryHash: "newest",
                visibleHashes: ["newest", "middle", "oldest"]
            ),
            "middle"
        )
    }

    func testNativeTableRangeSelectionUsesFarthestAddedEndpoint() {
        XCTAssertEqual(
            HistoryLoadPolicy.primaryHashForTableSelection(
                oldSelection: ["middle"],
                newSelection: ["middle", "older", "oldest"],
                previousPrimaryHash: "middle",
                visibleHashes: ["newest", "middle", "older", "oldest"]
            ),
            "oldest"
        )

        XCTAssertEqual(
            HistoryLoadPolicy.primaryHashForTableSelection(
                oldSelection: ["older"],
                newSelection: ["newest", "middle", "older"],
                previousPrimaryHash: "older",
                visibleHashes: ["newest", "middle", "older", "oldest"]
            ),
            "newest"
        )
    }

    func testNativeTableRemovalPreservesPrimaryWhenStillSelected() {
        XCTAssertEqual(
            HistoryLoadPolicy.primaryHashForTableSelection(
                oldSelection: ["newest", "middle", "oldest"],
                newSelection: ["newest", "middle"],
                previousPrimaryHash: "middle",
                visibleHashes: ["newest", "middle", "oldest"]
            ),
            "middle"
        )
    }

    private func makeCommit(
        hash: String,
        message: String = "",
        parents: [String] = [],
        refs: [String] = []
    ) -> Commit {
        Commit(
            hash: hash,
            parents: parents,
            message: message,
            author: "Test",
            email: "test@example.com",
            date: Date(timeIntervalSince1970: 0),
            refs: refs
        )
    }
}
