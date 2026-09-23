// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import XCTest
@testable import macgit

final class RevisionMaterialIconsTests: XCTestCase {
    func testFileNameCompoundExtensionAndFallback() throws {
        let icons = try XCTUnwrap(RevisionMaterialIcons.shared)
        func icon(_ path: String) -> String {
            icons.icon(for: path, isDirectory: false, isExpanded: false, isLight: false)
        }
        XCTAssertEqual(icon("Sources/App.SWIFT"), "swift")
        XCTAssertEqual(icon("types/example.d.ts"), "typescript-def")
        XCTAssertEqual(icon("src/component.tsx"), "react_ts")
        XCTAssertEqual(icon("package.json"), icons.fileNames["package.json"] ?? "json")
        XCTAssertEqual(icon("unknown.unrecognizedextension"), icons.file)
        XCTAssertEqual(icon("README.md"), icons.fileNames["readme.md"] ?? "markdown")
    }

    @MainActor func testFolderStatesAndEveryBundledMappingAsset() throws {
        let icons = try XCTUnwrap(RevisionMaterialIcons.shared)
        XCTAssertEqual(icons.icon(for: "src", isDirectory: true, isExpanded: false, isLight: false), "folder")
        XCTAssertEqual(icons.icon(for: "src", isDirectory: true, isExpanded: true, isLight: false), "folder-open")
        let mappings = [icons.fileNames, icons.fileExtensions,
            icons.light.fileNames ?? [:], icons.light.fileExtensions ?? [:]]
        let names = Set(mappings.flatMap { $0.values }).union([icons.file, icons.folder, icons.folderExpanded])
        XCTAssertLessThanOrEqual(names.count, 120)
        XCTAssertGreaterThanOrEqual(names.count, 100)
        for folder in ["docs", ".github", "tests", "arbitrary"] {
            XCTAssertEqual(icons.icon(for: folder, isDirectory: true, isExpanded: false, isLight: true), "folder")
            XCTAssertEqual(icons.icon(for: folder, isDirectory: true, isExpanded: true, isLight: true), "folder-open")
        }
        for name in names {
            XCTAssertNotNil(NSImage(named: "revision-material-" + name), "Missing icon: \(name)")
        }
    }
}
