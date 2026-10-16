// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class YourRepositoriesStoreTests: XCTestCase {
    func testScanFindsDirectoryAndWorktreeRepositoriesAndDeduplicatesOverlappingRoots() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("your-repositories-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let first = root.appendingPathComponent("first", isDirectory: true)
        try fileManager.createDirectory(
            at: first.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        let group = root.appendingPathComponent("group", isDirectory: true)
        let second = group.appendingPathComponent("second", isDirectory: true)
        try fileManager.createDirectory(at: second, withIntermediateDirectories: true)
        try Data("gitdir: elsewhere".utf8).write(to: second.appendingPathComponent(".git"))

        let nestedInsideRepository = first.appendingPathComponent("nested", isDirectory: true)
        try fileManager.createDirectory(
            at: nestedInsideRepository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        let result = YourRepositoriesStore.scanRepositories(in: [root, group])

        XCTAssertEqual(result.map(\.url), [first, second])
        XCTAssertEqual(Set(result.map(\.url)).count, 2)
    }
}
