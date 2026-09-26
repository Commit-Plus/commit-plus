// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class GitLFSRuntimeTests: XCTestCase {
    func testMissingRuntimePreservesGitLookup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lfs-missing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "lfs-missing-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = GitRuntimeConfiguration(applicationSupportDirectory: root, candidateSystemGitURLs: [],
            manifest: GitLFSRuntime.manifest, preferenceDefaults: defaults, preferenceKey: "lfsPreference",
            managedDirectoryName: "GitLFS", executableRelativePath: "git-lfs-3.8.0/git-lfs", versionPrefix: "git-lfs/")
        let manager = GitRuntimeManager(configuration: configuration, processRunner: GitLFSVersionRunner())
        let commands = root.appendingPathComponent("commands")
        let runtime = GitLFSRuntime(manager: manager, commandDirectory: commands)
        let environment = ["PATH": "/usr/bin:/bin", "GIT_EXEC_PATH": "/nonexistent/git-core"]
        let resolved = try await runtime.environment(inheriting: environment)
        XCTAssertEqual(resolved, environment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: commands.path))
        do {
            _ = try await runtime.executable()
            XCTFail("Explicit LFS operations must still report the missing runtime")
        } catch {}
    }

    func testMetadataExecutionDoesNotProbeLFS() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lfs-metadata-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "lfs-metadata-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let gitManager = GitRuntimeManager(configuration: GitRuntimeConfiguration(
            applicationSupportDirectory: root, candidateSystemGitURLs: [URL(fileURLWithPath: "/usr/bin/git")],
            manifest: .current, preferenceDefaults: defaults, preferenceKey: "gitPreference"))
        let runner = CountingLFSVersionRunner()
        let lfsManager = GitRuntimeManager(configuration: GitRuntimeConfiguration(
            applicationSupportDirectory: root, candidateSystemGitURLs: [URL(fileURLWithPath: "/bin/sh")],
            manifest: GitLFSRuntime.manifest, preferenceDefaults: defaults, preferenceKey: "lfsPreference",
            managedDirectoryName: "GitLFS", executableRelativePath: "git-lfs-3.8.0/git-lfs", versionPrefix: "git-lfs/"),
            processRunner: runner)
        let commands = root.appendingPathComponent("commands")
        let runtime = GitLFSRuntime(manager: lfsManager, commandDirectory: commands)
        let service = GitStatusService(runtimeManager: gitManager, lfsRuntime: runtime)
        // Exercise both production process paths, without a mock Git command runner.
        let arguments = ["check-ref-format", "refs/heads/topic"]
        let output = try await service.runGit(arguments: arguments, in: root)
        XCTAssertEqual(output, "")
        let bounded = try await service.runGitBounded(arguments: arguments, in: root,
            environment: ProcessInfo.processInfo.environment, outputByteLimit: 1024)
        XCTAssertEqual(bounded.text, "")
        let count = await runner.count
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: commands.path))

        _ = try await runtime.executable()
        let resolvedCount = await runner.count
        XCTAssertEqual(resolvedCount, 1, "LFS must still resolve when explicitly requested")
    }

    func testConcurrentStartupReadsShareOneRuntimeProbe() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lfs-startup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "lfs-startup-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runner = CountingLFSVersionRunner()
        let executable = URL(fileURLWithPath: "/bin/sh")
        let configuration = GitRuntimeConfiguration(applicationSupportDirectory: root, candidateSystemGitURLs: [executable],
            manifest: GitLFSRuntime.manifest, preferenceDefaults: defaults, preferenceKey: "lfsPreference",
            managedDirectoryName: "GitLFS", executableRelativePath: "git-lfs-3.8.0/git-lfs", versionPrefix: "git-lfs/")
        let manager = GitRuntimeManager(configuration: configuration, processRunner: runner)
        let runtime = GitLFSRuntime(manager: manager, commandDirectory: root.appendingPathComponent("commands"))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<32 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        _ = try await runtime.environment(inheriting: ["PATH": "/usr/bin:/bin"])
                    } else {
                        _ = try await runtime.executable()
                    }
                }
            }
            try await group.waitForAll()
        }
        let startupCount = await runner.count
        XCTAssertEqual(startupCount, 1, "Concurrent Welcome reads should share the first LFS probe")
        _ = try await runtime.executable()
        let cachedCount = await runner.count
        XCTAssertEqual(cachedCount, 1)

        _ = await runtime.status()
        let refreshedCount = await runner.count
        XCTAssertEqual(refreshedCount, 2, "Explicit Settings refresh must still probe again")
    }

    func testEmbeddedInstallVerifiesAndSelectsPrivateRuntime() async throws {
        guard let source = ProcessInfo.processInfo.environment["COMMITPLUS_TEST_LFS_ARCHIVE"] else {
            throw XCTSkip("Set COMMITPLUS_TEST_LFS_ARCHIVE to the official archive for this architecture.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lfs-install-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lfs-install-\(UUID())"))
        let configuration = GitRuntimeConfiguration(applicationSupportDirectory: root, candidateSystemGitURLs: [],
            manifest: GitLFSRuntime.manifest, preferenceDefaults: defaults, preferenceKey: "lfsPreference",
            managedDirectoryName: "GitLFS", executableRelativePath: "git-lfs-3.8.0/git-lfs", versionPrefix: "git-lfs/")
        let manager = GitRuntimeManager(configuration: configuration, processRunner: GitLFSVersionRunner(),
            downloader: LFSFixtureDownloader(source: URL(fileURLWithPath: source)), extractor: GitLFSArchiveExtractor())
        let runtime = GitLFSRuntime(manager: manager, commandDirectory: root.appendingPathComponent("commands"))
        let before = await runtime.status()
        XCTAssertNil(before.activeRuntime)
        try await runtime.install()
        let status = await runtime.status()
        XCTAssertEqual(status.preference, .embedded)
        XCTAssertTrue(status.activeRuntime?.version.hasPrefix("git-lfs/3.8.0") == true)
        XCTAssertTrue(status.activeRuntime?.executableURL.path.hasPrefix(root.path) == true)
        XCTAssertNil(defaults.string(forKey: "gitRuntimePreference"))
        do { try await runtime.select(.system); XCTFail("Missing system runtime must not silently fall back") } catch {}
        let after = await runtime.status()
        XCTAssertEqual(after.preference, .embedded)
    }
}

private struct LFSFixtureDownloader: GitRuntimeDownloading {
    let source: URL
    func download(from url: URL) async throws -> URL {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("lfs-archive-\(UUID()).zip")
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }
}

private actor CountingLFSVersionRunner: GitRuntimeProcessRunning {
    private(set) var count = 0

    func version(at executableURL: URL) async throws -> String {
        count += 1
        // Keep discovery suspended while the other startup callers enter the actor.
        try await Task.sleep(for: .milliseconds(50))
        return "git-lfs/3.8.0"
    }
}
