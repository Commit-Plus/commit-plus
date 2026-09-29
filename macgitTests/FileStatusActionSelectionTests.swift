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
final class FileStatusActionSelectionTests: XCTestCase {
    func testSelectionKeyChangesWhenConflictBecomesStaged() {
        let conflict = file("Sources/App.swift", status: .conflict)
        let resolved = file("Sources/App.swift", status: .staged)

        XCTAssertNotEqual(
            FileStatusSelectionKey(file: conflict, isStaged: true),
            FileStatusSelectionKey(file: resolved, isStaged: true)
        )
    }

    func testSectionTitlesUseAllWhenNothingIsSelected() {
        let policy = FileStatusActionSelection(
            selectedKeys: [],
            stagedFiles: [file("README.md", status: .staged)],
            changedFiles: [file("Sources/App.swift", status: .modified)]
        )

        XCTAssertEqual(policy.title(for: .staged), "Unstage All")
        XCTAssertEqual(policy.title(for: .changed), "Stage All")
    }

    func testSectionTitlesUseSelectedForSectionsWithSelectedFiles() {
        let staged = file("README.md", status: .staged)
        let changed = file("Sources/App.swift", status: .modified)
        let policy = FileStatusActionSelection(
            selectedKeys: [
                FileStatusSelectionKey(file: staged, isStaged: true),
                FileStatusSelectionKey(file: changed, isStaged: false)
            ],
            stagedFiles: [staged],
            changedFiles: [changed]
        )

        XCTAssertEqual(policy.title(for: .staged), "Unstage selected")
        XCTAssertEqual(policy.title(for: .changed), "Stage selected")
    }

    func testMenuTitlesUseSelectedWhenMultipleFilesAreSelected() {
        let first = file("Sources/App.swift", status: .modified)
        let second = file("Sources/Model.swift", status: .modified)
        let policy = FileStatusActionSelection(
            selectedKeys: [
                FileStatusSelectionKey(file: first, isStaged: false),
                FileStatusSelectionKey(file: second, isStaged: false)
            ],
            stagedFiles: [],
            changedFiles: [first, second]
        )

        XCTAssertTrue(policy.isSingleFileActionDisabled)
        XCTAssertEqual(policy.title(for: .stage), "Stage selected")
        XCTAssertEqual(policy.title(for: .discard), "Discard selected")
        XCTAssertEqual(policy.title(for: .remove), "Remove selected")
    }

    func testActionFilesUseSelectedEligibleFilesWhenMultipleFilesAreSelected() {
        let staged = file("README.md", status: .staged)
        let changed = file("Sources/App.swift", status: .modified)
        let untracked = file("Notes.txt", status: .untracked)
        let policy = FileStatusActionSelection(
            selectedKeys: [
                FileStatusSelectionKey(file: staged, isStaged: true),
                FileStatusSelectionKey(file: changed, isStaged: false),
                FileStatusSelectionKey(file: untracked, isStaged: false)
            ],
            stagedFiles: [staged],
            changedFiles: [changed, untracked]
        )

        XCTAssertEqual(policy.files(for: .stage, fallback: changed), [changed, untracked])
        XCTAssertEqual(policy.files(for: .unstage, fallback: staged), [staged])
        XCTAssertEqual(policy.files(for: .discard, fallback: changed), [changed, untracked])
        XCTAssertEqual(policy.files(for: .remove, fallback: changed), [staged, changed, untracked])
    }

    func testRemoveSelectedDeduplicatesPathsThatAppearInBothSections() {
        let staged = file("Sources/App.swift", status: .staged)
        let changed = file("Sources/App.swift", status: .modified)
        let untracked = file("Notes.txt", status: .untracked)
        let policy = FileStatusActionSelection(
            selectedKeys: [
                FileStatusSelectionKey(file: staged, isStaged: true),
                FileStatusSelectionKey(file: changed, isStaged: false),
                FileStatusSelectionKey(file: untracked, isStaged: false)
            ],
            stagedFiles: [staged],
            changedFiles: [changed, untracked]
        )

        XCTAssertEqual(policy.files(for: .remove, fallback: changed).map(\.path), ["Sources/App.swift", "Notes.txt"])
    }

    func testPrunedSelectionDropsFilesNoLongerPresent() {
        let present = file("README.md", status: .staged)
        let missing = file("Deleted.swift", status: .modified)
        let policy = FileStatusActionSelection(
            selectedKeys: [
                FileStatusSelectionKey(file: present, isStaged: true),
                FileStatusSelectionKey(file: missing, isStaged: false)
            ],
            stagedFiles: [present],
            changedFiles: []
        )

        XCTAssertEqual(policy.prunedSelection, [FileStatusSelectionKey(file: present, isStaged: true)])
    }

    func testDraggingSelectedRowCarriesAllSelectedFilePaths() {
        let staged = file("README.md", status: .staged)
        let changed = file("Sources/App.swift", status: .modified)
        let policy = FileStatusActionSelection(
            selectedKeys: [
                FileStatusSelectionKey(file: staged, isStaged: true),
                FileStatusSelectionKey(file: changed, isStaged: false)
            ],
            stagedFiles: [staged],
            changedFiles: [changed]
        )

        XCTAssertEqual(
            policy.dragPaths(startingAt: changed, isStaged: false),
            ["README.md", "Sources/App.swift"]
        )
    }

    func testDraggingUnselectedRowCarriesOnlyFallbackFilePath() {
        let selected = file("README.md", status: .staged)
        let fallback = file("Sources/App.swift", status: .modified)
        let policy = FileStatusActionSelection(
            selectedKeys: [FileStatusSelectionKey(file: selected, isStaged: true)],
            stagedFiles: [selected],
            changedFiles: [fallback]
        )

        XCTAssertEqual(
            policy.dragPaths(startingAt: fallback, isStaged: false),
            ["Sources/App.swift"]
        )
    }

    func testDragPathsDeduplicateFilesPresentInStagedAndChangedSections() {
        let staged = file("Sources/App.swift", status: .staged)
        let changed = file("Sources/App.swift", status: .modified)
        let policy = FileStatusActionSelection(
            selectedKeys: [
                FileStatusSelectionKey(file: staged, isStaged: true),
                FileStatusSelectionKey(file: changed, isStaged: false)
            ],
            stagedFiles: [staged],
            changedFiles: [changed]
        )

        XCTAssertEqual(
            policy.dragPaths(startingAt: staged, isStaged: true),
            ["Sources/App.swift"]
        )
    }

    func testDragPathsIncludeOriginalAndNewRenamePaths() {
        let renamed = file(
            "new-name.txt",
            status: .renamed,
            originalPath: "old-name.txt"
        )
        let policy = FileStatusActionSelection(
            selectedKeys: [FileStatusSelectionKey(file: renamed, isStaged: true)],
            stagedFiles: [renamed],
            changedFiles: []
        )

        XCTAssertEqual(
            policy.dragPaths(startingAt: renamed, isStaged: true),
            ["old-name.txt", "new-name.txt"]
        )
    }

    func testDroppingOnStagedReturnsOnlyChangedFiles() {
        let staged = file("README.md", status: .staged)
        let changed = file("Sources/App.swift", status: .modified)
        let untracked = file("Notes.txt", status: .untracked)
        let policy = FileStatusActionSelection(
            selectedKeys: [],
            stagedFiles: [staged],
            changedFiles: [changed, untracked]
        )

        XCTAssertEqual(
            policy.filesForDrop(
                paths: [staged.path, changed.path, untracked.path],
                into: .staged
            ),
            [changed, untracked]
        )
    }

    func testDroppingOnChangedReturnsOnlyStagedFiles() {
        let staged = file("README.md", status: .staged)
        let changed = file("Sources/App.swift", status: .modified)
        let policy = FileStatusActionSelection(
            selectedKeys: [],
            stagedFiles: [staged],
            changedFiles: [changed]
        )

        XCTAssertEqual(
            policy.filesForDrop(paths: [staged.path, changed.path], into: .changed),
            [staged]
        )
    }

    func testDropMatchesEitherPathOfRenamedFile() {
        let renamed = file(
            "new-name.txt",
            status: .renamed,
            originalPath: "old-name.txt"
        )
        let policy = FileStatusActionSelection(
            selectedKeys: [],
            stagedFiles: [renamed],
            changedFiles: []
        )

        XCTAssertEqual(
            policy.filesForDrop(paths: ["old-name.txt"], into: .changed),
            [renamed]
        )
    }

    private func file(
        _ path: String,
        status: FileStatus,
        originalPath: String? = nil
    ) -> StatusFile {
        StatusFile(path: path, status: status, originalPath: originalPath)
    }
}
