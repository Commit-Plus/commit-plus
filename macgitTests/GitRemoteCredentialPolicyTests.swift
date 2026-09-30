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
