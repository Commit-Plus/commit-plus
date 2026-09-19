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

final class GitSubmoduleActionTests: XCTestCase {
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

    func testAddSubmoduleUsesRemoteDefaultBranchAndStagesGitlink() async throws {
        let setup = try makeRepositories()
        let request = SubmoduleAddRequest(
            repository: setup.child.path,
            path: "Packages/SharedKit",
            branch: nil,
            initializeAfterAdd: true,
            shallow: false
        )

        try await GitStatusService.shared.addSubmodule(request, in: setup.parent, credentialResolver: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit/shared.txt").path))
        let staged = try runGitCapture(["diff", "--cached", "--name-only"], in: setup.parent)
        XCTAssertEqual(Set(staged.split(separator: "\n").map(String.init)), [".gitmodules", "Packages/SharedKit"])
    }

    func testAddSubmoduleReplacesEmptyPrecreatedDestinationFolder() async throws {
        let setup = try makeRepositories()
        let destination = setup.parent.appendingPathComponent("backend")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let request = SubmoduleAddRequest(
            repository: setup.child.path,
            path: "backend",
            branch: nil,
            initializeAfterAdd: true,
            shallow: false
        )

        try await GitStatusService.shared.addSubmodule(request, in: setup.parent, credentialResolver: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("shared.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".git").path))
    }

    func testAddSubmoduleUsesSpecificBranch() async throws {
        let setup = try makeRepositories()
        try runGit(["checkout", "-b", "release"], in: setup.child)
        try "release\n".write(to: setup.child.appendingPathComponent("release.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "release.txt"], in: setup.child)
        try runGit(["commit", "-m", "release"], in: setup.child)
        try runGit(["checkout", "main"], in: setup.child)
        let request = SubmoduleAddRequest(
            repository: setup.child.path,
            path: "Packages/SharedKit",
            branch: "release",
            initializeAfterAdd: true,
            shallow: false
        )

        try await GitStatusService.shared.addSubmodule(request, in: setup.parent, credentialResolver: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit/release.txt").path))
        XCTAssertEqual(try runGitCapture(["config", "--file", ".gitmodules", "--get", "submodule.Packages/SharedKit.branch"], in: setup.parent), "release\n")
    }

    func testAddLocalSubmoduleAllowsFileTransport() async throws {
        let setup = try makeRepositories()
        let runner = RecordingSubmoduleRunner()
        let service = GitStatusService(runner: runner)
        let request = SubmoduleAddRequest(
            repository: setup.child.path,
            path: "Packages/SharedKit",
            branch: nil,
            initializeAfterAdd: true,
            shallow: false
        )

        try await service.addSubmodule(request, in: setup.parent, credentialResolver: nil)

        let calls = await runner.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].environment?["GIT_ALLOW_PROTOCOL"], "file")
    }

    func testAddedSubmoduleCanBeDiscoveredImmediately() async throws {
        let setup = try makeRepositories()
        let request = SubmoduleAddRequest(
            repository: setup.child.path,
            path: "backend",
            branch: nil,
            initializeAfterAdd: true,
            shallow: false
        )

        try await GitStatusService.shared.addSubmodule(request, in: setup.parent, credentialResolver: nil)
        unsetenv("GIT_ALLOW_PROTOCOL")

        let entries = try await GitStatusService.shared.submodules(in: setup.parent)
        XCTAssertEqual(entries.map(\.path), ["backend"])
        XCTAssertEqual(entries.first?.state, .clean)
    }

    func testAddWithoutInitializationLeavesStagedMetadataAndUninitializedCheckout() async throws {
        let setup = try makeRepositories()
        let request = SubmoduleAddRequest(
            repository: setup.child.path,
            path: "Packages/SharedKit",
            branch: nil,
            initializeAfterAdd: false,
            shallow: false
        )

        try await GitStatusService.shared.addSubmodule(request, in: setup.parent, credentialResolver: nil)

        let staged = try runGitCapture(["diff", "--cached", "--name-only"], in: setup.parent)
        XCTAssertEqual(Set(staged.split(separator: "\n").map(String.init)), [".gitmodules", "Packages/SharedKit"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("Packages/SharedKit/shared.txt").path))
        XCTAssertTrue(try runGitCapture(["ls-files", "--stage", "--", "Packages/SharedKit"], in: setup.parent).contains("160000"))
    }

    func testAddBuildsBranchAndShallowArgumentsAndKeepsCredentialOutOfArguments() async throws {
        let runner = RecordingSubmoduleRunner()
        let service = GitStatusService(runner: runner)
        let resolver = makeCredentialResolver(token: "top-secret-token")
        let request = SubmoduleAddRequest(
            repository: "https://github.com/example/SharedKit.git",
            path: "Packages/SharedKit",
            branch: "release",
            initializeAfterAdd: true,
            shallow: true
        )

        try await service.addSubmodule(request, in: URL(fileURLWithPath: "/tmp/parent"), credentialResolver: resolver)

        let calls = await runner.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].arguments, [
            "submodule", "add", "--branch", "release", "--depth", "1", "--",
            "https://github.com/example/SharedKit.git", "Packages/SharedKit"
        ])
        XCTAssertFalse(calls[0].arguments.joined(separator: " ").contains("top-secret-token"))
        XCTAssertNotNil(calls[0].environment?["GIT_ASKPASS"])
    }

    func testInitializeSubmoduleAfterFreshClone() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        let clone = setup.root.appendingPathComponent("clone")
        try runGit(["clone", setup.parent.path, clone.path], in: setup.root)
        try runGit(["config", "protocol.file.allow", "always"], in: clone)

        try await GitStatusService.shared.initializeSubmodule(path: "Packages/SharedKit", in: clone, credentialResolver: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: clone.appendingPathComponent("Packages/SharedKit/shared.txt").path))
    }

    func testUpdateSubmoduleToRecordedCommit() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        let checkout = setup.parent.appendingPathComponent("Packages/SharedKit")
        let original = try runGitCapture(["rev-parse", "HEAD"], in: checkout).trimmingCharacters(in: .whitespacesAndNewlines)
        try "next\n".write(to: setup.child.appendingPathComponent("next.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "next.txt"], in: setup.child)
        try runGit(["commit", "-m", "next"], in: setup.child)
        let next = try runGitCapture(["rev-parse", "HEAD"], in: setup.child).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["fetch"], in: checkout)
        try runGit(["checkout", next], in: checkout)
        try runGit(["add", "Packages/SharedKit"], in: setup.parent)
        try runGit(["checkout", original], in: checkout)

        try await GitStatusService.shared.updateSubmodule(path: "Packages/SharedKit", mode: .recordedCommit, in: setup.parent, credentialResolver: nil)

        XCTAssertEqual(try runGitCapture(["rev-parse", "HEAD"], in: checkout).trimmingCharacters(in: .whitespacesAndNewlines), next)
    }

    func testUpdateSubmoduleFromRemoteChecksOutLatestBranchCommit() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        try "next\n".write(to: setup.child.appendingPathComponent("next.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "next.txt"], in: setup.child)
        try runGit(["commit", "-m", "next"], in: setup.child)
        let next = try runGitCapture(["rev-parse", "HEAD"], in: setup.child).trimmingCharacters(in: .whitespacesAndNewlines)

        try await GitStatusService.shared.updateSubmodule(path: "Packages/SharedKit", mode: .remoteCheckout, in: setup.parent, credentialResolver: nil)

        let checkout = setup.parent.appendingPathComponent("Packages/SharedKit")
        XCTAssertEqual(try runGitCapture(["rev-parse", "HEAD"], in: checkout).trimmingCharacters(in: .whitespacesAndNewlines), next)
    }

    func testSynchronizeSubmoduleURLUpdatesLocalConfiguration() async throws {
        let setup = try makeParentWithCommittedSubmodule()
        let replacement = setup.root.appendingPathComponent("Replacement")
        try createRepository(at: replacement)
        try runGit(["config", "--file", ".gitmodules", "submodule.Packages/SharedKit.url", replacement.path], in: setup.parent)

        try await GitStatusService.shared.synchronizeSubmoduleURL(path: "Packages/SharedKit", in: setup.parent)

        XCTAssertEqual(try runGitCapture(["config", "--get", "submodule.Packages/SharedKit.url"], in: setup.parent), replacement.path + "\n")
    }

    func testCommandFailureIsPropagatedAndDoesNotPostNotification() async throws {
        let runner = RecordingSubmoduleRunner(error: GitError.commandFailed("sanitized failure"))
        let service = GitStatusService(runner: runner)
        let notification = expectation(description: "no repository notification")
        notification.isInverted = true
        let observer = NotificationCenter.default.addObserver(forName: .repositoryDidChange, object: nil, queue: .main) { _ in
            notification.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        do {
            try await service.synchronizeSubmoduleURL(path: "Packages/SharedKit", in: URL(fileURLWithPath: "/tmp/parent"))
            XCTFail("Expected command failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "sanitized failure")
        }
        await fulfillment(of: [notification], timeout: 0.2)
    }

    func testSuccessfulActionPostsRepositoryNotification() async throws {
        let runner = RecordingSubmoduleRunner()
        let service = GitStatusService(runner: runner)
        let repositoryURL = URL(fileURLWithPath: "/tmp/parent")
        let notification = expectation(forNotification: .repositoryDidChange, object: nil) { value in
            (value.userInfo?["repositoryURL"] as? URL) == repositoryURL
        }

        try await service.synchronizeSubmoduleURL(path: "Packages/SharedKit", in: repositoryURL)

        await fulfillment(of: [notification], timeout: 1)
    }

    func testAddWithForcePassesForceFlagToGit() async throws {
        let runner = RecordingSubmoduleRunner()
        let service = GitStatusService(runner: runner)
        let request = SubmoduleAddRequest(
            repository: "https://github.com/example/SharedKit.git",
            path: "Packages/SharedKit",
            branch: nil,
            initializeAfterAdd: true,
            shallow: false,
            force: true
        )

        try await service.addSubmodule(request, in: URL(fileURLWithPath: "/tmp/parent"), credentialResolver: nil)

        let calls = await runner.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].arguments, [
            "submodule", "add", "--force", "--",
            "https://github.com/example/SharedKit.git", "Packages/SharedKit"
        ])
    }

    func testForcedAddReusesStaleGitDirectory() async throws {
        let setup = try makeRepositories()
        try runGit(["submodule", "add", "--", setup.child.path, "package"], in: setup.parent)
        try runGit(["commit", "-am", "add package"], in: setup.parent)
        try runGit(["rm", "--", "package"], in: setup.parent)
        try runGit(["rm", "-f", "--", ".gitmodules"], in: setup.parent)
        try runGit(["commit", "-am", "remove package"], in: setup.parent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent(".git/modules/package").path))

        let request = SubmoduleAddRequest(
            repository: setup.child.path,
            path: "package",
            branch: nil,
            initializeAfterAdd: true,
            shallow: false,
            force: true
        )

        try await GitStatusService.shared.addSubmodule(request, in: setup.parent, credentialResolver: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.parent.appendingPathComponent("package/shared.txt").path))
    }

    func testAddWithoutForceFailsWhenGitDirectoryWouldBeReused() async throws {
        let setup = try makeRepositories()
        try runGit(["submodule", "add", "--", setup.child.path, "package"], in: setup.parent)
        try runGit(["commit", "-am", "add package"], in: setup.parent)
        try runGit(["rm", "--", "package"], in: setup.parent)
        try runGit(["rm", "-f", "--", ".gitmodules"], in: setup.parent)
        try runGit(["commit", "-am", "remove package"], in: setup.parent)
        let request = SubmoduleAddRequest(
            repository: setup.child.path,
            path: "package",
            branch: nil,
            initializeAfterAdd: true,
            shallow: false,
            force: false
        )

        do {
            try await GitStatusService.shared.addSubmodule(request, in: setup.parent, credentialResolver: nil)
            XCTFail("Expected reuse rejection without force")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("--force"))
        }
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

    private func createRepository(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: url)
        try runGit(["config", "user.name", "Commit Plus Tests"], in: url)
        try runGit(["config", "user.email", "tests@example.com"], in: url)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macgit-submodule-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
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

    private func makeCredentialResolver(token: String) -> GitProviderCredentialResolver {
        let account = GitProviderAccount(
            id: "account-1",
            macgitUID: "user-1",
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: "example",
            username: "example",
            displayName: "Example",
            avatarURL: nil,
            scopes: [],
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: Date(),
            lastValidatedAt: Date()
        )
        return GitProviderCredentialResolver(
            accounts: [account],
            tokenVault: SubmoduleTokenVault(accountID: account.id, token: GitProviderToken(accessToken: token, refreshToken: nil, expiresAt: nil, tokenType: "bearer"))
        )
    }
}

private actor RecordingSubmoduleRunner: GitCommandRunning {
    struct Call: Sendable {
        let arguments: [String]
        let environment: [String: String]?
    }

    private(set) var calls: [Call] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        calls.append(Call(arguments: arguments, environment: nil))
        if let error { throw error }
        return ""
    }

    func runGit(arguments: [String], in directory: URL, environment: [String: String]) async throws -> String {
        calls.append(Call(arguments: arguments, environment: environment))
        if let error { throw error }
        return ""
    }
}

private final class SubmoduleTokenVault: GitProviderTokenVault {
    private let accountID: String
    private let token: GitProviderToken

    init(accountID: String, token: GitProviderToken) {
        self.accountID = accountID
        self.token = token
    }

    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? {
        account.id == accountID ? token : nil
    }

    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {}
    func deleteToken(for account: GitProviderAccount) throws {}
}
