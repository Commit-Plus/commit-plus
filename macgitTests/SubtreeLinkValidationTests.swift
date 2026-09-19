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

final class SubtreeLinkValidationTests: XCTestCase {
    func testRejectsRequiredFields() async throws {
        let repository = try makeRepository()

        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(name: ""), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .emptyName)
        }
        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(repository: ""), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .emptyRepository)
        }
        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(branch: ""), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .emptyBranch)
        }
        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(path: ""), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .emptyPath)
        }
    }

    func testRejectsAbsoluteAndEscapingPaths() async throws {
        let root = try makeTemporaryDirectory()
        let repository = root.appendingPathComponent("Repository", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try createRepository(at: repository)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: repository.appendingPathComponent("LinkedOutside"),
            withDestinationURL: outside
        )

        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(path: "/tmp/SharedKit"), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .absolutePath)
        }
        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(path: "../SharedKit"), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .pathOutsideRepository)
        }
        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(path: "LinkedOutside/SharedKit"), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .pathOutsideRepository)
        }
    }

    func testRejectsMissingDirectory() async throws {
        let repository = try makeRepository()

        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(path: "Packages/Missing"), in: repository)
        }) { error in
            XCTAssertEqual(error as? SubtreeLinkValidationError, .missingDirectory("Packages/Missing"))
        }
    }

    func testRejectsUntrackedDirectory() async throws {
        let repository = try makeRepository()
        try makeDirectory("Packages/SharedKit", in: repository)

        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(path: "Packages/SharedKit"), in: repository)
        }) { error in
            XCTAssertEqual(error as? SubtreeLinkValidationError, .untrackedDirectory("Packages/SharedKit"))
        }
    }

    func testRejectsDuplicateAndOverlappingPath() async throws {
        let repository = try makeRepository()
        try makeTrackedFile("Packages/SharedKit/file.txt", in: repository)
        try makeTrackedFile("Packages/Other/file.txt", in: repository)
        let registry = GitSubtreeRegistry()
        try await registry.save(existingEntry(id: "shared", path: "Packages/SharedKit"), in: repository)

        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(path: "Packages/SharedKit"), in: repository, registry: registry)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .duplicatePath("Packages/SharedKit"))
        }
        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(request(path: "Packages"), in: repository, registry: registry)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .overlappingPath("Packages/SharedKit"))
        }
    }

    func testRejectsInvalidLocalRepository() async throws {
        let repository = try makeRepository()
        let notARepo = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-not-a-repo-\(UUID().uuidString)", isDirectory: true)

        await XCTAssertThrowsErrorAsync({
            try await GitStatusService.shared.linkExistingSubtree(
                request(repository: notARepo.path),
                in: repository
            )
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .invalidLocalRepository)
        }
    }

    func testLinksValidTrackedDirectoryWithoutChangingWorkingTree() async throws {
        let repository = try makeRepository()
        try makeTrackedFile("Packages/SharedKit/file.txt", in: repository)
        let statusBefore = try runGit(["status", "--porcelain"], in: repository)
        let notification = expectation(forNotification: .repositoryDidChange, object: nil) { value in
            (value.userInfo?["repositoryURL"] as? URL) == repository
        }

        let entry = try await GitStatusService.shared.linkExistingSubtree(
            request(path: "Packages/SharedKit"),
            in: repository
        )

        await fulfillment(of: [notification], timeout: 1.0)
        XCTAssertEqual(entry.id, "packages-sharedkit")
        XCTAssertEqual(entry.path, "Packages/SharedKit")
        XCTAssertEqual(entry.repository, "https://example.com/shared.git")
        XCTAssertEqual(entry.branch, "main")
        XCTAssertEqual(try runGit(["status", "--porcelain"], in: repository), statusBefore)
        XCTAssertEqual(
            try runGit(["config", "--local", "--get", "commitplus-subtree.packages-sharedkit.path"], in: repository),
            "Packages/SharedKit\n"
        )
    }

    private func request(
        name: String = "SharedKit",
        path: String = "Packages/SharedKit",
        repository: String = "https://example.com/shared.git",
        branch: String = "main",
        squash: Bool = false
    ) -> SubtreeLinkRequest {
        SubtreeLinkRequest(
            name: name,
            path: path,
            repository: repository,
            branch: branch,
            squash: squash
        )
    }

    private func existingEntry(id: String, path: String) -> GitSubtreeEntry {
        GitSubtreeEntry(
            id: id,
            name: id,
            path: path,
            repository: "https://example.com/\(id).git",
            branch: "main",
            squash: false,
            folderExists: false
        )
    }

    private func makeRepository() throws -> URL {
        let root = try makeTemporaryDirectory()
        let repository = root.appendingPathComponent("Repository", isDirectory: true)
        try createRepository(at: repository)
        return repository
    }

    private func createRepository(at repository: URL) throws {
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repository)
        try runGit(["config", "user.name", "Commit Plus Tests"], in: repository)
        try runGit(["config", "user.email", "tests@example.com"], in: repository)
    }

    private func makeDirectory(_ path: String, in repository: URL) throws {
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(path, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func makeTrackedFile(_ path: String, in repository: URL) throws {
        let url = repository.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "tracked\n".write(to: url, atomically: true, encoding: .utf8)
        try runGit(["add", path], in: repository)
        try runGit(["commit", "-m", "track \(path)"], in: repository)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-subtree-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(String(data: errorData, encoding: .utf8) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> some Any,
    _ validation: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        validation(error)
    }
}
