// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class CopilotLanguageServerRuntimeTests: XCTestCase {
    func testCachedServerIsUsedWithoutDownloading() async throws {
        let fixture = try makeFixture()
        try createExecutable(at: fixture.serverURL)
        let downloader = CountingCopilotDownloader(result: .failure(GitRuntimeError.downloadFailed("unused")))
        let runtime = fixture.runtime(
            versions: [fixture.serverURL: "1.560.0\n"],
            downloader: downloader
        )

        let executableURL = try await runtime.executableURL()
        let isInstalled = await runtime.isInstalled()
        let downloadCount = await downloader.count

        XCTAssertEqual(executableURL, fixture.serverURL)
        XCTAssertTrue(isInstalled)
        XCTAssertEqual(downloadCount, 0)
    }

    func testCachedServerWithWrongVersionIsNotUsed() async throws {
        let fixture = try makeFixture()
        try createExecutable(at: fixture.serverURL)
        let runtime = fixture.runtime(
            versions: [fixture.serverURL: "1.559.0\n"],
            downloader: CountingCopilotDownloader(result: .failure(GitRuntimeError.downloadFailed("offline")))
        )

        let isInstalled = await runtime.isInstalled()

        XCTAssertFalse(isInstalled)
    }

    func testChecksumMismatchIsReportedAsVerificationFailure() async throws {
        let fixture = try makeFixture(sha256: String(repeating: "0", count: 64))
        let archiveURL = fixture.rootURL.appendingPathComponent("server.tgz")
        try Data().write(to: archiveURL)
        let runtime = fixture.runtime(
            versions: [:],
            downloader: CountingCopilotDownloader(result: .success(archiveURL))
        )

        do {
            _ = try await runtime.executableURL()
            XCTFail("Expected a verification failure.")
        } catch let error as CopilotLanguageServerRuntimeError {
            XCTAssertEqual(error, .verificationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.serverURL.path))
    }

    func testDownloadFailureOffersRetry() async throws {
        let fixture = try makeFixture()
        let runtime = fixture.runtime(
            versions: [:],
            downloader: CountingCopilotDownloader(result: .failure(GitRuntimeError.downloadFailed("The network connection was lost.")))
        )

        do {
            _ = try await runtime.executableURL()
            XCTFail("Expected a download failure.")
        } catch let error as CopilotLanguageServerRuntimeError {
            XCTAssertEqual(error, .downloadFailed("The network connection was lost."))
            XCTAssertTrue(error.localizedDescription.hasSuffix("Try again."))
        }
    }

    func testArchiveListingRejectsPathsOutsidePackage() {
        XCTAssertNoThrow(try CopilotLanguageServerArchiveExtractor.validateListing(
            "package/copilot-language-server\npackage/package.json\n"
        ))
        XCTAssertThrowsError(try CopilotLanguageServerArchiveExtractor.validateListing("package/../evil\n"))
        XCTAssertThrowsError(try CopilotLanguageServerArchiveExtractor.validateListing("/usr/local/bin/evil\n"))
        XCTAssertThrowsError(try CopilotLanguageServerArchiveExtractor.validateListing("other/file\n"))
    }

    func testManifestPinsServerVersionAndRegistryURL() {
        let manifest = CopilotLanguageServerRuntime.manifest

        XCTAssertEqual(manifest.version, "1.560.0")
        XCTAssertEqual(manifest.url.host(), "registry.npmjs.org")
        XCTAssertTrue(manifest.url.lastPathComponent.hasSuffix("-1.560.0.tgz"))
        XCTAssertEqual(manifest.sha256.count, 64)
    }

    private func makeFixture(
        sha256: String = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ) throws -> CopilotRuntimeFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-copilot-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CopilotLanguageServerRuntimeTests.\(UUID().uuidString)"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let live = CopilotLanguageServerRuntime.manifest
        return CopilotRuntimeFixture(
            rootURL: rootURL,
            defaults: defaults,
            manifest: GitRuntimeManifest(
                version: live.version,
                platform: "macos-test",
                url: URL(string: "https://example.invalid/server.tgz")!,
                sha256: sha256,
                archiveSize: 0
            )
        )
    }

    private func createExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private struct CopilotRuntimeFixture {
    let rootURL: URL
    let defaults: UserDefaults
    let manifest: GitRuntimeManifest

    var supportURL: URL {
        rootURL.appendingPathComponent("Application Support", isDirectory: true)
    }

    var serverURL: URL {
        supportURL.appendingPathComponent(
            "Commit+/GitHubCopilot/LanguageServer/\(manifest.version)-macos-test/package/copilot-language-server"
        )
    }

    func runtime(versions: [URL: String], downloader: any GitRuntimeDownloading) -> CopilotLanguageServerRuntime {
        let live = CopilotLanguageServerRuntime.configuration(
            applicationSupportDirectory: supportURL,
            preferenceDefaults: defaults
        )
        let configuration = GitRuntimeConfiguration(
            applicationSupportDirectory: live.applicationSupportDirectory,
            candidateSystemGitURLs: live.candidateSystemGitURLs,
            manifest: manifest,
            preferenceDefaults: live.preferenceDefaults,
            preferenceKey: live.preferenceKey,
            managedDirectoryName: live.managedDirectoryName,
            executableRelativePath: live.executableRelativePath,
            versionPrefix: live.versionPrefix
        )
        return CopilotLanguageServerRuntime(
            manager: GitRuntimeManager(
                configuration: configuration,
                processRunner: CopilotVersionRunner(versions: versions),
                downloader: downloader,
                extractor: NoopCopilotExtractor()
            )
        )
    }
}

private struct CopilotVersionRunner: GitRuntimeProcessRunning {
    let versions: [URL: String]

    func version(at executableURL: URL) async throws -> String {
        guard let version = versions[executableURL] else {
            throw GitRuntimeError.validationFailed(executableURL.path)
        }
        return version
    }
}

private final class CountingCopilotDownloader: GitRuntimeDownloading {
    let result: Result<URL, Error>
    private(set) var count = 0

    init(result: Result<URL, Error>) {
        self.result = result
    }

    func download(from url: URL) async throws -> URL {
        count += 1
        return try result.get()
    }
}

private struct NoopCopilotExtractor: GitRuntimeExtracting {
    func extract(archiveURL: URL, to destinationURL: URL) throws {}
}
