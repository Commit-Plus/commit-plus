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

import FirebaseFirestore
import XCTest
@testable import macgit

final class CloudSettingsDocumentTests: XCTestCase {
    private let snapshot = AppSettingsSnapshot(
        appearance: .dark,
        showToolbarButtonText: false,
        showGitFlow: false,
        showWorkspaceReflog: false,
        showWorkspacePullRequests: true,
        showWorkspaceGitLFS: false,
        showSubmodules: true,
        showSubtrees: false,
        showHeaderBranchButton: true,
        showHeaderMergeButton: false,
        showHeaderStashButton: true,
        showHeaderUndoButton: true,
        showHeaderRemoteButton: false,
        showHeaderFinderButton: true,
        showHeaderEditorButton: false,
        showHeaderTerminalButton: false,
        showHeaderSettingsButton: true,
        historyBranchFilter: .branch("origin/feature/login"),
        historyIncludeRemotes: true,
        autoFetchEnabled: true,
        refreshOnAppActive: false
    )

    func testEncodingUsesExactDocumentSchema() throws {
        let timestamp = Timestamp(date: Date(timeIntervalSince1970: 123))

        let document = CloudSettingsDocument.encode(snapshot, updatedAt: timestamp)

        XCTAssertEqual(
            Set(document.keys),
            [
                "schemaVersion",
                "appearance",
                "showToolbarButtonText",
                "showGitFlow",
                "showWorkspaceReflog",
                "showWorkspacePullRequests",
                "showWorkspaceGitLFS",
                "showSubmodules",
                "showSubtrees",
                "showHeaderBranchButton",
                "showHeaderMergeButton",
                "showHeaderStashButton",
                "showHeaderUndoButton",
                "showHeaderRemoteButton",
                "showHeaderFinderButton",
                "showHeaderEditorButton",
                "showHeaderTerminalButton",
                "showHeaderSettingsButton",
                "historyBranchFilter",
                "historyIncludeRemotes",
                "autoFetchEnabled",
                "refreshOnAppActive",
                "updatedAt"
            ]
        )
        XCTAssertEqual(document["schemaVersion"] as? Int, 1)
        XCTAssertEqual(document["appearance"] as? String, "dark")
        XCTAssertEqual(document["showToolbarButtonText"] as? Bool, false)
        XCTAssertEqual(document["showGitFlow"] as? Bool, false)
        XCTAssertEqual(document["showWorkspaceReflog"] as? Bool, false)
        XCTAssertEqual(document["showWorkspacePullRequests"] as? Bool, true)
        XCTAssertEqual(document["showWorkspaceGitLFS"] as? Bool, false)
        XCTAssertEqual(document["showSubmodules"] as? Bool, true)
        XCTAssertEqual(document["showSubtrees"] as? Bool, false)
        XCTAssertEqual(document["showHeaderBranchButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderMergeButton"] as? Bool, false)
        XCTAssertEqual(document["showHeaderStashButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderUndoButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderRemoteButton"] as? Bool, false)
        XCTAssertEqual(document["showHeaderFinderButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderEditorButton"] as? Bool, false)
        XCTAssertEqual(document["showHeaderTerminalButton"] as? Bool, false)
        XCTAssertEqual(document["showHeaderSettingsButton"] as? Bool, true)
        XCTAssertEqual(document["historyBranchFilter"] as? String, "branch:origin/feature/login")
        XCTAssertEqual(document["historyIncludeRemotes"] as? Bool, true)
        XCTAssertEqual(document["autoFetchEnabled"] as? Bool, true)
        XCTAssertEqual(document["refreshOnAppActive"] as? Bool, false)
        XCTAssertEqual(document["updatedAt"] as? Timestamp, timestamp)
    }

    func testDecodingDefaultsMissingHeaderButtonsToTrue() throws {
        var document = validDocument()
        document.removeValue(forKey: "showHeaderBranchButton")
        document.removeValue(forKey: "showHeaderUndoButton")
        document.removeValue(forKey: "showHeaderRemoteButton")
        document.removeValue(forKey: "showHeaderEditorButton")
        document.removeValue(forKey: "showHeaderSettingsButton")

        let decoded = try CloudSettingsDocument.decode(document)

        XCTAssertTrue(decoded.showHeaderBranchButton)
        XCTAssertFalse(decoded.showHeaderUndoButton)
        XCTAssertTrue(decoded.showHeaderRemoteButton)
        XCTAssertTrue(decoded.showHeaderEditorButton)
        XCTAssertFalse(decoded.showHeaderSettingsButton)
    }

    func testDecodingDefaultsMissingGitFlowVisibilityToTrue() throws {
        var document = validDocument()
        document.removeValue(forKey: "showGitFlow")

        let decoded = try CloudSettingsDocument.decode(document)

        XCTAssertTrue(decoded.showGitFlow)
    }

    func testDecodingDefaultsMissingWorkspaceVisibilityToTrue() throws {
        var document = validDocument()
        document.removeValue(forKey: "showWorkspaceReflog")
        document.removeValue(forKey: "showWorkspacePullRequests")
        document.removeValue(forKey: "showWorkspaceGitLFS")

        let decoded = try CloudSettingsDocument.decode(document)

        XCTAssertTrue(decoded.showWorkspaceReflog)
        XCTAssertTrue(decoded.showWorkspacePullRequests)
        XCTAssertTrue(decoded.showWorkspaceGitLFS)
    }

    func testDecodingDefaultsMissingHistoryFilterSettings() throws {
        var document = validDocument()
        document.removeValue(forKey: "historyBranchFilter")
        document.removeValue(forKey: "historyIncludeRemotes")

        let decoded = try CloudSettingsDocument.decode(document)

        XCTAssertEqual(decoded.historyBranchFilter, .all)
        XCTAssertFalse(decoded.historyIncludeRemotes)
    }

    func testDecodingDefaultsMissingPullFetchSettings() throws {
        var document = validDocument()
        document.removeValue(forKey: "autoFetchEnabled")
        document.removeValue(forKey: "refreshOnAppActive")

        let decoded = try CloudSettingsDocument.decode(document)

        XCTAssertFalse(decoded.autoFetchEnabled)
        XCTAssertTrue(decoded.refreshOnAppActive)
    }

    func testDecodingDefaultsMissingAppearanceToSystem() throws {
        var document = validDocument()
        document.removeValue(forKey: "appearance")

        let decoded = try CloudSettingsDocument.decode(document)

        XCTAssertEqual(decoded.appearance, .system)
    }

    func testDecodingRejectsInvalidAppearance() {
        var unsupported = validDocument()
        unsupported["appearance"] = "sepia"
        var wrongType = validDocument()
        wrongType["appearance"] = true

        XCTAssertThrowsError(try CloudSettingsDocument.decode(unsupported))
        XCTAssertThrowsError(try CloudSettingsDocument.decode(wrongType))
    }

    func testDecodingValidDocumentReturnsCompleteSnapshot() throws {
        let decoded = try CloudSettingsDocument.decode(validDocument())

        XCTAssertEqual(decoded, snapshot)
    }

    func testDecodingRejectsMissingRequiredField() {
        var document = validDocument()
        document.removeValue(forKey: "showSubmodules")

        XCTAssertThrowsError(try CloudSettingsDocument.decode(document)) { error in
            XCTAssertEqual(error as? CloudSettingsError, .invalidDocument)
        }
    }

    func testDecodingRejectsWrongFieldTypeWithoutPartialSnapshot() {
        var document = validDocument()
        document["showSubtrees"] = "false"

        XCTAssertThrowsError(try CloudSettingsDocument.decode(document)) { error in
            XCTAssertEqual(error as? CloudSettingsError, .invalidDocument)
        }
    }

    func testDecodingRejectsMissingOrWrongTimestamp() {
        var missing = validDocument()
        missing.removeValue(forKey: "updatedAt")
        var wrongType = validDocument()
        wrongType["updatedAt"] = Date()

        XCTAssertThrowsError(try CloudSettingsDocument.decode(missing))
        XCTAssertThrowsError(try CloudSettingsDocument.decode(wrongType))
    }

    private func validDocument() -> [String: Any] {
        CloudSettingsDocument.encode(
            snapshot,
            updatedAt: Timestamp(date: Date(timeIntervalSince1970: 123))
        )
    }
}
