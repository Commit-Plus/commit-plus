// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class RepositoryActionAuditTests: XCTestCase {
    func testMutatingCommandsAreAuditable() {
        let commands: [[String]] = [
            ["fetch", "--prune", "origin"],
            ["push", "origin", "main"],
            ["commit", "-F", "-"],
            ["apply", "--cached", "-"],
            ["checkout", "main"],
            ["reset", "--hard", "HEAD~1"],
            ["stash", "push", "-m", "work"],
            ["stash"],
            ["branch", "topic"],
            ["branch", "-D", "topic"],
            ["branch", "--set-upstream-to=origin/main", "main"],
            ["tag", "v1.0"],
            ["tag", "-d", "v1.0"],
            ["remote", "add", "upstream", "https://example.com/repo.git"],
            ["worktree", "add", "../feature", "feature"],
            ["config", "user.name", "Someone"],
            ["config", "--unset", "branch.main.merge"],
            ["submodule", "update", "--init"],
            ["-c", "core.hooksPath=/dev/null", "commit", "-m", "x"],
            ["--literal-pathspecs", "add", "--", "file.txt"],
            ["lfs", "push", "origin", "main"]
        ]
        for arguments in commands {
            XCTAssertTrue(RepositoryActionAudit.isAuditable(arguments: arguments), "\(arguments)")
        }
    }

    func testReadOnlyCommandsAreNotAuditable() {
        let commands: [[String]] = [
            ["status", "--porcelain=v2"],
            ["log", "--format=%H", "--no-patch"],
            ["rev-parse", "HEAD"],
            ["diff", "--cached"],
            ["for-each-ref", "refs/heads"],
            ["config", "--get", "user.name"],
            ["config", "user.name"],
            ["config", "--file", ".gitmodules", "--get-regexp", "path"],
            ["branch", "--show-current"],
            ["branch", "-a"],
            ["branch", "--list", "topic*"],
            ["stash", "list"],
            ["tag", "-l", "v*"],
            ["remote"],
            ["remote", "get-url", "origin"],
            ["worktree", "list", "--porcelain"],
            ["submodule", "status"],
            ["apply", "--check", "-"],
            ["symbolic-ref", "HEAD"],
            ["lfs", "ls-files", "--json"],
            ["-c", "color.ui=never", "show", "HEAD"],
            []
        ]
        for arguments in commands {
            XCTAssertFalse(RepositoryActionAudit.isAuditable(arguments: arguments), "\(arguments)")
        }
    }

    func testTitles() {
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["fetch", "--prune", "origin"]), "Fetch origin")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["push", "origin", "main:main"]), "Push origin")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["commit", "-m", "message"]), "Commit")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["stash"]), "Stash push")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["stash", "pop", "stash@{0}"]), "Stash pop")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["worktree", "add", "/tmp/repo-feature", "feature"]), "Worktree add repo-feature")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["add", "--", "Sources/a.swift"]), "Add a.swift")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["add", "--", "a", "b", "c"]), "Add 3 files")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["cherry-pick", "abc123"]), "Cherry-pick abc123")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["update-ref", "refs/heads/main", "abc"]), "Update ref refs/heads/main")
        XCTAssertEqual(RepositoryActionAudit.title(arguments: ["-c", "a=b", "checkout", "main"]), "Checkout main")
    }

    func testCommandRedactsCredentials() {
        let command = RepositoryActionAudit.displayCommand(arguments: [
            "clone", "https://user:secret@example.com/repo.git", "--token", "abc"
        ])
        XCTAssertFalse(command.contains("secret"), command)
        XCTAssertFalse(command.contains("abc"), command)
        XCTAssertTrue(command.contains("<redacted>"), command)
    }

    func testOutputRedactsURLUserInfo() {
        let output = RepositoryActionAudit.redactedOutput("To https://user:secret@example.com/repo.git\n   abc..def  main -> main")
        XCTAssertEqual(output, "To https://<redacted>@example.com/repo.git\n   abc..def  main -> main")
        XCTAssertEqual(RepositoryActionAudit.redactedOutput("To git@github.com:me/repo.git"), "To git@github.com:me/repo.git")
    }

    func testSummaryFallsBackToStatus() {
        XCTAssertEqual(RepositoryActionAudit.summary(output: "\n  From origin\nmore", status: .succeeded, command: "fetch origin"), "From origin")
        XCTAssertEqual(RepositoryActionAudit.summary(output: "", status: .succeeded, command: "fetch --prune origin"), "Already up to date")
        XCTAssertEqual(RepositoryActionAudit.summary(output: "", status: .succeeded, command: "add -- a.txt"), "Completed with no output")
        XCTAssertEqual(RepositoryActionAudit.summary(output: "", status: .failed, command: "push origin"), "Failed")
        XCTAssertEqual(RepositoryActionAudit.summary(output: "", status: .cancelled, command: "push origin"), "Cancelled")
    }
}
