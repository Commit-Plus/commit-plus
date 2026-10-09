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

final class GitFlowLitePhase1Tests: XCTestCase {
    func testBranchNameSanitizerMatchesCreateBranchBehavior() {
        XCTAssertEqual(
            GitBranchNameSanitizer.sanitize("  Test  Feature Flow  "),
            "Test-Feature-Flow"
        )
        XCTAssertEqual(
            GitBranchNameSanitizer.sanitize("Feature/Sidebar & Search"),
            "Feature/Sidebar-&-Search"
        )
    }

    func testBranchNameSanitizerPreservesCaseAndNonWhitespaceCharacters() {
        XCTAssertEqual(GitBranchNameSanitizer.sanitize("cv-123 Add new feature"), "cv-123-Add-new-feature")
        XCTAssertEqual(GitBranchNameSanitizer.sanitize("Feature/CV-123.API_v2"), "Feature/CV-123.API_v2")
        XCTAssertEqual(GitBranchNameSanitizer.sanitize("  CV-123\tAdd\nFeature  "), "CV-123-Add-Feature")
        XCTAssertEqual(GitBranchNameSanitizer.sanitize("Feature--API"), "Feature--API")
    }

    func testPlannerMapsTopicKindsToExpectedBaseAndPrefix() throws {
        let configuration = GitFlowConfiguration(isEnabled: true)
        let planner = GitFlowPlanner()

        XCTAssertEqual(
            try planner.startPlan(kind: .feature, topicName: "search", configuration: configuration),
            GitFlowStartPlan(kind: .feature, branchName: "feature/search", baseBranch: "develop")
        )
        XCTAssertEqual(
            try planner.startPlan(kind: .bugfix, topicName: "empty-state", configuration: configuration),
            GitFlowStartPlan(kind: .bugfix, branchName: "bugfix/empty-state", baseBranch: "develop")
        )
        XCTAssertEqual(
            try planner.startPlan(kind: .release, topicName: "2.0.0", configuration: configuration),
            GitFlowStartPlan(kind: .release, branchName: "release/2.0.0", baseBranch: "develop")
        )
        XCTAssertEqual(
            try planner.startPlan(kind: .hotfix, topicName: "2.0.1", configuration: configuration),
            GitFlowStartPlan(kind: .hotfix, branchName: "hotfix/2.0.1", baseBranch: "main")
        )
    }

    func testConfigurationNormalizesPrefixesAndDetectsTopicKind() throws {
        let configuration = GitFlowConfiguration(
            isEnabled: true,
            featurePrefix: " feature ",
            bugfixPrefix: "bugfix/",
            releasePrefix: "release",
            hotfixPrefix: "hotfix/"
        )

        XCTAssertEqual(configuration.normalized().featurePrefix, "feature/")
        XCTAssertEqual(configuration.normalized().releasePrefix, "release/")
        XCTAssertEqual(
            GitFlowPlanner().topicKind(for: "bugfix/sidebar", configuration: configuration),
            .bugfix
        )
    }

    func testPlannerRejectsDuplicatePrefixes() {
        let configuration = GitFlowConfiguration(
            isEnabled: true,
            featurePrefix: "topic/",
            bugfixPrefix: "topic/"
        )

        XCTAssertThrowsError(try GitFlowPlanner().validate(configuration)) { error in
            XCTAssertEqual(
                error as? GitFlowPlannerError,
                .invalidConfiguration("Git Flow prefixes must be unique.")
            )
        }
    }

    func testConfigurationStoreIsSharedByLinkedWorktrees() async throws {
        let repositoryURL = try makeRepository()
        let worktreeURL = repositoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("macgit-git-flow-worktree-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: repositoryURL)
            try? FileManager.default.removeItem(at: worktreeURL)
        }
        try runGit(["worktree", "add", worktreeURL.path, "develop"], in: repositoryURL)

        let configuration = GitFlowConfiguration(
            isEnabled: true,
            mainBranch: "main",
            developBranch: "develop",
            featurePrefix: "feat/"
        )
        let store = GitFlowConfigurationStore()
        try await store.save(configuration, in: repositoryURL)

        let loaded = await store.configuration(in: worktreeURL)
        XCTAssertEqual(loaded, configuration.normalized())
    }

    func testStartFeatureCreatesAndChecksOutBranchFromDevelop() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let configuration = GitFlowConfiguration(isEnabled: true)
        let plan = try GitFlowPlanner().startPlan(
            kind: .feature,
            topicName: "workflow-menu",
            configuration: configuration
        )

        let result = try await GitFlowService().start(plan, in: repositoryURL)
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        let featureTip = try await GitBranchUndoSupport().tip(
            of: "feature/workflow-menu",
            in: repositoryURL
        )
        let developTip = try await GitBranchUndoSupport().tip(of: "develop", in: repositoryURL)

        XCTAssertEqual(result.placement, .currentWorkingCopy(previousRef: "main"))
        XCTAssertEqual(currentBranch, "feature/workflow-menu")
        XCTAssertEqual(featureTip, developTip)
    }

    func testStartIsBlockedByDirtyWorkingTree() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try "dirty\n".write(
            to: repositoryURL.appendingPathComponent("untracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        let plan = try GitFlowPlanner().startPlan(
            kind: .bugfix,
            topicName: "dirty-state",
            configuration: GitFlowConfiguration(isEnabled: true)
        )

        do {
            _ = try await GitFlowService().start(plan, in: repositoryURL)
            XCTFail("Expected dirty working tree validation to fail")
        } catch {
            XCTAssertEqual(error as? GitFlowStartError, .dirtyWorkingTree)
        }
    }

    func testStartIsBlockedWhenBranchAlreadyExists() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try runGit(["branch", "feature/existing"], in: repositoryURL)
        let plan = try GitFlowPlanner().startPlan(
            kind: .feature,
            topicName: "existing",
            configuration: GitFlowConfiguration(isEnabled: true)
        )

        do {
            _ = try await GitFlowService().start(plan, in: repositoryURL)
            XCTFail("Expected existing branch validation to fail")
        } catch {
            XCTAssertEqual(error as? GitFlowStartError, .branchAlreadyExists("feature/existing"))
        }
    }

    func testStartIsBlockedByInvalidBranchName() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let plan = try GitFlowPlanner().startPlan(
            kind: .feature,
            topicName: "bad..name",
            configuration: GitFlowConfiguration(isEnabled: true)
        )

        do {
            _ = try await GitFlowService().start(plan, in: repositoryURL)
            XCTFail("Expected invalid branch-name validation to fail")
        } catch {
            XCTAssertEqual(error as? GitFlowStartError, .invalidBranchName("feature/bad..name"))
        }
    }

    func testStartIsBlockedWhileMergeIsInProgress() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try runGit(["checkout", "-b", "conflicting"], in: repositoryURL)
        try "branch\n".write(
            to: repositoryURL.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["commit", "-am", "branch change"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
        try "main\n".write(
            to: repositoryURL.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["commit", "-am", "main change"], in: repositoryURL)
        XCTAssertThrowsError(try runGit(["merge", "conflicting"], in: repositoryURL))
        let plan = try GitFlowPlanner().startPlan(
            kind: .hotfix,
            topicName: "blocked",
            configuration: GitFlowConfiguration(isEnabled: true)
        )

        do {
            _ = try await GitFlowService().start(plan, in: repositoryURL)
            XCTFail("Expected unfinished-operation validation to fail")
        } catch {
            XCTAssertEqual(error as? GitFlowStartError, .unfinishedOperation)
        }
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-git-flow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repositoryURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
        try "base\n".write(
            to: repositoryURL.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.txt"], in: repositoryURL)
        try runGit(["commit", "-m", "initial"], in: repositoryURL)
        try runGit(["branch", "develop"], in: repositoryURL)
        return repositoryURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        let standardError = Pipe()
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git failed"
            throw GitError.commandFailed(message)
        }
    }
}
