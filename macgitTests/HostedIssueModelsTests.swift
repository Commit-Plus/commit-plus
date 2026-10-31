// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class HostedIssueModelsTests: XCTestCase {
    func testReferenceFormatPerProvider() {
        XCTAssertEqual(HostedIssueProvider.github.reference(for: 42), "#42")
        XCTAssertEqual(HostedIssueProvider.gitlab.reference(for: 42), "#42")
        XCTAssertEqual(HostedIssueProvider.bitbucket.reference(for: 42), "#42")
        XCTAssertEqual(HostedIssueProvider.azureBoards.reference(for: 42), "AB#42")
    }

    func testProviderFollowsAccountKind() {
        XCTAssertEqual(HostedIssueProvider(.azureDevOps), .azureBoards)
        XCTAssertEqual(HostedIssueProvider(.gitlab).sidebarTitle, "GitLab Issues")
        XCTAssertEqual(HostedIssueProvider.azureBoards.sidebarTitle, "Azure Boards")
        XCTAssertEqual(HostedIssueProvider.azureBoards.accountKind, .azureDevOps)
    }

    func testFilterDefaultsAndRoundTrip() throws {
        XCTAssertEqual(HostedIssueFilter.default.state, .open)
        XCTAssertEqual(HostedIssueFilter.default.relationship, .all)
        XCTAssertTrue(HostedIssueFilter().isDefault)

        let filter = HostedIssueFilter(state: .closed, relationship: .assignedToMe)
        let data = try JSONEncoder().encode(filter)
        XCTAssertEqual(try JSONDecoder().decode(HostedIssueFilter.self, from: data), filter)
        XCTAssertFalse(filter.isDefault)
    }
}
