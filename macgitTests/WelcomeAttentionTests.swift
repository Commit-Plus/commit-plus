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

final class WelcomeAttentionTests: XCTestCase {
    private let repository = RecentRepository(url: URL(fileURLWithPath: "/repo"))

    func testDivergedBranchAndConflictPriority() {
        let status = GitStatusService.parseWelcomeAttention("# branch.head feature/example\n# branch.ab +4 -2\nu conflict\n", repository: repository)
        XCTAssertEqual(status.branch, "feature/example")
        XCTAssertEqual(status.ahead, 4)
        XCTAssertEqual(status.behind, 2)
        XCTAssertEqual(status.conflicts, 1)
        XCTAssertEqual(status.priority, 0)
        XCTAssertFalse(status.showsHistory)
    }

    func testDivergedAndAheadAndBehindRouteToHistoryInPriorityOrder() {
        let diverged = GitStatusService.parseWelcomeAttention("# branch.ab +3 -2", repository: repository)
        let ahead = GitStatusService.parseWelcomeAttention("# branch.ab +3 -0", repository: repository)
        let behind = GitStatusService.parseWelcomeAttention("# branch.ab +0 -2", repository: repository)
        XCTAssertEqual([diverged.priority, ahead.priority, behind.priority], [1, 2, 3])
        XCTAssertTrue([diverged, ahead, behind].allSatisfy(\.showsHistory))
    }

    func testTrackedChangesRouteToFileStatus() {
        let output = """
        # branch.head main
        1 .M N... 100644 100644 100644 abc abc tracked.txt
        """
        let status = GitStatusService.parseWelcomeAttention(output, repository: repository)
        XCTAssertTrue(status.hasUncommittedChanges)
        XCTAssertFalse(status.showsHistory)
    }

    func testUntrackedFilesRouteToFileStatus() {
        let status = GitStatusService.parseWelcomeAttention("# branch.head main\n? new.txt", repository: repository)
        XCTAssertTrue(status.hasUncommittedChanges)
        XCTAssertFalse(status.showsHistory)
    }

    func testUnreadableStatusDoesNotRouteToHistory() {
        let malformed = GitStatusService.parseWelcomeAttention("# branch.ab garbage", repository: repository)
        XCTAssertNotNil(malformed.error)
        XCTAssertFalse(malformed.showsHistory)
        var unavailable = WelcomeRepositoryAttention(url: repository.url, name: repository.name)
        unavailable.unavailable = true
        XCTAssertFalse(unavailable.showsHistory)
    }

    func testUnfinishedOperationNeedsReviewEvenWithCleanIndex() {
        var status = GitStatusService.parseWelcomeAttention("# branch.head main", repository: repository)
        XCTAssertFalse(status.needsAttention)
        status.operation = "Rebase"
        XCTAssertTrue(status.needsAttention)
        XCTAssertFalse(status.showsHistory)
        XCTAssertEqual(status.priority, 0)
    }

    func testDetachedOrUnbornBranchWithoutUpstreamIsNotAnIssue() {
        let status = GitStatusService.parseWelcomeAttention("# branch.oid (initial)\n# branch.head main", repository: repository)
        XCTAssertFalse(status.needsAttention)
        let detached = GitStatusService.parseWelcomeAttention("# branch.head (detached)", repository: repository)
        XCTAssertEqual(detached.branch, "Detached HEAD")
        XCTAssertFalse(detached.needsAttention)
    }

    func testHistoryDestinationSurvivesWindowRequestEncoding() throws {
        let request = RepositoryWindowRequest.repository(repository.url, shouldFitVisibleScreen: true, showsHistory: true)
        let restored = try JSONDecoder().decode(RepositoryWindowRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(restored.showsHistory, true)
    }
}
