// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class GitProcessLaunchErrorTests: XCTestCase {
    func testMissingWorkingDirectoryIsNotReportedAsMissingGit() async throws {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-repository-\(UUID())", isDirectory: true)

        do {
            _ = try await GitStatusService.shared.runProcessRaw(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["status"],
                in: missingDirectory
            )
            XCTFail("Expected the missing working directory to fail")
        } catch let GitError.repositoryUnavailable(path) {
            XCTAssertEqual(path, missingDirectory.path)
        } catch {
            XCTFail("Expected repositoryUnavailable, got \(error)")
        }
    }

    func testMissingExecutableIsReportedAsMissingGit() async throws {
        let directory = FileManager.default.temporaryDirectory
        let missingExecutable = directory.appendingPathComponent("missing-git-\(UUID())")

        do {
            _ = try await GitStatusService.shared.runProcessRaw(
                executableURL: missingExecutable,
                arguments: [],
                in: directory
            )
            XCTFail("Expected the missing executable to fail")
        } catch GitError.gitNotFound {
            // Expected.
        } catch {
            XCTFail("Expected gitNotFound, got \(error)")
        }
    }
}
