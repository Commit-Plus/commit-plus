// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class RemoteEditValidationTests: XCTestCase {
    private let remotes = [
        "origin": "https://github.com/Commit-Plus/commit-plus.git",
        "lab": "https://gitlab.com/user/macgit-lab.git",
    ]

    func testAddRejectsExistingName() {
        XCTAssertEqual(
            RemoteEditValidation.conflictMessage(
                name: "origin", url: "https://example.com/new.git", mode: .add, existingRemotes: remotes
            ),
            "A remote named \"origin\" already exists."
        )
    }

    func testAddRejectsEquivalentURL() {
        XCTAssertEqual(
            RemoteEditValidation.conflictMessage(
                name: "copy", url: " https://GitHub.com/Commit-Plus/commit-plus/ ", mode: .add, existingRemotes: remotes
            ),
            "Remote \"origin\" already uses this URL."
        )
    }

    func testAddAllowsNewNameAndURL() {
        XCTAssertNil(RemoteEditValidation.conflictMessage(
            name: "upstream", url: "https://github.com/other/repo.git", mode: .add, existingRemotes: remotes
        ))
    }

    func testEditAllowsKeepingOwnURL() {
        XCTAssertNil(RemoteEditValidation.conflictMessage(
            name: "origin", url: "https://github.com/Commit-Plus/commit-plus",
            mode: .edit(name: "origin", url: remotes["origin"]!), existingRemotes: remotes
        ))
    }

    func testEditRejectsAnotherRemotesURL() {
        XCTAssertEqual(
            RemoteEditValidation.conflictMessage(
                name: "origin", url: "https://gitlab.com/user/macgit-lab.git",
                mode: .edit(name: "origin", url: remotes["origin"]!), existingRemotes: remotes
            ),
            "Remote \"lab\" already uses this URL."
        )
    }
}
