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

@MainActor
final class BranchSheetInitialStateTests: XCTestCase {
    func testInitialBranchNameIsPrefilledAndAlreadySanitized() {
        let suggested = JiraBranchNameSuggester.name(key: "PROJ-123", summary: "Fix login crash")
        let state = BranchSheetView.initialNameState(suggested)

        XCTAssertEqual(state.input, "PROJ-123-fix-login-crash")
        XCTAssertEqual(state.sanitized, "PROJ-123-fix-login-crash")
        XCTAssertEqual(BranchSheetView.initialNameState(nil).input, "")
        XCTAssertEqual(BranchSheetView.initialNameState(nil).sanitized, "")
    }

    func testDefaultInitialStatePrefersWorkingCopyParentWhenNoStartPointIsInjected() {
        let state = BranchSheetView.initialCreateState(
            initialStartPoint: nil,
            recentCommits: [
                BranchCommitInfo(hash: "abc123", message: "Latest commit")
            ]
        )

        XCTAssertTrue(state.useWorkingCopyParent)
        XCTAssertNil(state.selectedStartPoint)
    }

    func testInjectedCommitStartPointPreselectsCommitAndDisablesWorkingCopyParent() {
        let state = BranchSheetView.initialCreateState(
            initialStartPoint: .commit(hash: "def456", message: "Dragged commit"),
            recentCommits: [
                BranchCommitInfo(hash: "abc123", message: "Latest commit"),
                BranchCommitInfo(hash: "def456", message: "Dragged commit")
            ]
        )

        XCTAssertFalse(state.useWorkingCopyParent)
        XCTAssertEqual(state.selectedStartPoint, .commit(hash: "def456", message: "Dragged commit"))
        XCTAssertEqual(state.selectedStartReference, "def456")
    }

    func testInjectedBranchStartPointRemainsDistinctForFutureBranchBasedStartSelection() {
        let state = BranchSheetView.initialCreateState(
            initialStartPoint: .branch("release/1.0"),
            recentCommits: [
                BranchCommitInfo(hash: "abc123", message: "Latest commit")
            ]
        )

        XCTAssertFalse(state.useWorkingCopyParent)
        XCTAssertEqual(state.selectedStartPoint, .branch("release/1.0"))
        XCTAssertEqual(state.selectedStartReference, "release/1.0")
    }

    func testInjectedCommitNotPresentInRecentCommitsStillSelectsHashCleanly() {
        let state = BranchSheetView.initialCreateState(
            initialStartPoint: .commit(hash: "deadbeef", message: "Detached selection"),
            recentCommits: [
                BranchCommitInfo(hash: "abc123", message: "Latest commit")
            ]
        )

        XCTAssertFalse(state.useWorkingCopyParent)
        XCTAssertEqual(state.selectedStartPoint, .commit(hash: "deadbeef", message: "Detached selection"))
        XCTAssertEqual(state.selectedStartReference, "deadbeef")
    }

    func testBranchStartPointAppearsInPickerOptionsWhenNotPresentInRecentCommits() {
        let options = BranchSheetView.commitPickerOptions(
            selectedStartPoint: .branch("feature"),
            recentCommits: [
                BranchCommitInfo(hash: "abc123", message: "Latest commit")
            ]
        )

        XCTAssertEqual(options.first?.hash, "feature")
        XCTAssertEqual(options.first?.message, "Branch")
    }

    func testMatchingRemoteTargetsAreAvailableForFilteredLocalBranches() {
        let targets = BranchSheetView.matchingRemoteTargets(for: [
            BranchDeleteItem(
                name: "feature/one",
                type: .local,
                remoteTarget: RemoteBranchDeleteTarget(remote: "origin", branch: "feature/one"),
                isSelected: true
            ),
            BranchDeleteItem(
                name: "feature/two",
                type: .local,
                remoteTarget: RemoteBranchDeleteTarget(remote: "fork", branch: "review/two"),
                isSelected: true
            )
        ])

        XCTAssertEqual(targets, [
            RemoteBranchDeleteTarget(remote: "fork", branch: "review/two"),
            RemoteBranchDeleteTarget(remote: "origin", branch: "feature/one")
        ])
    }

    func testDeletionSummaryReportsSuccessesAndEachFailure() {
        let summary = GitStatusService.branchDeletionSummary(
            deletedCount: 2,
            failures: [
                .init(name: "feature/stale", message: "Merge evidence could not be verified."),
                .init(name: "origin/feature/remote", message: "The remote branch no longer exists.")
            ]
        )

        XCTAssertEqual(
            summary,
            """
            Deleted 2 selected branches.

            Could not complete:
            • feature/stale: Merge evidence could not be verified.
            • origin/feature/remote: The remote branch no longer exists.
            """
        )
    }
}
