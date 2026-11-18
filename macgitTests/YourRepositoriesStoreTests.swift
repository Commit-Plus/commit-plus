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

        XCTAssertEqual(result.map(\.url), [first, nestedInsideRepository, second])
        XCTAssertEqual(Set(result.map(\.url)).count, 3)
    }

    func testScanFindsRepositoriesNestedInsideRootThatIsARepository() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("your-repositories-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let nested = root.appendingPathComponent("nested", isDirectory: true)
        let deep = root.appendingPathComponent("group/deep", isDirectory: true)
        let insideNested = nested.appendingPathComponent("inner", isDirectory: true)
        for repository in [root, nested, deep, insideNested] {
            try fileManager.createDirectory(
                at: repository.appendingPathComponent(".git", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let result = YourRepositoriesStore.scanRoot(root)

        XCTAssertNil(result.error)
        XCTAssertEqual(
            Set(result.urls.map { $0.standardizedFileURL.path }),
            Set([root, nested, deep, insideNested].map { $0.standardizedFileURL.path })
        )
    }

    func testScanDescendsIntoRepositoriesUpToDepthLimitAndSkipsSubmodules() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("your-repositories-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let parent = root.appendingPathComponent("parent", isDirectory: true)
        let child = parent.appendingPathComponent("child", isDirectory: true)
        let atLimit = root.appendingPathComponent("a/b/c/d", isDirectory: true)
        let beyondLimit = root.appendingPathComponent("a/b/c/d/e", isDirectory: true)
        let inNodeModules = parent.appendingPathComponent("node_modules/dependency", isDirectory: true)
        for repository in [parent, child, atLimit, beyondLimit, inNodeModules] {
            try fileManager.createDirectory(
                at: repository.appendingPathComponent(".git", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let submodule = child.appendingPathComponent("core", isDirectory: true)
        try fileManager.createDirectory(at: submodule, withIntermediateDirectories: true)
        try Data("gitdir: ../.git/modules/core\n".utf8).write(to: submodule.appendingPathComponent(".git"))

        let result = YourRepositoriesStore.scanRoot(root)

        XCTAssertNil(result.error)
        XCTAssertEqual(
            Set(result.urls.map { $0.standardizedFileURL.path }),
            Set([parent, child, atLimit].map { $0.standardizedFileURL.path })
        )
    }
}
