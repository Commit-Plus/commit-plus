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

final class SubmoduleRequestValidationTests: XCTestCase {
    func testRejectsEmptyRepository() throws {
        let repository = try makeRepositoryDirectory()

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(repository: "   "),
                in: repository
            )
        )
    }

    func testRejectsAbsoluteRepositoryThatIsNotAGitRepository() throws {
        let repository = try makeRepositoryDirectory()
        let localSource = repository.deletingLastPathComponent().appendingPathComponent("NotGit")
        try FileManager.default.createDirectory(at: localSource, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(repository: localSource.path),
                in: repository
            )
        ) { error in
            XCTAssertEqual(error as? SubmoduleRequestValidationError, .invalidLocalRepository)
        }
    }

    func testAcceptsAbsoluteRepositoryWithGitMetadata() throws {
        let repository = try makeRepositoryDirectory()
        let localSource = repository.deletingLastPathComponent().appendingPathComponent("LocalSource")
        try FileManager.default.createDirectory(at: localSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: localSource.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )

        let validated = try SubmoduleRequestValidator.validate(
            addRequest: request(repository: localSource.path),
            in: repository
        )

        XCTAssertEqual(validated.repository, localSource.path)
    }

    func testBuildsRelativePathForFolderInsideRepository() throws {
        let repository = try makeRepositoryDirectory()
        let destination = repository.appendingPathComponent("Packages/SharedKit")

        XCTAssertEqual(
            SubmoduleRequestValidator.relativePath(for: destination, in: repository),
            "Packages/SharedKit"
        )
    }

    func testDoesNotBuildRelativePathForFolderOutsideRepositoryOrRoot() throws {
        let repository = try makeRepositoryDirectory()
        let outside = repository.deletingLastPathComponent().appendingPathComponent("Outside")

        XCTAssertNil(SubmoduleRequestValidator.relativePath(for: repository, in: repository))
        XCTAssertNil(SubmoduleRequestValidator.relativePath(for: outside, in: repository))
    }

    func testRejectsAbsolutePath() throws {
        let repository = try makeRepositoryDirectory()

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "/tmp/SharedKit"),
                in: repository
            )
        )
    }

    func testRejectsParentTraversalOutsideRepository() throws {
        let repository = try makeRepositoryDirectory()

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "Packages/../../SharedKit"),
                in: repository
            )
        )
    }

    func testRejectsPathEscapingThroughSymlink() throws {
        let root = try makeTemporaryDirectory()
        let repository = root.appendingPathComponent("Parent", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: repository.appendingPathComponent("LinkedOutside"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "LinkedOutside/SharedKit"),
                in: repository
            )
        )
    }

    func testRejectsDuplicateConfiguredPath() throws {
        let repository = try makeRepositoryDirectory()
        let gitmodules = """
        [submodule "SharedKit"]
            path = Packages/SharedKit
            url = https://example.com/shared-kit.git
        """
        try gitmodules.write(
            to: repository.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "Packages/SharedKit"),
                in: repository
            )
        )
    }

    func testRejectsDuplicateConfiguredPathWithCaseInsensitiveKey() throws {
        let repository = try makeRepositoryDirectory()
        let gitmodules = """
        [submodule "SharedKit"]
            PATH = Packages/SharedKit
            url = https://example.com/shared-kit.git
        """
        try gitmodules.write(
            to: repository.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "Packages/SharedKit"),
                in: repository
            )
        ) { error in
            XCTAssertEqual(
                error as? SubmoduleRequestValidationError,
                .duplicatePath("Packages/SharedKit")
            )
        }
    }

    func testRejectsDuplicateConfiguredPathWithQuotedEscapedValue() throws {
        let repository = try makeRepositoryDirectory()
        let gitmodules = """
        [submodule "SharedKit"]
            path = "Packages/Shared\\\"Kit"
            url = https://example.com/shared-kit.git
        """
        try gitmodules.write(
            to: repository.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "Packages/Shared\"Kit"),
                in: repository
            )
        ) { error in
            XCTAssertEqual(
                error as? SubmoduleRequestValidationError,
                .duplicatePath("Packages/Shared\"Kit")
            )
        }
    }

    func testGitStatusServiceReadsConfiguredPathsUsingGitConfigSemantics() throws {
        let repository = try makeRepositoryDirectory()
        let gitmodules = """
        [submodule "SharedKit"]
            PATH = "Packages/Shared\\\"Kit"
            url = https://example.com/shared-kit.git
        """
        try gitmodules.write(
            to: repository.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            GitStatusService.shared.configuredSubmodulePaths(in: repository),
            ["Packages/Shared\"Kit"]
        )
    }

    func testTrimsConfiguredBranch() throws {
        let repository = try makeRepositoryDirectory()

        let validated = try SubmoduleRequestValidator.validate(
            addRequest: request(branch: "  release/v2  "),
            in: repository
        )

        XCTAssertEqual(validated.branch, "release/v2")
    }

    func testAcceptsAndStandardizesNestedRelativePath() throws {
        let repository = try makeRepositoryDirectory()

        let validated = try SubmoduleRequestValidator.validate(
            addRequest: request(
                repository: "  https://example.com/shared-kit.git  ",
                path: "  Packages\\Libraries/../SharedKit  "
            ),
            in: repository
        )

        XCTAssertEqual(validated.repository, "https://example.com/shared-kit.git")
        XCTAssertEqual(validated.path, "Packages/SharedKit")
        XCTAssertEqual(validated.initializeAfterAdd, true)
        XCTAssertEqual(validated.shallow, false)
    }

    func testRejectsNestedPathInsideActiveSubmodule() throws {
        let repository = try makeRepositoryDirectory()
        try """
        [submodule "package"]
            path = package
            url = https://example.com/package.git
        """.write(
            to: repository.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "package/tool"),
                in: repository
            )
        ) { error in
            XCTAssertEqual(
                error as? SubmoduleRequestValidationError,
                .nestedInsideSubmodule(path: "package/tool", existing: "package")
            )
        }
    }

    func testRejectsNestedPathInsideStaleGitDirectory() throws {
        let repository = try makeRepositoryDirectory()
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git/modules/package"),
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "package/tool"),
                in: repository
            )
        ) { error in
            XCTAssertEqual(
                error as? SubmoduleRequestValidationError,
                .staleSubmoduleGitDirectory(path: "package/tool", prefix: "package")
            )
        }
    }

    func testRejectsPathContainingActiveSubmodule() throws {
        let repository = try makeRepositoryDirectory()
        try """
        [submodule "Packages/OtherKit"]
            path = Packages/OtherKit
            url = https://example.com/other-kit.git
        """.write(
            to: repository.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try SubmoduleRequestValidator.validate(
                addRequest: request(path: "Packages"),
                in: repository
            )
        ) { error in
            XCTAssertEqual(
                error as? SubmoduleRequestValidationError,
                .ancestorOfSubmodule(path: "Packages", existing: "Packages/OtherKit")
            )
        }
    }

    func testAllowsReaddingSamePathWithStaleGitDirectory() throws {
        let repository = try makeRepositoryDirectory()
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git/modules/package"),
            withIntermediateDirectories: true
        )

        let validated = try SubmoduleRequestValidator.validate(
            addRequest: request(path: "package"),
            in: repository
        )

        XCTAssertEqual(validated.path, "package")
    }

    func testPreservesForceFlag() throws {
        let repository = try makeRepositoryDirectory()

        let validated = try SubmoduleRequestValidator.validate(
            addRequest: request(force: true),
            in: repository
        )

        XCTAssertTrue(validated.force)
        XCTAssertFalse(try SubmoduleRequestValidator.validate(addRequest: request(), in: repository).force)
    }

    private func request(
        repository: String = "https://example.com/shared-kit.git",
        path: String = "Packages/SharedKit",
        branch: String? = nil,
        force: Bool = false
    ) -> SubmoduleAddRequest {
        SubmoduleAddRequest(
            repository: repository,
            path: path,
            branch: branch,
            initializeAfterAdd: true,
            shallow: false,
            force: force
        )
    }

    private func makeRepositoryDirectory() throws -> URL {
        let root = try makeTemporaryDirectory()
        let repository = root.appendingPathComponent("Parent", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        return repository
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-submodule-validation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
