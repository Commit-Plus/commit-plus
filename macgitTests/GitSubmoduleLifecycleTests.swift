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
import SwiftUI
@testable import macgit

final class GitSubmoduleLifecycleTests: XCTestCase {
    private var previousAllowedProtocols: String?

    override func setUp() {
        super.setUp()
        previousAllowedProtocols = ProcessInfo.processInfo.environment["GIT_ALLOW_PROTOCOL"]
        setenv("GIT_ALLOW_PROTOCOL", "file", 1)
    }

    override func tearDown() {
        if let previousAllowedProtocols {
            setenv("GIT_ALLOW_PROTOCOL", previousAllowedProtocols, 1)
        } else {
            unsetenv("GIT_ALLOW_PROTOCOL")
        }
        super.tearDown()
    }

    func testUpdateSubmoduleSettingsSetsURLAndBranch() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        let replacement = setup.root.appendingPathComponent("Replacement")
        try createRepository(at: replacement)

        try await GitStatusService.shared.updateSubmoduleSettings(
            path: "Packages/SharedKit",
            url: replacement.path,
            branch: "release",
            in: setup.parent
        )

        XCTAssertEqual(
            try runGitCapture(["config", "--file", ".gitmodules", "--get", "submodule.Packages/SharedKit.url"], in: setup.parent),
            replacement.path + "\n"
        )
        XCTAssertEqual(
            try runGitCapture(["config", "--file", ".gitmodules", "--get", "submodule.Packages/SharedKit.branch"], in: setup.parent),
            "release\n"
        )
    }

    func testUpdateSubmoduleSettingsClearsBranchToDefault() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        try runGit(["config", "--file", ".gitmodules", "submodule.Packages/SharedKit.branch", "release"], in: setup.parent)

        try await GitStatusService.shared.updateSubmoduleSettings(
            path: "Packages/SharedKit",
            url: setup.child.path,
            branch: nil,
            in: setup.parent
        )

        XCTAssertThrowsError(
            try runGitCapture(["config", "--file", ".gitmodules", "--get", "submodule.Packages/SharedKit.branch"], in: setup.parent)
        )
    }

    func testCleanDeinitializeRemovesLocalCheckoutButKeepsMetadata() async throws {
        let setup = try makeParentWithCommittedSubmodule()

        try await GitStatusService.shared.deinitializeSubmodule(path: "Packages/SharedKit", force: false, in: setup.parent)

        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit/shared.txt").path))
        XCTAssertEqual(
            try runGitCapture(["config", "--file", ".gitmodules", "--get", "submodule.Packages/SharedKit.path"], in: setup.parent),
            "Packages/SharedKit\n"
        )
        XCTAssertTrue(try runGitCapture(["ls-files", "--stage", "--", "Packages/SharedKit"], in: setup.parent).contains("160000"))
    }

    func testDirtyDeinitializeIsRejectedWithoutNotification() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        try dirtySubmodule(in: setup.parent)
        let notification = invertedRepositoryNotificationExpectation()

        do {
            try await GitStatusService.shared.deinitializeSubmodule(path: "Packages/SharedKit", force: false, in: setup.parent)
            XCTFail("Expected dirty deinitialize rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("uncommitted changes"))
        }

        await fulfillment(of: [notification.expectation], timeout: 0.2)
        NotificationCenter.default.removeObserver(notification.observer)
        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit/shared.txt").path))
    }

    func testForcedDeinitializeRemovesDirtyLocalCheckout() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        try dirtySubmodule(in: setup.parent)

        try await GitStatusService.shared.deinitializeSubmodule(path: "Packages/SharedKit", force: true, in: setup.parent)

        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit/shared.txt").path))
    }

    func testCleanRemovalStagesPathAndGitmodulesRemoval() async throws {
        let setup = try makeParentWithCommittedSubmodule()

        try await GitStatusService.shared.removeSubmodule(path: "Packages/SharedKit", force: false, in: setup.parent)

        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent(".gitmodules").path))
        let staged = try runGitCapture(["diff", "--cached", "--name-status"], in: setup.parent)
        XCTAssertTrue(staged.contains("D\t.gitmodules"))
        XCTAssertTrue(staged.contains("D\tPackages/SharedKit"))
    }

    func testDirtyRemovalIsRejectedWithoutNotification() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        try dirtySubmodule(in: setup.parent)
        let notification = invertedRepositoryNotificationExpectation()

        do {
            try await GitStatusService.shared.removeSubmodule(path: "Packages/SharedKit", force: false, in: setup.parent)
            XCTFail("Expected dirty remove rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("uncommitted changes"))
        }

        await fulfillment(of: [notification.expectation], timeout: 0.2)
        NotificationCenter.default.removeObserver(notification.observer)
        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit/shared.txt").path))
    }

    func testForcedRemovalStagesDirtyPathAndGitmodulesRemoval() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        try dirtySubmodule(in: setup.parent)

        try await GitStatusService.shared.removeSubmodule(path: "Packages/SharedKit", force: true, in: setup.parent)

        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit").path))
        let staged = try runGitCapture(["diff", "--cached", "--name-status"], in: setup.parent)
        XCTAssertTrue(staged.contains("D\t.gitmodules"))
        XCTAssertTrue(staged.contains("D\tPackages/SharedKit"))
    }

    func testStagedNewRemovalIsRejectedWithoutNotification() async throws {
        let setup = try makeRepositories()
        try runGit(["submodule", "add", "--", setup.child.path, "Packages/SharedKit"], in: setup.parent)
        let notification = invertedRepositoryNotificationExpectation()

        do {
            try await GitStatusService.shared.removeSubmodule(path: "Packages/SharedKit", force: false, in: setup.parent)
            XCTFail("Expected staged remove rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Confirm force"))
        }

        await fulfillment(of: [notification.expectation], timeout: 0.2)
        NotificationCenter.default.removeObserver(notification.observer)
        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit").path))
    }

    func testForcedRemovalOfStagedNewSubmoduleCleansUp() async throws {
        let setup = try makeRepositories()
        try runGit(["submodule", "add", "--", setup.child.path, "Packages/SharedKit"], in: setup.parent)

        try await GitStatusService.shared.removeSubmodule(path: "Packages/SharedKit", force: true, in: setup.parent)

        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent(".gitmodules").path))
        XCTAssertTrue(try runGitCapture(["status", "--porcelain"], in: setup.parent).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @MainActor
    func testRemoveThroughViewCallbackChainRemovesStagedSubmodule() async throws {
        // Drives the production wiring: a MainActor-isolated remove closure
        // stored in SidebarView, invoked through a Task-based operation runner
        // exactly like RepositoryOperationProgress + SidebarView do at runtime.
        // A calling-convention mismatch on this seam used to corrupt the path
        // argument and crash inside validatedSubmodulePath (EXC_BAD_ACCESS).
        let setup = try makeRepositories()
        try runGit(["submodule", "add", "--", setup.child.path, "Packages/SharedKit"], in: setup.parent)
        let entries = try await GitStatusService.shared.submodules(in: setup.parent)
        guard let entry = entries.first(where: { $0.path == "Packages/SharedKit" }) else {
            XCTFail("Expected staged submodule entry")
            return
        }
        let notification = expectation(forNotification: .repositoryDidChange, object: nil) { value in
            (value.userInfo?["repositoryURL"] as? URL) == setup.parent
        }
        var view = SidebarView(
            repositoryURL: setup.parent,
            selection: .constant(nil),
            onRequestCheckout: { _, _ in },
            onRequestFetchBranch: { _ in },
            onRequestRemoveSubmodule: { path, force in
                try await GitStatusService.shared.removeSubmodule(path: path, force: force, in: setup.parent)
            },
            onRunRepositoryOperation: { _, operation in
                Task { await operation() }
            }
        )
        view.runSubmoduleRemove(entry, force: true)

        await fulfillment(of: [notification], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent(".gitmodules").path))
    }

    func testRemoveCleansRegistrationWhenGitlinkAlreadyAbsent() async throws {
        let setup = try makeRepositories()
        try runGit(["submodule", "add", "--", setup.child.path, "package/tool"], in: setup.parent)
        try runGit(["commit", "-am", "add submodule"], in: setup.parent)
        let gitmodulesBackup = try String(
            contentsOf: setup.parent.appendingPathComponent(".gitmodules"),
            encoding: .utf8
        )
        try runGit(["rm", "--cached", "--", "package/tool"], in: setup.parent)
        try gitmodulesBackup.write(
            to: setup.parent.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "--", ".gitmodules"], in: setup.parent)
        try runGit(["commit", "-m", "half-removed state"], in: setup.parent)
        let notification = expectation(forNotification: .repositoryDidChange, object: nil) { value in
            (value.userInfo?["repositoryURL"] as? URL) == setup.parent
        }

        try await GitStatusService.shared.removeSubmodule(path: "package/tool", force: false, in: setup.parent)

        await fulfillment(of: [notification], timeout: 1)
        XCTAssertFalse(try runGitCapture(["ls-files", "--stage"], in: setup.parent).contains("package/tool"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent(".gitmodules").path))
    }

    func testRemoveHandlesCaseMismatchedGitlink() async throws {
        let setup = try makeRepositories()
        try runGit(["submodule", "add", "--", setup.child.path, "package/tool"], in: setup.parent)
        try runGit(["commit", "-am", "add submodule"], in: setup.parent)
        let notification = expectation(forNotification: .repositoryDidChange, object: nil) { value in
            (value.userInfo?["repositoryURL"] as? URL) == setup.parent
        }

        try await GitStatusService.shared.removeSubmodule(path: "Package/tool", force: false, in: setup.parent)

        await fulfillment(of: [notification], timeout: 1)
        XCTAssertFalse(try runGitCapture(["ls-files", "--stage"], in: setup.parent).contains("package/tool"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent(".gitmodules").path))
    }

    func testRemoveWithUntrackedGitmodulesDoesNotThrow() async throws {
        let setup = try makeRepositories()
        try """
        [submodule "package/tool"]
            path = package/tool
            url = https://example.com/tool.git
        """.write(
            to: setup.parent.appendingPathComponent(".gitmodules"),
            atomically: true,
            encoding: .utf8
        )
        let notification = expectation(forNotification: .repositoryDidChange, object: nil) { value in
            (value.userInfo?["repositoryURL"] as? URL) == setup.parent
        }

        try await GitStatusService.shared.removeSubmodule(path: "package/tool", force: false, in: setup.parent)

        await fulfillment(of: [notification], timeout: 1)
        let remaining = try runGitCapture(["config", "--file", ".gitmodules", "--list"], in: setup.parent)
        XCTAssertTrue(remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(try runGitCapture(["status", "--porcelain"], in: setup.parent).contains("?? .gitmodules"))
    }

    func testRemovingOneOfMultipleSubmodulesKeepsGitmodulesWithRemainingSection() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        let other = setup.root.appendingPathComponent("OtherKit")
        try createRepository(at: other)
        try "other\n".write(to: other.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "other.txt"], in: other)
        try runGit(["commit", "-m", "other base"], in: other)
        try runGit(["submodule", "add", "--", other.path, "Packages/OtherKit"], in: setup.parent)
        try runGit(["commit", "-am", "add other submodule"], in: setup.parent)

        try await GitStatusService.shared.removeSubmodule(path: "Packages/SharedKit", force: false, in: setup.parent)

        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent(".gitmodules").path))
        XCTAssertEqual(
            try runGitCapture(["config", "--file", ".gitmodules", "--get", "submodule.Packages/OtherKit.path"], in: setup.parent),
            "Packages/OtherKit\n"
        )
    }

    func testSuccessfulLifecycleActionPostsRepositoryNotification() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        let notification = expectation(forNotification: .repositoryDidChange, object: nil) { value in
            (value.userInfo?["repositoryURL"] as? URL) == setup.parent
        }

        try await GitStatusService.shared.deinitializeSubmodule(path: "Packages/SharedKit", force: false, in: setup.parent)

        await fulfillment(of: [notification], timeout: 1)
    }

    private func makeRepositories() throws -> (root: URL, child: URL, parent: URL) {
        let root = try makeTemporaryDirectory()
        let child = root.appendingPathComponent("SharedKit")
        let parent = root.appendingPathComponent("Parent")
        try createRepository(at: child)
        try "shared\n".write(to: child.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "shared.txt"], in: child)
        try runGit(["commit", "-m", "shared base"], in: child)
        try createRepository(at: parent)
        try runGit(["config", "protocol.file.allow", "always"], in: parent)
        try "parent\n".write(to: parent.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: parent)
        try runGit(["commit", "-m", "parent base"], in: parent)
        return (root, child, parent)
    }

    private func makeParentWithCommittedSubmodule() throws -> (root: URL, child: URL, parent: URL) {
        let setup = try makeRepositories()
        try runGit(["submodule", "add", "--", setup.child.path, "Packages/SharedKit"], in: setup.parent)
        try runGit(["commit", "-am", "add submodule"], in: setup.parent)
        return setup
    }

    private func dirtySubmodule(in parent: URL) throws {
        try "dirty\n".write(
            to: parent.appendingPathComponent("Packages/SharedKit/dirty.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func createRepository(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: url)
        try runGit(["config", "user.name", "Commit Plus Tests"], in: url)
        try runGit(["config", "user.email", "tests@example.com"], in: url)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macgit-submodule-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func invertedRepositoryNotificationExpectation() -> (expectation: XCTestExpectation, observer: NSObjectProtocol) {
        let notification = expectation(description: "no repository notification")
        notification.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: .repositoryDidChange, object: nil, queue: .main) { _ in
            notification.fulfill()
        }
        return (notification, observer)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        _ = try runGitCapture(arguments, in: directory)
    }

    private func runGitCapture(_ arguments: [String], in directory: URL) throws -> String {
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
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Git command failed")
        }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
