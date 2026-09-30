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

final class GitRuntimeManagerTests: XCTestCase {
    func testAutomaticPreferenceUsesSystemBeforeEmbedded() async throws {
        let fixture = try makeFixture()
        try createExecutable(at: fixture.systemGitURL)
        try createExecutable(at: fixture.embeddedGitURL)
        let manager = fixture.manager(
            runner: TestGitRuntimeRunner(
                versions: [
                    fixture.systemGitURL: "git version 2.50.0",
                    fixture.embeddedGitURL: "git version 2.53.0"
                ]
            )
        )

        let status = await manager.status()
        let executableURL = try await manager.executableURL()

        XCTAssertEqual(status.preference, .automatic)
        XCTAssertEqual(status.activeRuntime?.executableURL, fixture.systemGitURL)
        XCTAssertEqual(executableURL, fixture.systemGitURL)
    }

    func testConcurrentStatusRequestsShareRuntimeDiscovery() async throws {
        let fixture = try makeFixture()
        try createExecutable(at: fixture.systemGitURL)
        try createExecutable(at: fixture.embeddedGitURL)
        let runner = CountingGitRuntimeRunner(
            versions: [
                fixture.systemGitURL: "git version 2.50.0",
                fixture.embeddedGitURL: "git version 2.53.0"
            ]
        )
        let manager = fixture.manager(runner: runner)

        async let firstStatus = manager.status()
        async let secondStatus = manager.status()
        async let executableURL = manager.executableURL()
        let (first, second, executable) = try await (firstStatus, secondStatus, executableURL)
        let systemCallCount = await runner.callCount(for: fixture.systemGitURL)
        let embeddedCallCount = await runner.callCount(for: fixture.embeddedGitURL)

        XCTAssertEqual(first.activeRuntime, second.activeRuntime)
        XCTAssertEqual(executable, fixture.systemGitURL)
        XCTAssertEqual(systemCallCount, 1)
        XCTAssertEqual(embeddedCallCount, 1)
    }

    func testEmbeddedPreferenceOverridesAvailableSystemGit() async throws {
        let fixture = try makeFixture()
        try createExecutable(at: fixture.systemGitURL)
        try createExecutable(at: fixture.embeddedGitURL)
        let manager = fixture.manager(
            runner: TestGitRuntimeRunner(
                versions: [
                    fixture.systemGitURL: "git version 2.50.0",
                    fixture.embeddedGitURL: "git version 2.53.0"
                ]
            )
        )

        try await manager.setPreference(.embedded)
        let executableURL = try await manager.executableURL()
        let status = await manager.status()

        XCTAssertEqual(executableURL, fixture.embeddedGitURL)
        XCTAssertEqual(status.preference, .embedded)
    }

    func testCannotSelectEmbeddedGitBeforeItIsInstalled() async throws {
        let fixture = try makeFixture()
        try createExecutable(at: fixture.systemGitURL)
        let manager = fixture.manager(
            runner: TestGitRuntimeRunner(
                versions: [fixture.systemGitURL: "git version 2.50.0"]
            )
        )

        do {
            try await manager.setPreference(.embedded)
            XCTFail("Expected missing Embedded Git.")
        } catch let error as GitRuntimeError {
            XCTAssertEqual(error, .missingEmbeddedGit)
        }

        let status = await manager.status()
        XCTAssertEqual(status.preference, .automatic)
    }

    func testInstallRejectsArchiveWithWrongChecksum() async throws {
        let fixture = try makeFixture(sha256: String(repeating: "0", count: 64))
        let archiveURL = fixture.rootURL.appendingPathComponent("download.tar.gz")
        try Data().write(to: archiveURL)
        let manager = fixture.manager(
            runner: TestGitRuntimeRunner(versions: [:]),
            downloader: TestGitRuntimeDownloader(archiveURL: archiveURL)
        )

        do {
            try await manager.installEmbeddedRuntime()
            XCTFail("Expected checksum mismatch.")
        } catch let error as GitRuntimeError {
            XCTAssertEqual(error, .checksumMismatch)
        }
    }

    func testEmbeddedEnvironmentUsesRuntimeSubcommandsAndTemplates() async throws {
        let fixture = try makeFixture()
        try createExecutable(at: fixture.embeddedGitURL)
        let manager = fixture.manager(
            runner: TestGitRuntimeRunner(
                versions: [fixture.embeddedGitURL: "git version 2.53.0"]
            )
        )
        try await manager.setPreference(.embedded)
        let executableURL = try await manager.executableURL()

        let environment = await manager.environment(
            for: executableURL,
            inheriting: ["PATH": "/usr/bin"]
        )

        let embeddedRoot = fixture.embeddedGitURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        XCTAssertEqual(
            environment["GIT_EXEC_PATH"],
            embeddedRoot.appendingPathComponent("libexec/git-core").path
        )
        XCTAssertEqual(
            environment["GIT_TEMPLATE_DIR"],
            embeddedRoot.appendingPathComponent("share/git-core/templates").path
        )
        XCTAssertTrue(environment["PATH"]?.hasPrefix("\(embeddedRoot.path)/bin:") == true)
    }

    private func makeFixture(
        sha256: String = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ) throws -> GitRuntimeTestFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GitRuntimeManagerTests.\(UUID().uuidString)"))
        defaults.removePersistentDomain(forName: "GitRuntimeManagerTests")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return GitRuntimeTestFixture(
            rootURL: rootURL,
            defaults: defaults,
            manifest: GitRuntimeManifest(
                version: "2.53.0",
                platform: "macos-test",
                url: URL(string: "https://example.invalid/embedded-git.tar.gz")!,
                sha256: sha256,
                archiveSize: 0
            )
        )
    }

    private func createExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}

private struct GitRuntimeTestFixture {
    let rootURL: URL
    let defaults: UserDefaults
    let manifest: GitRuntimeManifest

    var supportURL: URL {
        rootURL.appendingPathComponent("Application Support", isDirectory: true)
    }

    var systemGitURL: URL {
        rootURL.appendingPathComponent("system/git")
    }

    var embeddedGitURL: URL {
        supportURL
            .appendingPathComponent("Commit+/Git/2.53.0-macos-test/bin/git")
    }

    func manager(
        runner: any GitRuntimeProcessRunning,
        downloader: any GitRuntimeDownloading = FailingGitRuntimeDownloader()
    ) -> GitRuntimeManager {
        GitRuntimeManager(
            configuration: GitRuntimeConfiguration(
                applicationSupportDirectory: supportURL,
                candidateSystemGitURLs: [systemGitURL],
                manifest: manifest,
                preferenceDefaults: defaults,
                preferenceKey: "preference"
            ),
            processRunner: runner,
            downloader: downloader,
            extractor: TestGitRuntimeExtractor()
        )
    }
}

private struct TestGitRuntimeRunner: GitRuntimeProcessRunning {
    let versions: [URL: String]

    func version(at executableURL: URL) async throws -> String {
        guard let version = versions[executableURL] else {
            throw GitRuntimeError.validationFailed(executableURL.path)
        }
        return version
    }
}

private actor CountingGitRuntimeRunner: GitRuntimeProcessRunning {
    let versions: [URL: String]
    private var callCounts: [URL: Int] = [:]

    init(versions: [URL: String]) {
        self.versions = versions
    }

    func version(at executableURL: URL) async throws -> String {
        callCounts[executableURL, default: 0] += 1
        try await Task.sleep(for: .milliseconds(50))
        guard let version = versions[executableURL] else {
            throw GitRuntimeError.validationFailed(executableURL.path)
        }
        return version
    }

    func callCount(for executableURL: URL) -> Int {
        callCounts[executableURL, default: 0]
    }
}

private struct TestGitRuntimeDownloader: GitRuntimeDownloading {
    let archiveURL: URL

    func download(from url: URL) async throws -> URL {
        archiveURL
    }
}

private struct FailingGitRuntimeDownloader: GitRuntimeDownloading {
    func download(from url: URL) async throws -> URL {
        throw GitRuntimeError.downloadFailed("Unexpected test download.")
    }
}

private struct TestGitRuntimeExtractor: GitRuntimeExtracting {
    func extract(archiveURL: URL, to destinationURL: URL) throws {}
}
