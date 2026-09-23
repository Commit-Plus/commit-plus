// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class GitLFSRuntimeTests: XCTestCase {
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
