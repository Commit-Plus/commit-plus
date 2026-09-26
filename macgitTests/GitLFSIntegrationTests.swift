// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class GitLFSIntegrationTests: XCTestCase {
    func testCancellationStopsChildrenBeforeReturning() async throws {
        let (repo, service) = try await fixture()
        let resultFile = repo.appendingPathComponent("should-not-be-written")
        let task = Task {
            try await service.runProcessRaw(executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "(sleep 2; echo unexpected > \"$RESULT_FILE\") & wait"], in: repo,
                environment: ["PATH": "/usr/bin:/bin", "RESULT_FILE": resultFile.path])
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await Task.sleep(for: .seconds(2.2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resultFile.path))
    }

    func testSelectedLFSOverridesGitBundledExecutable() async throws {
        let (repo, service) = try await fixture()
        let core = repo.deletingLastPathComponent().appendingPathComponent("competing-core")
        try FileManager.default.createDirectory(at: core, withIntermediateDirectories: true)
        let competing = core.appendingPathComponent("git-lfs")
        try "#!/bin/sh\necho WRONG-LFS\n".write(to: competing, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: competing.path)
        let environment = try await service.lfsRuntime.environment(inheriting: ["GIT_EXEC_PATH": core.path, "PATH": "/usr/bin:/bin"])
        let output = try await service.runProcessRaw(executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["lfs", "version"], in: repo, environment: environment)
        XCTAssertTrue(String(decoding: output, as: UTF8.self).hasPrefix("git-lfs/"))
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("WRONG-LFS"))
    }

    func testPushCloneAndDownloadRoundTripThroughService() async throws {
        let (repo, service) = try await fixture()
        try await service.setupLFS(in: repo)
        let rule = try await service.reviewLFSTracking(pattern: "*.dat", literal: false, removing: false, in: repo)
        try await service.applyLFSTracking(rule, in: repo)
        let content = Data(repeating: 91, count: 8192)
        try content.write(to: repo.appendingPathComponent("asset.dat"))
        _ = try await service.runGit(arguments: ["add", "."], in: repo)
        try await service.commit(message: "LFS asset", in: repo)
        let remote = repo.deletingLastPathComponent().appendingPathComponent("remote.git")
        _ = try await service.runGit(arguments: ["init", "--bare", remote.path], in: repo)
        _ = try await service.runGit(arguments: ["remote", "add", "origin", remote.path], in: repo)
        _ = try await service.runGit(arguments: ["push", "-u", "origin", "main"], in: repo)
        _ = try await service.runGit(arguments: ["symbolic-ref", "HEAD", "refs/heads/main"], in: remote)
        let clone = repo.deletingLastPathComponent().appendingPathComponent("clone")
        try await service.cloneRepository(remoteURL: remote.path, to: clone, checkoutBranch: "main", recurseSubmodules: false, downloadLFSContent: false)
        XCTAssertNotNil(GitLFSPointer(try String(contentsOf: clone.appendingPathComponent("asset.dat"), encoding: .utf8)))
        _ = try await service.runGit(arguments: ["remote", "rename", "origin", "upstream"], in: clone)
        try await service.finishLFSClone(in: clone)
        XCTAssertEqual(try Data(contentsOf: clone.appendingPathComponent("asset.dat")), content)
        let changed = Data("local edits".utf8)
        try changed.write(to: clone.appendingPathComponent("asset.dat"))
        try await service.restoreLFS(in: clone)
        XCTAssertEqual(try Data(contentsOf: clone.appendingPathComponent("asset.dat")), changed)
    }

    private func fixture() async throws -> (URL, GitStatusService) {
        let candidate = ProcessInfo.processInfo.environment["COMMITPLUS_TEST_LFS"] ?? "/opt/homebrew/bin/git-lfs"
        guard FileManager.default.isExecutableFile(atPath: candidate) else { throw XCTSkip("Set COMMITPLUS_TEST_LFS to a Git LFS executable for integration tests.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lfs-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let repository = root.appendingPathComponent("repository")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lfs-tests-\(UUID())"))
        let configuration = GitRuntimeConfiguration(applicationSupportDirectory: root,
            candidateSystemGitURLs: [URL(fileURLWithPath: candidate)], manifest: GitLFSRuntime.manifest,
            preferenceDefaults: defaults, preferenceKey: "runtime", managedDirectoryName: "LFS",
            executableRelativePath: "git-lfs-3.8.0/git-lfs", versionPrefix: "git-lfs/")
        let runtime = GitLFSRuntime(manager: GitRuntimeManager(configuration: configuration), commandDirectory: root.appendingPathComponent(".test-command-paths"))
        let service = GitStatusService(lfsRuntime: runtime)
        _ = try await service.runGit(arguments: ["init", "-b", "main"], in: repository)
        for (key, value) in [("user.name", "LFS Tests"), ("user.email", "test@example.invalid"), ("commit.gpgsign", "false")] {
            _ = try await service.runGit(arguments: ["config", key, value], in: repository)
        }
        return (repository, service)
    }

    func testConversionProducesPointerWithoutChangingWorkingContent() async throws {
        let (repo, service) = try await fixture()
        let file = repo.appendingPathComponent("space 日本語.dat")
        let content = Data(repeating: 42, count: 4096)
        try content.write(to: file)
        _ = try await service.runGit(arguments: ["add", "."], in: repo)
        _ = try await service.runGit(arguments: ["commit", "-m", "ordinary file"], in: repo)
        try await service.setupLFS(in: repo)
        let rule = try await service.reviewLFSTracking(pattern: "*.dat", literal: false, removing: false, in: repo)
        try await service.applyLFSTracking(rule, in: repo)
        let review = try await service.reviewLFSConversion(path: file.lastPathComponent, in: repo)
        try await service.convertLFS(review, in: repo)
        let staged = try await service.runGit(arguments: ["show", ":" + file.lastPathComponent], in: repo)
        XCTAssertEqual(GitLFSPointer(staged)?.size, 4096)
        XCTAssertEqual(try Data(contentsOf: file), content)
        do { try await service.validateLFSCommitAttributes(in: repo); XCTFail("Unstaged attributes must be reported") } catch {}
        _ = try await service.runGit(arguments: ["add", ".gitattributes"], in: repo)
        try await service.commit(message: "LFS", in: repo)
        let snapshot = try await service.lfsSnapshot(in: repo)
        XCTAssertEqual(snapshot.files.count, 1)
        XCTAssertNil(snapshot.setupIssue)
    }

    func testRuleReviewRejectsConcurrentAttributesChange() async throws {
        let (repo, service) = try await fixture()
        let review = try await service.reviewLFSTracking(pattern: "*.dat", literal: false, removing: false, in: repo)
        try "# another editor\n".write(to: repo.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
        do { try await service.applyLFSTracking(review, in: repo); XCTFail("Must revalidate attributes") } catch {}
        XCTAssertEqual(try String(contentsOf: repo.appendingPathComponent(".gitattributes"), encoding: .utf8), "# another editor\n")
    }

    func testSetupPreservesCustomHook() async throws {
        let (repo, service) = try await fixture()
        let hook = repo.appendingPathComponent(".git/hooks/pre-push")
        let content = "#!/bin/sh\necho custom\n"
        try content.write(to: hook, atomically: true, encoding: .utf8)
        try await service.setupLFS(in: repo)
        let issue = try await service.lfsSetupIssue(in: repo)
        XCTAssertNil(issue)
        XCTAssertEqual(try String(contentsOf: hook, encoding: .utf8), content)
    }

    func testCustomHooksPathDispatchesInputAndPreservesFailures() async throws {
        let (repo, service) = try await fixture()
        let original = repo.appendingPathComponent("custom hooks' directory")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        _ = try await service.runGit(arguments: ["config", "core.hooksPath", "custom hooks' directory"], in: repo)
        let hook = original.appendingPathComponent("pre-push")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$ARGUMENTS\"\ncat > \"$ORIGINAL_INPUT\"\nexit \"${HOOK_EXIT:-0}\"\n"
        try script.write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try await service.setupLFS(in: repo)
        let path = try await service.runGit(arguments: ["config", "--get", "core.hooksPath"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try await service.setupLFS(in: repo)
        let repeatedPath = try await service.runGit(arguments: ["config", "--get", "core.hooksPath"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(path, repeatedPath)
        XCTAssertEqual(try String(contentsOf: hook, encoding: .utf8), script)

        let bin = repo.appendingPathComponent("fake-bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let git = bin.appendingPathComponent("git")
        try "#!/bin/sh\ncat > \"$LFS_INPUT\"\n".write(to: git, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: git.path)
        let originalInput = repo.appendingPathComponent("original-input")
        let lfsInput = repo.appendingPathComponent("lfs-input")
        let arguments = repo.appendingPathComponent("arguments")
        var environment = ["PATH": bin.path + ":/usr/bin:/bin", "HOOK": path + "/pre-push",
                           "ORIGINAL_INPUT": originalInput.path, "LFS_INPUT": lfsInput.path, "ARGUMENTS": arguments.path]
        let command = "printf 'refs/heads/main abc refs/heads/main def\\n' | \"$HOOK\" origin 'remote with spaces'"
        _ = try await service.runProcessRaw(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", command], in: repo, environment: environment)
        XCTAssertEqual(try Data(contentsOf: originalInput), try Data(contentsOf: lfsInput))
        XCTAssertEqual(try String(contentsOf: arguments, encoding: .utf8), "origin\nremote with spaces\n")
        try FileManager.default.removeItem(at: lfsInput)
        environment["HOOK_EXIT"] = "17"
        do {
            _ = try await service.runProcessRaw(executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", command], in: repo, environment: environment)
            XCTFail("The original hook must veto the push")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: lfsInput.path))

        // A hook added after setup is still discovered in the original directory.
        let laterHook = original.appendingPathComponent("pre-commit")
        try "#!/bin/sh\necho forwarded\n".write(to: laterHook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: laterHook.path)
        let output = try await service.runProcessRaw(executableURL: URL(fileURLWithPath: path + "/pre-commit"),
            arguments: [], in: repo)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "forwarded\n")
    }

    func testSharedHooksPathIsNotModified() async throws {
        let (repo, service) = try await fixture()
        let shared = repo.deletingLastPathComponent().appendingPathComponent("shared-hooks")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        let hook = shared.appendingPathComponent("pre-push")
        let content = "#!/bin/sh\nexit 0\n"
        try content.write(to: hook, atomically: true, encoding: .utf8)
        _ = try await service.runGit(arguments: ["config", "core.hooksPath", shared.path], in: repo)
        try await service.setupLFS(in: repo)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: shared.path), ["pre-push"])
        XCTAssertEqual(try String(contentsOf: hook, encoding: .utf8), content)
        let issue = try await service.lfsSetupIssue(in: repo)
        XCTAssertNil(issue)
    }

    func testConversionRejectsConcurrentFileEditAndPartialStaging() async throws {
        let (repo, service) = try await fixture()
        try await service.setupLFS(in: repo)
        let rule = try await service.reviewLFSTracking(pattern: "*.dat", literal: false, removing: false, in: repo)
        try await service.applyLFSTracking(rule, in: repo)
        let file = repo.appendingPathComponent("file.dat")
        try "first".write(to: file, atomically: true, encoding: .utf8)
        let review = try await service.reviewLFSConversion(path: "file.dat", in: repo)
        try "edited".write(to: file, atomically: true, encoding: .utf8)
        do { try await service.convertLFS(review, in: repo); XCTFail("Must detect concurrent edits") } catch {}
        _ = try await service.runGit(arguments: ["add", "file.dat"], in: repo)
        try "working only".write(to: file, atomically: true, encoding: .utf8)
        do { _ = try await service.reviewLFSConversion(path: "file.dat", in: repo); XCTFail("Must preserve partial staging") } catch {}
    }
}
