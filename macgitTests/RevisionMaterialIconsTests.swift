// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import XCTest
@testable import macgit

final class RevisionMaterialIconsTests: XCTestCase {
    func testFileNameCompoundExtensionAndFallback() throws {
        let icons = try XCTUnwrap(RevisionMaterialIcons.shared)
        func icon(_ path: String) -> String {
            icons.icon(for: path, isLight: false)
        }
        XCTAssertEqual(icon("Sources/App.SWIFT"), "swift")
        XCTAssertEqual(icon("types/example.d.ts"), "typescript-def")
        XCTAssertEqual(icon("src/component.tsx"), "react_ts")
        XCTAssertEqual(icon("package.json"), icons.fileNames["package.json"] ?? "json")
        XCTAssertEqual(icon("unknown.unrecognizedextension"), icons.file)
        XCTAssertEqual(icon("README.md"), icons.fileNames["readme.md"] ?? "markdown")
    }

    @MainActor func testEveryBundledMappingAsset() throws {
        let icons = try XCTUnwrap(RevisionMaterialIcons.shared)
        let mappings = [icons.fileNames, icons.fileExtensions,
            icons.light.fileNames ?? [:], icons.light.fileExtensions ?? [:]]
        let names = Set(mappings.flatMap { $0.values }).union([icons.file])
        XCTAssertLessThanOrEqual(names.count, 120)
        XCTAssertGreaterThanOrEqual(names.count, 100)
        for name in names {
            XCTAssertNotNil(NSImage(named: "revision-material-" + name), "Missing icon: \(name)")
        }
    }
}
