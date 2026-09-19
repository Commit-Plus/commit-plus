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

final class GitSubtreeOperationTests: XCTestCase {
    func testAddSubtreeWithoutSquashImportsFilesAndSavesRegistry() async throws {
        let setup = try makeRemoteAndParent()

        let entry = try await GitStatusService.shared.addSubtree(
            request(path: "Vendor/SharedKit", repository: setup.bare.path, squash: false),
            in: setup.parent,
            credentialResolver: nil,
            registry: GitSubtreeRegistry()
        )

        XCTAssertEqual(entry.path, "Vendor/SharedKit")
        XCTAssertFalse(entry.squash)
        XCTAssertEqual(
            try readFile("Vendor/SharedKit/shared.txt", in: setup.parent),
            "base\n"
        )
        let registryEntries = try await GitSubtreeRegistry().entries(in: setup.parent)
        XCTAssertEqual(registryEntries.map(\.path), ["Vendor/SharedKit"])
        XCTAssertFalse(try XCTUnwrap(registryEntries.first).squash)
    }

    func testAddSubtreeWithSquashRecordsSquashPolicy() async throws {
        let setup = try makeRemoteAndParent()

        let entry = try await GitStatusService.shared.addSubtree(
            request(path: "Vendor/SharedKit", repository: setup.bare.path, squash: true),
            in: setup.parent,
            credentialResolver: nil,
            registry: GitSubtreeRegistry()
        )

        XCTAssertTrue(entry.squash)
        let registryEntries = try await GitSubtreeRegistry().entries(in: setup.parent)
        XCTAssertEqual(registryEntries.first?.squash, true)
    }

    func testPullSubtreeImportsUpstreamChange() async throws {
        let setup = try makeRemoteAndParent()
        let entry = try await GitStatusService.shared.addSubtree(
            request(path: "Vendor/SharedKit", repository: setup.bare.path, squash: false),
            in: setup.parent,
            credentialResolver: nil,
            registry: GitSubtreeRegistry()
        )
        try "next\n".write(to: setup.source.appendingPathComponent("next.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "next.txt"], in: setup.source)
        try runGit(["commit", "-m", "next"], in: setup.source)
        try runGit(["push", "origin", "main"], in: setup.source)

        try await GitStatusService.shared.pullSubtree(entry, in: setup.parent, credentialResolver: nil)

        XCTAssertEqual(try readFile("Vendor/SharedKit/next.txt", in: setup.parent), "next\n")
    }

    func testPushSubtreePublishesPrefixChange() async throws {
        let setup = try makeRemoteAndParent()
        let entry = try await GitStatusService.shared.addSubtree(
            request(path: "Vendor/SharedKit", repository: setup.bare.path, squash: false),
            in: setup.parent,
            credentialResolver: nil,
            registry: GitSubtreeRegistry()
        )
        try "parent change\n".write(
            to: setup.parent.appendingPathComponent("Vendor/SharedKit/parent.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "Vendor/SharedKit/parent.txt"], in: setup.parent)
        try runGit(["commit", "-m", "parent subtree change"], in: setup.parent)

        try await GitStatusService.shared.pushSubtree(entry, in: setup.parent, credentialResolver: nil)

        XCTAssertEqual(
            try runGit(["--git-dir", setup.bare.path, "show", "main:parent.txt"], in: setup.root),
            "parent change\n"
        )
    }

    func testAddSubtreeRejectsUnavailableCapabilityBeforeSavingRegistry() async throws {
        let runner = RecordingSubtreeOperationRunner(failures: [
            "subtree -h": GitError.commandFailed("git: 'subtree' is not a git command")
        ])
        let registry = RecordingSubtreeRegistry()
        let service = GitStatusService(runner: runner)

        await XCTAssertThrowsErrorAsync({
            try await service.addSubtree(
                request(),
                in: URL(fileURLWithPath: "/tmp/repo"),
                credentialResolver: nil,
                registry: registry
            )
        }) { error in
            XCTAssertEqual(error.localizedDescription, "This Git installation does not include git subtree.")
        }
        let savedEntries = await registry.savedEntries()
        let calls = await runner.recordedArguments()
        XCTAssertEqual(savedEntries, [])
        XCTAssertEqual(calls, [["subtree", "-h"]])
    }

    func testAddSubtreeRejectsDirtyParentBeforeMutationAndRegistrySave() async throws {
        let runner = RecordingSubtreeOperationRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": " M dirty.txt\0"
        ])
        let registry = RecordingSubtreeRegistry()
        let service = GitStatusService(runner: runner)

        await XCTAssertThrowsErrorAsync({
            try await service.addSubtree(
                request(),
                in: URL(fileURLWithPath: "/tmp/repo"),
                credentialResolver: nil,
                registry: registry
            )
        }) { error in
            XCTAssertEqual(error.localizedDescription, "Commit, stash, or discard changes before running subtree operations.")
        }
        let savedEntries = await registry.savedEntries()
        let calls = await runner.recordedArguments()
        XCTAssertEqual(savedEntries, [])
        XCTAssertEqual(calls, [["subtree", "-h"], ["status", "--porcelain=v1", "-z"]])
    }

    func testCommandFailureDoesNotSaveRegistryOrPostNotification() async throws {
        let repository = URL(fileURLWithPath: "/tmp/repo")
        let runner = RecordingSubtreeOperationRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": ""
        ], failures: [
            "subtree add --prefix=Vendor/SharedKit https://example.com/shared.git main": GitError.commandFailed("remote rejected")
        ])
        let registry = RecordingSubtreeRegistry()
        let notification = invertedRepositoryNotificationExpectation(repositoryURL: repository)
        let service = GitStatusService(runner: runner)

        await XCTAssertThrowsErrorAsync({
            try await service.addSubtree(
                request(),
                in: repository,
                credentialResolver: nil,
                registry: registry
            )
        }) { error in
            XCTAssertEqual(error.localizedDescription, "remote rejected")
        }

        await fulfillment(of: [notification.expectation], timeout: 0.2)
        NotificationCenter.default.removeObserver(notification.observer)
        let savedEntries = await registry.savedEntries()
        XCTAssertEqual(savedEntries, [])
    }

    func testSuccessfulAddSavesRegistryAndPostsNotificationAfterSave() async throws {
        let repository = URL(fileURLWithPath: "/tmp/repo")
        let runner = RecordingSubtreeOperationRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": "",
            "subtree add --prefix=Vendor/SharedKit https://example.com/shared.git main": ""
        ])
        let registry = RecordingSubtreeRegistry()
        let notification = expectation(forNotification: .repositoryDidChange, object: nil) { value in
            (value.userInfo?["repositoryURL"] as? URL) == repository
        }
        let service = GitStatusService(runner: runner)

        let entry = try await service.addSubtree(
            request(),
            in: repository,
            credentialResolver: nil,
            registry: registry
        )

        await fulfillment(of: [notification], timeout: 1.0)
        XCTAssertEqual(entry.path, "Vendor/SharedKit")
        let savedPaths = await registry.savedEntries().map(\.path)
        XCTAssertEqual(savedPaths, ["Vendor/SharedKit"])
    }

    func testAddSubtreeUsesCredentialEnvironmentWithoutTokenArguments() async throws {
        let repository = URL(fileURLWithPath: "/tmp/repo")
        let token = "secret-subtree-token"
        let remote = "https://github.com/example/shared.git"
        let runner = RecordingSubtreeOperationRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": "",
            "subtree add --prefix=Vendor/SharedKit \(remote) main": ""
        ])
        let service = GitStatusService(runner: runner)

        _ = try await service.addSubtree(
            request(repository: remote),
            in: repository,
            credentialResolver: makeCredentialResolver(token: token),
            registry: RecordingSubtreeRegistry()
        )

        let calls = await runner.recordedArguments()
        let environments = await runner.recordedEnvironments()
        let addEnvironment = try XCTUnwrap(environments.last ?? nil)
        XCTAssertEqual(
            calls.last,
            ["subtree", "add", "--prefix=Vendor/SharedKit", remote, "main"]
        )
        XCTAssertFalse(calls.flatMap { $0 }.contains { $0.contains(token) })
        XCTAssertEqual(addEnvironment["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertNotNil(addEnvironment["GIT_ASKPASS"])
        XCTAssertFalse(addEnvironment.values.contains { $0.contains(token) })
    }

    func testAddSubtreeRejectsExistingNonEmptyPrefixBeforeMutation() async throws {
        let repository = try makeTemporaryDirectory()
        let prefix = repository.appendingPathComponent("Vendor/SharedKit", isDirectory: true)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try "leftover\n".write(to: prefix.appendingPathComponent("kept.txt"), atomically: true, encoding: .utf8)
        let runner = RecordingSubtreeOperationRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": ""
        ])
        let registry = RecordingSubtreeRegistry()
        let service = GitStatusService(runner: runner)

        await XCTAssertThrowsErrorAsync({
            try await service.addSubtree(
                request(),
                in: repository,
                credentialResolver: nil,
                registry: registry
            )
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .prefixAlreadyExists("Vendor/SharedKit"))
        }
        let savedEntries = await registry.savedEntries()
        let calls = await runner.recordedArguments()
        XCTAssertEqual(savedEntries, [])
        XCTAssertEqual(calls, [["subtree", "-h"], ["status", "--porcelain=v1", "-z"]])
    }

    func testAddSubtreeRemovesEmptyPrefixFolderAndSucceeds() async throws {
        let repository = try makeTemporaryDirectory()
        let prefix = repository.appendingPathComponent("Vendor/SharedKit", isDirectory: true)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let runner = RecordingSubtreeOperationRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": "",
            "subtree add --prefix=Vendor/SharedKit https://example.com/shared.git main": ""
        ])
        let registry = RecordingSubtreeRegistry()
        let service = GitStatusService(runner: runner)

        let entry = try await service.addSubtree(
            request(),
            in: repository,
            credentialResolver: nil,
            registry: registry
        )

        XCTAssertEqual(entry.path, "Vendor/SharedKit")
        XCTAssertFalse(FileManager.default.fileExists(atPath: prefix.path))
        let savedPaths = await registry.savedEntries().map(\.path)
        XCTAssertEqual(savedPaths, ["Vendor/SharedKit"])
    }

    func testAddSubtreeRejectsInvalidLocalRepository() async throws {
        let repository = try makeTemporaryDirectory()
        let notARepo = repository.appendingPathComponent("not-a-repo-\(UUID().uuidString)", isDirectory: true)
        let runner = RecordingSubtreeOperationRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": ""
        ])
        let registry = RecordingSubtreeRegistry()
        let service = GitStatusService(runner: runner)

        await XCTAssertThrowsErrorAsync({
            try await service.addSubtree(
                request(repository: notARepo.path),
                in: repository,
                credentialResolver: nil,
                registry: registry
            )
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .invalidLocalRepository)
        }
        let savedAfterReject = await registry.savedEntries()
        XCTAssertEqual(savedAfterReject, [])
    }

    func testAddSubtreeAllowsFileProtocolForLocalRepository() async throws {
        let repository = try makeTemporaryDirectory()
        let upstream = repository.appendingPathComponent("upstream", isDirectory: true)
        try FileManager.default.createDirectory(
            at: upstream.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let runner = RecordingSubtreeOperationRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": "",
            "subtree add --prefix=Vendor/SharedKit \(upstream.path) main": ""
        ])
        let service = GitStatusService(runner: runner)

        _ = try await service.addSubtree(
            request(repository: upstream.path),
            in: repository,
            credentialResolver: nil,
            registry: RecordingSubtreeRegistry()
        )

        let environments = await runner.recordedEnvironments()
        XCTAssertEqual(environments.count, 3)
        XCTAssertEqual(environments[2]?["GIT_ALLOW_PROTOCOL"], "file")
    }

    private func request(
        name: String = "SharedKit",
        path: String = "Vendor/SharedKit",
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

    private func makeRemoteAndParent() throws -> (root: URL, source: URL, bare: URL, parent: URL) {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("source", isDirectory: true)
        let bare = root.appendingPathComponent("remote.git", isDirectory: true)
        let parent = root.appendingPathComponent("parent", isDirectory: true)

        try createRepository(at: source)
        try "base\n".write(to: source.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "shared.txt"], in: source)
        try runGit(["commit", "-m", "base"], in: source)
        try runGit(["init", "--bare", "--initial-branch=main", bare.path], in: root)
        try runGit(["remote", "add", "origin", bare.path], in: source)
        try runGit(["push", "-u", "origin", "main"], in: source)

        try createRepository(at: parent)
        try "parent\n".write(to: parent.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: parent)
        try runGit(["commit", "-m", "parent base"], in: parent)

        return (root, source, bare, parent)
    }

    private func createRepository(at repository: URL) throws {
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repository)
        try runGit(["config", "user.name", "Commit Plus Tests"], in: repository)
        try runGit(["config", "user.email", "tests@example.com"], in: repository)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-subtree-operations-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func readFile(_ path: String, in repository: URL) throws -> String {
        try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
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
            tokenVault: SubtreeOperationTokenVault(
                accountID: account.id,
                token: GitProviderToken(
                    accessToken: token,
                    refreshToken: nil,
                    expiresAt: nil,
                    tokenType: "bearer"
                )
            )
        )
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

    private func invertedRepositoryNotificationExpectation(repositoryURL: URL) -> (expectation: XCTestExpectation, observer: NSObjectProtocol) {
        let expectation = expectation(description: "repositoryDidChange not posted")
        expectation.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: .repositoryDidChange,
            object: nil,
            queue: nil
        ) { notification in
            if (notification.userInfo?["repositoryURL"] as? URL) == repositoryURL {
                expectation.fulfill()
            }
        }
        return (expectation, observer)
    }
}

private actor RecordingSubtreeOperationRunner: GitCommandRunning {
    private let outputs: [String: String]
    private let failures: [String: Error]
    private var calls: [[String]] = []
    private var environments: [[String: String]?] = []

    init(outputs: [String: String] = [:], failures: [String: Error] = [:]) {
        self.outputs = outputs
        self.failures = failures
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        calls.append(arguments)
        environments.append(nil)
        let key = arguments.joined(separator: " ")
        if let failure = failures[key] {
            throw failure
        }
        return outputs[key] ?? ""
    }

    func runGit(arguments: [String], in directory: URL, environment: [String: String]) async throws -> String {
        calls.append(arguments)
        environments.append(environment)
        let key = arguments.joined(separator: " ")
        if let failure = failures[key] {
            throw failure
        }
        return outputs[key] ?? ""
    }

    func recordedArguments() -> [[String]] {
        calls
    }

    func recordedEnvironments() -> [[String: String]?] {
        environments
    }
}

private actor RecordingSubtreeRegistry: GitSubtreeRegistryProtocol {
    private var entries: [GitSubtreeEntry] = []

    func entries(in repositoryURL: URL) async throws -> [GitSubtreeEntry] {
        entries
    }

    func save(_ entry: GitSubtreeEntry, in repositoryURL: URL) async throws {
        entries.append(entry)
    }

    func remove(id: String, in repositoryURL: URL) async throws {
        entries.removeAll { $0.id == id }
    }

    func savedEntries() -> [GitSubtreeEntry] {
        entries
    }
}

private final class SubtreeOperationTokenVault: GitProviderTokenVault {
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
