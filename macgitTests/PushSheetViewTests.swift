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

final class PushSheetViewTests: XCTestCase {
    func testRemoteSelectionPrefersCurrentBranchUpstream() {
        let remote = PushRemoteSelectionPolicy.resolve(
            remotes: ["gitlab", "origin"],
            currentBranch: "main",
            upstreams: ["main": "origin/main"]
        )

        XCTAssertEqual(remote, "origin")
    }

    func testRemoteSelectionRequiresChoiceWithoutUpstream() {
        let remote = PushRemoteSelectionPolicy.resolve(
            remotes: ["gitlab", "origin"],
            currentBranch: "feature/local-only",
            upstreams: ["main": "origin/main"]
        )

        XCTAssertEqual(remote, "")
    }

    func testRemoteSelectionUsesOnlyRemoteWithoutUpstream() {
        XCTAssertEqual(PushRemoteSelectionPolicy.resolve(
            remotes: ["origin"], currentBranch: "feature", upstreams: [:]
        ), "origin")
    }

    func testRemoteSelectionRequiresChoiceWhenUpstreamRemoteIsMissing() {
        XCTAssertEqual(PushRemoteSelectionPolicy.resolve(
            remotes: ["gitlab", "origin"], currentBranch: "feature",
            upstreams: ["feature": "removed/feature"]
        ), "")
    }

    func testRemoteSelectionHandlesNoRemotes() {
        XCTAssertEqual(PushRemoteSelectionPolicy.resolve(
            remotes: [], currentBranch: "feature", upstreams: [:]
        ), "")
    }

    func testRemoteSelectionMatchesLongestRemoteName() {
        let remote = PushRemoteSelectionPolicy.resolve(
            remotes: ["team", "team/gitlab"],
            currentBranch: "main",
            upstreams: ["main": "team/gitlab/main"]
        )

        XCTAssertEqual(remote, "team/gitlab")
    }

    func testMappingDoesNotReuseUpstreamFromAnotherRemote() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["feature"], upstreams: ["feature": "origin/review/topic"],
            currentBranch: "feature", remoteBranches: ["feature"], selectedRemote: "backup"
        )
        XCTAssertEqual(infos.first?.remote, "feature")
        XCTAssertEqual(infos.first?.isTracked, false)
    }

    func testBranchPushInfoBuilderUsesBulkUpstreamsAndSelectsTrackedCurrentBranch() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["main", "feature/new", "local-only"],
            upstreams: [
                "main": "origin/main",
                "feature/new": "origin/release/feature-new"
            ],
            currentBranch: "main"
        )

        XCTAssertEqual(infos.map(\.local), ["main", "feature/new", "local-only"])
        XCTAssertEqual(infos.map(\.remote), ["main", "release/feature-new", ""])
        XCTAssertEqual(infos.map(\.isTracked), [true, true, false])
        XCTAssertEqual(infos.map(\.isSelected), [true, false, false])
    }

    func testBranchPushInfoBuilderShowsExistingRemoteBranchWithoutUpstream() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["main", "feature", "local-only"],
            upstreams: ["main": "origin/main"],
            currentBranch: "feature",
            remoteBranches: ["main", "feature"]
        )

        XCTAssertEqual(infos.map(\.local), ["feature", "local-only", "main"])
        XCTAssertEqual(infos.map(\.remote), ["feature", "", "main"])
        XCTAssertEqual(infos.map(\.isTracked), [false, false, true])
        XCTAssertEqual(infos.map(\.isSelected), [true, false, false])
    }

    func testBranchPushInfoBuilderPrefersUpstreamOverMatchingRemoteBranch() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["feature"],
            upstreams: ["feature": "origin/release/feature-new"],
            currentBranch: "feature",
            remoteBranches: ["feature", "release/feature-new"]
        )

        XCTAssertEqual(infos.map(\.remote), ["release/feature-new"])
        XCTAssertEqual(infos.map(\.isTracked), [true])
    }

    func testBranchPushInfoBuilderPutsCurrentAndDefaultBranchFirst() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["feature/x", "develop", "zeta", "main", "alpha"],
            upstreams: ["main": "origin/main", "develop": "origin/develop"],
            currentBranch: "feature/x",
            defaultBranch: "main"
        )

        XCTAssertEqual(infos.map(\.local), ["feature/x", "main", "alpha", "develop", "zeta"])
    }

    func testBranchPushInfoBuilderUsesRepositoryDefaultBranchName() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["master", "feature/x", "develop", "alpha"],
            upstreams: ["master": "origin/master"],
            currentBranch: "feature/x",
            defaultBranch: "master"
        )

        XCTAssertEqual(infos.map(\.local), ["feature/x", "master", "alpha", "develop"])
    }

    func testBranchPushInfoBuilderPrioritizesCurrentBeforeDefaultBranch() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["main", "develop", "feature/x", "alpha"],
            upstreams: [:],
            currentBranch: "develop",
            defaultBranch: "main"
        )

        XCTAssertEqual(infos.map(\.local), ["develop", "main", "alpha", "feature/x"])
    }

    func testBranchPushInfoBuilderSortsAlphabeticallyWithoutDefaultBranch() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["main", "feature/x", "develop", "alpha"],
            upstreams: [:],
            currentBranch: "feature/x"
        )

        XCTAssertEqual(infos.map(\.local), ["feature/x", "alpha", "develop", "main"])
    }

    func testBranchPushInfoBuilderAutoSelectsCurrentBranchWithMatchingRemoteBranch() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["main", "feature/abctest", "local-only"],
            upstreams: ["main": "origin/main"],
            currentBranch: "feature/abctest",
            remoteBranches: ["main", "feature/abctest"]
        )

        XCTAssertEqual(infos.map(\.local), ["feature/abctest", "local-only", "main"])
        XCTAssertEqual(infos.map(\.remote), ["feature/abctest", "", "main"])
        XCTAssertEqual(infos.map(\.isTracked), [false, false, true])
        XCTAssertEqual(infos.map(\.isSelected), [true, false, false])
    }

    func testBranchPushInfoBuilderDoesNotSelectCurrentBranchWithoutRemoteBranch() {
        let infos = BranchPushInfoBuilder.build(
            localBranches: ["main", "feature/abctest"],
            upstreams: ["main": "origin/main"],
            currentBranch: "feature/abctest",
            remoteBranches: ["main"]
        )

        XCTAssertEqual(infos.map(\.isSelected), [false, false])
    }
}
