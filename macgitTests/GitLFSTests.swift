// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class GitLFSTests: XCTestCase {
    func testMetadataCommandsDoNotRequireLFSRuntime() {
        for arguments in [
            ["branch", "--show-current"], ["remote", "get-url", "origin"],
            ["config", "user.email"], ["rev-parse", "--git-dir"],
            ["rev-list", "--count", "--left-right", "HEAD...@{upstream}"],
            ["log", "--all", "--format=%H%x09%ae%x09%ct", "--no-patch"]
        ] {
            XCTAssertFalse(GitStatusService.requiresLFSRuntime(arguments: arguments), "\(arguments)")
        }
    }

    func testFiltersHooksAndUnknownCommandsRetainLFSRuntime() {
        for arguments in [
            ["status", "--porcelain"], ["add", "file.dat"], ["checkout", "main"],
            ["push", "origin"], ["commit", "-m", "message"], ["lfs", "env"],
            ["diff"], ["show", "HEAD:file.dat"], ["log", "-p"],
            ["log", "--no-patch", "-p"], ["log", "-p", "--", "--no-patch"],
            ["-c", "alias.custom=status", "custom"], ["branch", "-D", "topic"], []
        ] {
            XCTAssertTrue(GitStatusService.requiresLFSRuntime(arguments: arguments), "\(arguments)")
        }
    }

    @MainActor
    func testDownloadCredentialCallbackPreservesMainActorAcrossSuspension() async {
        var requestedRemote: String?
        let view = GitLFSView(repositoryURL: URL(fileURLWithPath: "/tmp/lfs-callback-test"),
            credentialResolver: { @MainActor remote in
                MainActor.assertIsolated()
                await Task.yield()
                MainActor.assertIsolated()
                requestedRemote = remote
                return nil
            }, refreshRepository: {}, authorizeAction: { true })
        let result = await view.credentialResolver("origin")
        XCTAssertNil(result)
        XCTAssertEqual(requestedRemote, "origin")
    }

    func testProgressParsesByteCountsAndNamesWithSpaces() {
        let progress = GitLFSTransferProgress("download 2/3 512/1024 Assets/large file.dat")
        XCTAssertEqual(progress?.fileIndex, 2)
        XCTAssertEqual(progress?.bytes, 512)
        XCTAssertEqual(progress?.name, "Assets/large file.dat")
        XCTAssertNil(GitLFSTransferProgress("download 1/1 100/0 bad"))
        XCTAssertNil(GitLFSTransferProgress("arbitrary error output"))
    }

    func testTrackingRulePresentationPreservesSourceAndExclusions() {
        let rules = GitLFSTrackingRule.displayRules("Listing tracked patterns\n    *.psd (.gitattributes)\n    art/*.dat (nested/.gitattributes)\nListing excluded patterns\n    skip.dat (.gitattributes)\n")
        XCTAssertEqual(rules.map(\.pattern), ["*.psd", "art/*.dat", "skip.dat"])
        XCTAssertTrue(rules[0].canRemove)
        XCTAssertFalse(rules[1].canRemove)
        XCTAssertTrue(rules[2].excluded)
        XCTAssertFalse(rules[2].canRemove)
    }
    func testDiagnosticsRemoveURLCredentialsAndSignedQueries() {
        let safe = GitLFSErrorMessage.sanitized("download https://user:secret@example.com/object?signature=private failed")
        XCTAssertFalse(safe.contains("secret"))
        XCTAssertFalse(safe.contains("private"))
        XCTAssertTrue(safe.contains("example.com/object"))
    }
    func testDiagnosticsRedactMalformedURL() {
        let safe = GitLFSErrorMessage.sanitized("download https://user:secret@[invalid?signature=private failed")
        XCTAssertFalse(safe.contains("secret"))
        XCTAssertFalse(safe.contains("private"))
        XCTAssertTrue(safe.contains("<remote URL>"))
    }

    func testAuthenticationClassificationRequiresHTTPContext() {
        for detail in ["object does not exist: abc401def403", "object does not exist: 401 bytes"] {
            let message = GitLFSErrorMessage.describe(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: detail]))
            XCTAssertTrue(message.hasPrefix("The LFS object is missing"))
        }
        for detail in ["HTTP 401", "HTTP/1.1 403", "status code: 401", "403 Forbidden"] {
            let message = GitLFSErrorMessage.describe(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: detail]))
            XCTAssertTrue(message.hasPrefix("Git LFS could not authenticate"))
        }
    }

    func testIncludeFiltersRejectAmbiguousSelections() throws {
        XCTAssertEqual(try GitStatusService.lfsIncludePaths(["Assets/a.dat", "日本語 space.dat"]), "/Assets/a.dat,/日本語 space.dat")
        for path in ["a,b.dat", "*.dat", "a[1].dat", "../outside", "line\nbreak", " trailing "] {
            XCTAssertThrowsError(try GitStatusService.lfsIncludePaths([path]))
        }
    }

    func testMinimumLFSVersion() {
        XCTAssertTrue(GitLFSVersionRunner.isSupported("git-lfs/3.8.0 (GitHub; darwin arm64)"))
        XCTAssertTrue(GitLFSVersionRunner.isSupported("git-lfs/4.0.0"))
        XCTAssertFalse(GitLFSVersionRunner.isSupported("git-lfs/3.7.0"))
        XCTAssertFalse(GitLFSVersionRunner.isSupported("git version 2.53.0"))
    }
    func testPointerRequiresValidHashSizeAndUniqueFields() {
        let hash = String(repeating: "a", count: 64)
        let valid = "version https://git-lfs.github.com/spec/v1\noid sha256:\(hash)\nsize 120\n"
        XCTAssertEqual(GitLFSPointer(valid)?.size, 120)
        XCTAssertEqual(GitLFSPointer(valid.replacingOccurrences(of: "\n", with: "\r\n"))?.oid, hash)
        XCTAssertNil(GitLFSPointer(valid.replacingOccurrences(of: hash, with: "abc")))
        XCTAssertNil(GitLFSPointer(valid.replacingOccurrences(of: "size 120", with: "size -1")))
        XCTAssertNil(GitLFSPointer(valid + "size 1\n"))
        XCTAssertNil(GitLFSPointer(valid + "unexpected data\n"))
    }

    func testJSONPreservesUnusualFilenamesAndCacheDistinction() throws {
        let data = Data(#"{"files":[{"name":"space\n日本語.dat","size":42,"oid":"abc","checkout":false,"downloaded":true}]}"#.utf8)
        let file = try XCTUnwrap(JSONDecoder().decode(GitLFSFileList.self, from: data).files?.first)
        XCTAssertEqual(file.name, "space\n日本語.dat")
        XCTAssertEqual(file.localState, "Cached · Restore Content")
        XCTAssertNil(try JSONDecoder().decode(GitLFSFileList.self, from: Data(#"{"files":null}"#.utf8)).files)
    }

    func testArchiveRejectsTraversalAndAbsolutePaths() throws {
        try GitLFSArchiveExtractor.validateListing("git-lfs-3.8.0/\ngit-lfs-3.8.0/git-lfs\n")
        for path in ["/tmp/git-lfs", "git-lfs-3.8.0/../../outside", "other/git-lfs", ""] {
            XCTAssertThrowsError(try GitLFSArchiveExtractor.validateListing(path))
        }
    }

    func testScopedAskpassDoesNotReturnTokenToAnotherHost() throws {
        let injection = try TemporaryGitCredentialInjector().injection(for: GitCredential(username: "tester", token: "test-only-token"))
        defer { injection.cleanup() }
        var environment = injection.environment
        environment["MACGIT_GIT_CREDENTIAL_HOST"] = "git.example.com"
        environment["MACGIT_GIT_CREDENTIAL_SCHEME"] = "https"
        func ask(_ prompt: String) throws -> (Int32, String) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: try XCTUnwrap(environment["GIT_ASKPASS"]))
            task.arguments = [prompt]
            task.environment = environment
            let output = Pipe()
            task.standardOutput = output
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return (task.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        let allowed = try ask("Password for 'https://tester@git.example.com':")
        XCTAssertEqual(allowed.0, 0)
        XCTAssertEqual(allowed.1.trimmingCharacters(in: .newlines), "test-only-token")
        for prompt in ["Password for 'https://evil.example.com':", "Password for 'https://git.example.com.evil.test':", "Password for 'http://git.example.com':"] {
            let denied = try ask(prompt)
            XCTAssertNotEqual(denied.0, 0)
            XCTAssertEqual(denied.1, "")
        }
    }
}
