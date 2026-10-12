// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import macgit

final class RemoteBranchDeleteResolverTests: XCTestCase {
    func testTrackedUpstreamTakesPriorityOverMatchingBranchName() {
        let target = RemoteBranchDeleteResolver.target(
            localBranch: "feature/demo",
            upstream: "fork/review/demo",
            branchesByRemote: [
                "origin": ["feature/demo"],
                "fork": ["review/demo"]
            ]
        )

        XCTAssertEqual(target, RemoteBranchDeleteTarget(remote: "fork", branch: "review/demo"))
    }

    func testFallsBackToOriginBranchWithSameName() {
        let target = RemoteBranchDeleteResolver.target(
            localBranch: "feature/demo",
            upstream: nil,
            branchesByRemote: [
                "origin": ["feature/demo"],
                "fork": ["feature/demo"]
            ]
        )

        XCTAssertEqual(target, RemoteBranchDeleteTarget(remote: "origin", branch: "feature/demo"))
    }

    func testFallsBackWhenTrackedUpstreamNoLongerExists() {
        let target = RemoteBranchDeleteResolver.target(
            localBranch: "feature/demo",
            upstream: "fork/review/demo",
            branchesByRemote: ["origin": ["feature/demo"]]
        )

        XCTAssertEqual(target, RemoteBranchDeleteTarget(remote: "origin", branch: "feature/demo"))
    }

    func testFallsBackToOnlyMatchingRemote() {
        let target = RemoteBranchDeleteResolver.target(
            localBranch: "feature/demo",
            upstream: nil,
            branchesByRemote: ["fork": ["feature/demo"]]
        )

        XCTAssertEqual(target, RemoteBranchDeleteTarget(remote: "fork", branch: "feature/demo"))
    }

    func testReturnsNilForAmbiguousNonOriginMatches() {
        let target = RemoteBranchDeleteResolver.target(
            localBranch: "feature/demo",
            upstream: nil,
            branchesByRemote: [
                "fork-a": ["feature/demo"],
                "fork-b": ["feature/demo"]
            ]
        )

        XCTAssertNil(target)
    }
}
