// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class JiraJQLBuilderTests: XCTestCase {
    func testDefaultFilterShowsOwnNotDoneIssuesInOpenSprints() {
        XCTAssertEqual(
            JiraJQLBuilder.jql(for: .default, supportsSprints: true),
            #"assignee = currentUser() AND sprint in openSprints() AND statusCategory in ("To Do", "In Progress") ORDER BY updated DESC"#
        )
    }

    func testSprintScopes() {
        var filter = JiraIssueFilter()
        filter.statusCategories = []

        filter.sprintScope = .sprint(id: 42, name: "Sprint 42")
        XCTAssertEqual(JiraJQLBuilder.jql(for: filter, supportsSprints: true), "assignee = currentUser() AND sprint = 42 ORDER BY updated DESC")
        filter.sprintScope = .backlog
        XCTAssertEqual(JiraJQLBuilder.jql(for: filter, supportsSprints: true), "assignee = currentUser() AND sprint is EMPTY ORDER BY updated DESC")
        filter.sprintScope = .any
        XCTAssertEqual(JiraJQLBuilder.jql(for: filter, supportsSprints: true), "assignee = currentUser() ORDER BY updated DESC")
    }

    func testSitesWithoutSprintsDropTheSprintClause() {
        XCTAssertFalse(JiraJQLBuilder.jql(for: .default, supportsSprints: false).contains("sprint"))
    }

    func testProjectTypeAndStatusFiltersAreQuotedAndOrdered() {
        var filter = JiraIssueFilter()
        filter.sprintScope = .any
        filter.statusCategories = [.done, .toDo]
        filter.projectKeys = ["WEB", "APP"]
        filter.issueTypeNames = ["Bug", "Story"]

        XCTAssertEqual(
            JiraJQLBuilder.jql(for: filter, supportsSprints: true),
            #"assignee = currentUser() AND statusCategory in ("To Do", "Done") AND project in ("APP", "WEB") AND issuetype in ("Bug", "Story") ORDER BY updated DESC"#
        )
    }

    func testSearchByKeyAddsExactKeyClause() {
        var filter = JiraIssueFilter()
        filter.sprintScope = .any
        filter.statusCategories = []
        filter.searchText = " proj-12 "

        XCTAssertEqual(
            JiraJQLBuilder.jql(for: filter, supportsSprints: true),
            #"assignee = currentUser() AND (summary ~ "proj 12" OR key = "PROJ-12") ORDER BY updated DESC"#
        )
        XCTAssertEqual(
            JiraJQLBuilder.jql(for: filter, supportsSprints: true, includeKeyClause: false),
            #"assignee = currentUser() AND summary ~ "proj 12" ORDER BY updated DESC"#
        )
    }

    func testSearchTextCannotEscapeItsQuotedValue() {
        var filter = JiraIssueFilter()
        filter.sprintScope = .any
        filter.statusCategories = []

        for attack in [
            #"x" OR assignee is not EMPTY OR summary ~ "y"#,
            #"x\" OR project = SECRET"#,
            "login) OR (assignee = EMPTY",
            "fix\nORDER BY created",
        ] {
            filter.searchText = attack
            let jql = JiraJQLBuilder.jql(for: filter, supportsSprints: true)
            XCTAssertTrue(jql.hasPrefix("assignee = currentUser() AND summary ~ \""), jql)
            XCTAssertTrue(jql.hasSuffix("\" ORDER BY updated DESC"), jql)
            let value = jql.dropFirst("assignee = currentUser() AND summary ~ \"".count).dropLast("\" ORDER BY updated DESC".count)
            XCTAssertFalse(value.contains("\""), jql)
            XCTAssertFalse(value.contains("("), jql)
            XCTAssertFalse(value.contains("\n"), jql)
        }
    }

    func testQuotedEscapesBackslashesAndQuotes() {
        XCTAssertEqual(JiraJQLBuilder.quoted(#"a\"b"#), #""a\\\"b""#)
    }

    func testOnlyOperatorCharactersMeansNoSearchClause() {
        var filter = JiraIssueFilter()
        filter.searchText = "*?!"
        XCTAssertEqual(JiraJQLBuilder.jql(for: filter, supportsSprints: true), JiraJQLBuilder.jql(for: .default, supportsSprints: true))
    }
}
