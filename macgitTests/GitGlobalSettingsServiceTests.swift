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

final class GitGlobalSettingsServiceTests: XCTestCase {
    func testLoadReadsGitVersionAndGlobalConfiguration() async throws {
        let runner = GlobalSettingsRecordingRunner(
            responses: [
                ["--version"]: "git version 2.50.1\n",
                ["config", "--global", "--get", "user.name"]: "Ada Lovelace\n",
                ["config", "--global", "--get", "user.email"]: "ada@example.com\n",
                ["config", "--global", "--get", "init.defaultBranch"]: "trunk\n",
                ["config", "--global", "--get", "fetch.prune"]: "true\n",
                ["config", "--global", "--get", "push.autoSetupRemote"]: "yes\n",
                ["config", "--global", "--get", "core.excludesFile"]: "~/.gitignore_global\n",
                ["config", "--global", "--get-all", "credential.helper"]: "cache\nosxkeychain\n"
            ]
        )
        let service = GitStatusService(runner: runner)

        let settings = try await service.loadGlobalGitSettings()

        XCTAssertEqual(settings.version, "git version 2.50.1")
        XCTAssertFalse(settings.executablePath.isEmpty)
        XCTAssertEqual(settings.userName, "Ada Lovelace")
        XCTAssertEqual(settings.userEmail, "ada@example.com")
        XCTAssertEqual(settings.defaultBranchName, "trunk")
        XCTAssertTrue(settings.pruneOnFetch)
        XCTAssertTrue(settings.autoSetupRemote)
        XCTAssertEqual(settings.excludesFilePath, "~/.gitignore_global")
        XCTAssertEqual(settings.credentialHelperValues, ["cache", "osxkeychain"])
    }

    func testCredentialHelperModeUsesValuesAfterLastReset() {
        XCTAssertEqual(
            GitCredentialHelperMode.resolve(configuredValues: ["cache", "", "osxkeychain"]),
            .helper("osxkeychain")
        )
        XCTAssertEqual(
            GitCredentialHelperMode.resolve(configuredValues: ["cache", "osxkeychain"]),
            .preserveExisting
        )
        XCTAssertEqual(
            GitCredentialHelperMode.resolve(configuredValues: [""]),
            .commitPlusAccountsOnly
        )
    }

    func testAvailableCredentialHelpersUsesActiveGitCommandList() async {
        let runner = GlobalSettingsRecordingRunner(
            responses: [
                ["help", "-a"]: "credential-store credential-cache credential-cache--daemon credential-osxkeychain\n"
            ]
        )
        let service = GitStatusService(runner: runner)

        let helpers = await service.availableCredentialHelpers()

        XCTAssertEqual(helpers, ["osxkeychain", "cache"])
    }

    func testUpdateReplacesCredentialHelperWithResetAndVerifiedHelper() async throws {
        let runner = GlobalSettingsRecordingRunner(
            responses: [["help", "-a"]: "credential-osxkeychain\n"],
            credentialHelpers: ["cache", "custom"]
        )
        let service = GitStatusService(runner: runner)
        let settings = makeValidSettings()

        try await service.updateGlobalGitSettings(
            settings,
            credentialHelperMode: .helper("osxkeychain")
        )

        let calls = await runner.recordedArguments()
        XCTAssertTrue(calls.contains(["config", "--global", "--unset-all", "credential.helper"]))
        XCTAssertTrue(calls.contains(["config", "--global", "--add", "credential.helper", ""]))
        XCTAssertTrue(calls.contains(["config", "--global", "--add", "credential.helper", "osxkeychain"]))
        let credentialHelpers = await runner.currentCredentialHelpers()
        XCTAssertEqual(credentialHelpers, ["", "osxkeychain"])
    }

    func testUpdateRejectsHelperMissingFromActiveRuntimeBeforeChangingConfiguration() async {
        let runner = GlobalSettingsRecordingRunner(
            responses: [["help", "-a"]: "credential-cache\n"],
            credentialHelpers: ["cache"]
        )
        let service = GitStatusService(runner: runner)

        do {
            try await service.updateGlobalGitSettings(
                makeValidSettings(),
                credentialHelperMode: .helper("osxkeychain")
            )
            XCTFail("Expected unavailable helper to be rejected.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("not available"))
        }

        let credentialHelpers = await runner.currentCredentialHelpers()
        XCTAssertEqual(credentialHelpers, ["cache"])
    }

    func testUpdateClearsHelpersWithoutErasingStoredCredentials() async throws {
        let runner = GlobalSettingsRecordingRunner(credentialHelpers: ["osxkeychain"])
        let service = GitStatusService(runner: runner)

        try await service.updateGlobalGitSettings(
            makeValidSettings(),
            credentialHelperMode: .commitPlusAccountsOnly
        )

        let credentialHelpers = await runner.currentCredentialHelpers()
        let calls = await runner.recordedArguments()
        XCTAssertEqual(credentialHelpers, [""])
        XCTAssertFalse(calls.flatMap { $0 }.contains("erase"))
    }

    func testUpdatingOtherSettingsPreservesMultipleCredentialHelpers() async throws {
        let runner = GlobalSettingsRecordingRunner(credentialHelpers: ["cache", "osxkeychain"])
        let service = GitStatusService(runner: runner)

        try await service.updateGlobalGitSettings(makeValidSettings())

        let credentialHelpers = await runner.currentCredentialHelpers()
        let calls = await runner.recordedArguments()
        XCTAssertEqual(credentialHelpers, ["cache", "osxkeychain"])
        XCTAssertFalse(calls.contains(["config", "--global", "--unset-all", "credential.helper"]))
    }

    func testUpdateWritesValidatedGlobalConfiguration() async throws {
        let runner = GlobalSettingsRecordingRunner()
        let service = GitStatusService(runner: runner)
        let settings = GlobalGitSettings(
            executablePath: "/usr/bin/git",
            version: "git version 2.50.1",
            userName: "Ada Lovelace",
            userEmail: "ada@example.com",
            defaultBranchName: "main",
            pruneOnFetch: true,
            autoSetupRemote: false,
            excludesFilePath: "~/.config/git/ignore"
        )

        try await service.updateGlobalGitSettings(settings)

        let calls = await runner.recordedArguments()
        XCTAssertEqual(
            calls,
            [
                ["check-ref-format", "--branch", "main"],
                ["config", "--global", "user.name", "Ada Lovelace"],
                ["config", "--global", "user.email", "ada@example.com"],
                ["config", "--global", "init.defaultBranch", "main"],
                ["config", "--global", "fetch.prune", "true"],
                ["config", "--global", "push.autoSetupRemote", "false"],
                ["config", "--global", "core.excludesFile", "~/.config/git/ignore"]
            ]
        )
    }

    func testUpdateRejectsInvalidIdentityBeforeRunningGit() async {
        let runner = GlobalSettingsRecordingRunner()
        let service = GitStatusService(runner: runner)
        var settings = GlobalGitSettings.empty
        settings.userName = "Ada Lovelace"
        settings.userEmail = "invalid email"

        do {
            try await service.updateGlobalGitSettings(settings)
            XCTFail("Expected invalid email to be rejected.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("valid email"))
        }

        let calls = await runner.recordedArguments()
        XCTAssertTrue(calls.isEmpty)
    }

    private func makeValidSettings() -> GlobalGitSettings {
        GlobalGitSettings(
            executablePath: "/usr/bin/git",
            version: "git version 2.50.1",
            userName: "Ada Lovelace",
            userEmail: "ada@example.com",
            defaultBranchName: "main",
            pruneOnFetch: true,
            autoSetupRemote: false,
            excludesFilePath: "~/.config/git/ignore"
        )
    }
}

private actor GlobalSettingsRecordingRunner: GitCommandRunning {
    private let responses: [[String]: String]
    private var calls: [[String]] = []
    private var credentialHelpers: [String]?

    init(responses: [[String]: String] = [:], credentialHelpers: [String]? = nil) {
        self.responses = responses
        self.credentialHelpers = credentialHelpers
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        calls.append(arguments)
        if arguments == ["config", "--global", "--get-all", "credential.helper"],
           let credentialHelpers {
            guard !credentialHelpers.isEmpty else { return "" }
            return credentialHelpers.joined(separator: "\n") + "\n"
        }
        if arguments == ["config", "--global", "--unset-all", "credential.helper"] {
            credentialHelpers = []
            return ""
        }
        if arguments.starts(with: ["config", "--global", "--add", "credential.helper"]),
           let helper = arguments.last {
            credentialHelpers = (credentialHelpers ?? []) + [helper]
            return ""
        }
        return responses[arguments] ?? ""
    }

    func recordedArguments() -> [[String]] {
        calls
    }

    func currentCredentialHelpers() -> [String]? {
        credentialHelpers
    }
}
