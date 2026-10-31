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

final class SidebarViewStashTests: XCTestCase {
    func testSidebarSectionStateDecodesMissingStashesExpandedAsTrue() throws {
        let data = #"{"branchesExpanded":false,"tagsExpanded":true,"remotesExpanded":false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SidebarSectionState.self, from: data)

        XCTAssertFalse(decoded.branchesExpanded)
        XCTAssertTrue(decoded.tagsExpanded)
        XCTAssertFalse(decoded.remotesExpanded)
        XCTAssertTrue(decoded.stashesExpanded)
    }

    func testSidebarSettingsStorePersistsStashesSectionToggle() {
        let repositoryPath = "/tmp/sidebar-stash-\(UUID().uuidString)"

        let initialState = SidebarSettingsStore.shared.state(for: repositoryPath)
        XCTAssertTrue(initialState.stashesExpanded)
        XCTAssertFalse(initialState.branchesExpanded)
        XCTAssertFalse(initialState.worktreesExpanded)

        SidebarSettingsStore.shared.toggleSection(.stashes, for: repositoryPath)

        let updatedState = SidebarSettingsStore.shared.state(for: repositoryPath)
        XCTAssertFalse(updatedState.stashesExpanded)
        XCTAssertFalse(updatedState.branchesExpanded)
        XCTAssertTrue(updatedState.tagsExpanded)
        XCTAssertTrue(updatedState.remotesExpanded)
    }

    func testSidebarSectionStateDecodesMissingWorktreesExpandedAsFalse() throws {
        let data = #"{"branchesExpanded":true,"tagsExpanded":false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SidebarSectionState.self, from: data)

        XCTAssertFalse(decoded.worktreesExpanded)
    }

    func testSidebarSectionStateDecodesMissingSubmodulesExpandedAsTrue() throws {
        let data = #"{"branchesExpanded":true,"tagsExpanded":false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SidebarSectionState.self, from: data)

        XCTAssertTrue(decoded.submodulesExpanded)
    }

    func testSidebarSectionStateDecodesMissingIssuesExpandedAsTrue() throws {
        let data = #"{"branchesExpanded":true,"tagsExpanded":false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SidebarSectionState.self, from: data)

        XCTAssertTrue(decoded.issuesExpanded)
    }

    func testSidebarSettingsStorePersistsIssuesSectionToggle() {
        let repositoryPath = "/tmp/sidebar-issues-\(UUID().uuidString)"

        SidebarSettingsStore.shared.toggleSection(.issues, for: repositoryPath)

        let updatedState = SidebarSettingsStore.shared.state(for: repositoryPath)
        XCTAssertFalse(updatedState.issuesExpanded)
        XCTAssertTrue(updatedState.stashesExpanded)
    }

    func testJiraMovesFromWorkspaceToIssuesSection() {
        XCTAssertFalse(SidebarSection.workspace.items.contains(.jira))
        XCTAssertEqual(SidebarSection.issues.items, [.jira, .hostedIssues])
    }

    func testSidebarSettingsStorePersistsSubmodulesSectionToggle() {
        let repositoryPath = "/tmp/sidebar-submodule-\(UUID().uuidString)"

        XCTAssertTrue(SidebarSettingsStore.shared.state(for: repositoryPath).submodulesExpanded)

        SidebarSettingsStore.shared.toggleSection(.submodules, for: repositoryPath)

        XCTAssertFalse(SidebarSettingsStore.shared.state(for: repositoryPath).submodulesExpanded)
    }
}
