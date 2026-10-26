// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class GitRemoteCredentialPolicyTests: XCTestCase {
    func testFetchPullAndPushAllowConfiguredHelpersWithoutTerminalPrompt() async throws {
        let runner = RecordingRunner()
        let service = GitStatusService(runner: runner)
        let repository = URL(fileURLWithPath: "/tmp/credential-policy-repository")

        try await service.fetch(remote: "origin", in: repository)
        _ = try await service.pull(
            remote: "origin",
            branch: "main",
            options: GitStatusService.PullOptions(),
            in: repository
        )
        _ = try await service.push(
            options: GitStatusService.PushOptions(remote: "origin", branches: ["main"]),
            in: repository
        )

        let calls = await runner.recordedCalls()
        let remoteCalls = calls.filter { call in
            ["fetch", "pull", "push"].contains(call.arguments.first)
        }
        XCTAssertEqual(remoteCalls.count, 3)
        for call in remoteCalls {
            let environment = try XCTUnwrap(call.environment)
            XCTAssertEqual(environment["GIT_TERMINAL_PROMPT"], "0")
            XCTAssertEqual(environment["GIT_ASKPASS"], "")
            XCTAssertNil(environment["SSH_ASKPASS"])
            XCTAssertNil(environment["GIT_CONFIG_COUNT"])
        }
    }

    func testRejectedConnectedAccountFallsBackToConfiguredHelpers() async throws {
        let runner = RejectingAccountRunner(fallbackError: nil)
        let service = GitStatusService(runner: runner, userDefaults: fallbackDefaults(enabled: true))
        let injection = connectedAccountInjection()

        let output = try await service.runRemoteGit(
            arguments: ["fetch", "origin"],
            in: URL(fileURLWithPath: "/tmp/credential-fallback-repository"),
            injection: injection
        )

        XCTAssertEqual(output, "fallback")
        let environments = await runner.recordedEnvironments()
        XCTAssertEqual(environments.count, 2)
        XCTAssertEqual(environments[0]["GIT_ASKPASS"], "/tmp/askpass")
        XCTAssertEqual(environments[1]["GIT_ASKPASS"], "")
        XCTAssertEqual(environments[1]["GIT_TERMINAL_PROMPT"], "0")
    }

    func testRejectedFallbackAddsAccessHint() async throws {
        let runner = RejectingAccountRunner(fallbackError: "fatal: could not read Username for 'https://github.com': terminal prompts disabled")
        let service = GitStatusService(runner: runner, userDefaults: fallbackDefaults(enabled: true))

        do {
            _ = try await service.runRemoteGit(
                arguments: ["push", "origin", "main"],
                in: URL(fileURLWithPath: "/tmp/credential-fallback-repository"),
                injection: connectedAccountInjection()
            )
            XCTFail("Expected push to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("terminal prompts disabled"))
            XCTAssertTrue(error.localizedDescription.contains("Authorized OAuth Apps"))
        }
    }

    func testNonAuthenticationFailureDoesNotFallBack() async throws {
        let runner = RejectingAccountRunner(fallbackError: nil, accountError: "! [rejected] main -> main (non-fast-forward)")
        let service = GitStatusService(runner: runner, userDefaults: fallbackDefaults(enabled: true))

        do {
            _ = try await service.runRemoteGit(
                arguments: ["push", "origin", "main"],
                in: URL(fileURLWithPath: "/tmp/credential-fallback-repository"),
                injection: connectedAccountInjection()
            )
            XCTFail("Expected push to fail")
        } catch {
            let environments = await runner.recordedEnvironments()
            XCTAssertEqual(environments.count, 1)
        }
    }

    func testDisabledFallbackExplainsHowToEnableIt() async throws {
        let runner = RejectingAccountRunner(fallbackError: nil)
        let service = GitStatusService(runner: runner, userDefaults: fallbackDefaults(enabled: false))

        do {
            _ = try await service.runRemoteGit(
                arguments: ["fetch", "origin"],
                in: URL(fileURLWithPath: "/tmp/credential-fallback-repository"),
                injection: connectedAccountInjection()
            )
            XCTFail("Expected fetch to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("remote: Repository not found."))
            XCTAssertTrue(error.localizedDescription.contains("Fall back to Git credential helpers"))
            let environments = await runner.recordedEnvironments()
            XCTAssertEqual(environments.count, 1)
        }
    }

    func testFallbackIsEnabledByDefault() async throws {
        let runner = RejectingAccountRunner(fallbackError: nil)
        let service = GitStatusService(runner: runner, userDefaults: fallbackDefaults(enabled: nil))

        let output = try await service.runRemoteGit(
            arguments: ["fetch", "origin"],
            in: URL(fileURLWithPath: "/tmp/credential-fallback-repository"),
            injection: connectedAccountInjection()
        )

        XCTAssertEqual(output, "fallback")
    }

    private func fallbackDefaults(enabled: Bool?) -> UserDefaults {
        let suiteName = "GitRemoteCredentialPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        if let enabled {
            defaults.set(enabled, forKey: GitStatusService.credentialHelperFallbackKey)
        }
        return defaults
    }

    private func connectedAccountInjection() -> GitCredentialInjection {
        GitCredentialInjection(
            environment: ["GIT_ASKPASS": "/tmp/askpass", "GIT_TERMINAL_PROMPT": "0"],
            cleanup: {},
            connectedAccountHost: "github.com"
        )
    }

    private actor RejectingAccountRunner: GitCommandRunning {
        private let fallbackError: String?
        private let accountError: String
        private var environments: [[String: String]] = []

        init(
            fallbackError: String?,
            accountError: String = "remote: Repository not found.\nfatal: repository 'https://github.com/org/private.git/' not found"
        ) {
            self.fallbackError = fallbackError
            self.accountError = accountError
        }

        func runGit(arguments: [String], in directory: URL) async throws -> String {
            ""
        }

        func runGit(
            arguments: [String],
            in directory: URL,
            environment: [String: String]
        ) async throws -> String {
            environments.append(environment)
            if environment["GIT_ASKPASS"] == "/tmp/askpass" {
                throw GitError.commandFailed(accountError)
            }
            if let fallbackError {
                throw GitError.commandFailed(fallbackError)
            }
            return "fallback"
        }

        func recordedEnvironments() -> [[String: String]] {
            environments
        }
    }

    private actor RecordingRunner: GitCommandRunning {
        struct Call: Sendable {
            let arguments: [String]
            let environment: [String: String]?
        }

        private var calls: [Call] = []

        func runGit(arguments: [String], in directory: URL) async throws -> String {
            calls.append(Call(arguments: arguments, environment: nil))
            return ""
        }

        func runGit(
            arguments: [String],
            in directory: URL,
            environment: [String: String]
        ) async throws -> String {
            calls.append(Call(arguments: arguments, environment: environment))
            return ""
        }

        func recordedCalls() -> [Call] {
            calls
        }
    }
}
