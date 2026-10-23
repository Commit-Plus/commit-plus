// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import macgit

final class ChatGPTCodexProviderTests: XCTestCase {
    private let responsesPath = "/backend-api/codex/responses"

    func testCommitRequestUsesCodexBackendHeadersAndDialect() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: responsesPath, body: sse([
            completedEvent(text: #"{\"type\":\"feat\",\"subject\":\"Use Codex\",\"body\":\"\"}"#),
        ]))

        let message = try await provider.generateCommitMessage(request: makeCommitRequest())

        XCTAssertEqual(message.text, "feat: Use Codex")
        let sent = await http.requests(path: responsesPath)
        let request = try XCTUnwrap(sent.first)
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/codex/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-ID"), "acct-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "originator"), "codex_cli_rs")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "codex_cli_rs/0.1.0")
        XCTAssertNotNil(UUID(uuidString: request.value(forHTTPHeaderField: "session-id") ?? ""))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["model"] as? String, "gpt-5.6-sol")
        XCTAssertNil(body["max_output_tokens"])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input.first?["type"] as? String, "message")
        XCTAssertEqual(input.first?["role"] as? String, "user")
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertFalse((content.first?["text"] as? String ?? "").isEmpty)
        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["summary"] as? String, "auto")
        let bodyText = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertFalse(bodyText.contains("access-1"))
        XCTAssertFalse(bodyText.contains("refresh-1"))
    }

    func testSessionIDStaysTheSameAcrossRequests() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: responsesPath, body: sse([
            completedEvent(text: #"{\"type\":\"fix\",\"subject\":\"One\",\"body\":\"\"}"#),
        ]))

        _ = try await provider.generateCommitMessage(request: makeCommitRequest())
        _ = try await provider.generateCommitMessage(request: makeCommitRequest())

        let sent = await http.requests(path: responsesPath)
        let ids = Set(sent.compactMap { $0.value(forHTTPHeaderField: "session-id") })
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(ids.count, 1)
    }

    func testAgentTurnReadsToolCallFromOutputItemDoneWhenCompletedOutputIsEmpty() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: responsesPath, body: sse([
            #"{"type":"response.output_item.added","item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"execute_git","arguments":""}}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc_1","delta":"{\"arguments\":"}"#,
            #"{"type":"response.output_item.done","item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"execute_git","arguments":"{\"arguments\":[\"diff\",\"--cached\"]}"}}"#,
            #"{"type":"response.completed","response":{"output":[]}}"#,
        ]))

        let turn = try await provider.generateRepositoryAgentTurn(request: RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review staged files",
            conversation: [],
            previousToolResults: [],
            isFirstTurn: false
        ))

        XCTAssertEqual(turn.toolCalls.map(\.id), ["call_1"])
        XCTAssertEqual(turn.toolCalls.first?.arguments, ["diff", "--cached"])
        let sent = await http.requests(path: responsesPath)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try XCTUnwrap(sent.first?.httpBody)
        ) as? [String: Any])
        // The plain agent message is sent as a typed message with typed content.
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.first?["type"] as? String, "message")
        XCTAssertEqual(input.first?["role"] as? String, "user")
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertFalse((content.first?["text"] as? String ?? "").isEmpty)
    }

    func testAgentFollowUpTurnKeepsToolItemsAndTypesTheMessage() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: responsesPath, body: sse([
            completedEvent(text: "Done."),
        ]))

        _ = try await provider.generateRepositoryAgentTurn(request: RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review staged files",
            conversation: [],
            previousToolResults: [
                RepositoryAIAgentToolResult(
                    toolCall: .init(id: "call_1", name: "execute_git", arguments: ["status"]),
                    commandResult: RepositoryAIGitCommandResult(
                        displayCommand: "git status",
                        output: "clean",
                        succeeded: true,
                        isTruncated: false
                    )
                ),
            ],
            isFirstTurn: false
        ))

        let sent = await http.requests(path: responsesPath)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try XCTUnwrap(sent.first?.httpBody)
        ) as? [String: Any])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.map { $0["type"] as? String }, ["message", "function_call", "function_call_output"])
        XCTAssertNotNil(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(input[1]["call_id"] as? String, "call_1")
        XCTAssertEqual(input[2]["output"] as? String, "clean")
    }

    func testRejectedAccessTokenClearsSignIn() async throws {
        let (provider, http, store) = await makeProvider()
        await http.respond(to: responsesPath, status: 401, body: #"{"detail":"Unauthorized"}"#)

        await assertError(.codexSignInRequired) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        XCTAssertNil(try store.loadTokens())
        let availability = await provider.availability()
        XCTAssertFalse(availability.isAvailable)
    }

    func testUsageLimitMarksProviderUnavailableWithoutFallback() async throws {
        let (provider, http, store) = await makeProvider()
        await http.respond(to: responsesPath, status: 429, body: """
            {"error":{"type":"usage_limit_reached","message":"The usage limit has been reached","plan_type":"free"}}
            """)

        await assertError(.codexUsageLimitReached) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        let availability = await provider.availability()
        XCTAssertEqual(availability, .unavailable(CommitMessageGenerationError.codexUsageLimitReached.localizedDescription))
        XCTAssertNotNil(try store.loadTokens())
        let sent = await http.allRequests()
        XCTAssertEqual(sent.count, 1)
    }

    func testPlanWithoutCodexMarksProviderUnavailable() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: responsesPath, status: 429, body: """
            {"error":{"type":"usage_not_included","message":"Not included"}}
            """)

        await assertError(.codexPlanNotAllowed) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        let availability = await provider.availability()
        XCTAssertEqual(availability, .unavailable(CommitMessageGenerationError.codexPlanNotAllowed.localizedDescription))
    }

    func testForbiddenWithoutKnownCodeReportsBlockedClient() async throws {
        let (provider, http, store) = await makeProvider()
        await http.respond(to: responsesPath, status: 403, body: #"{"detail":"Forbidden"}"#)

        await assertError(.codexClientRejected) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        let availability = await provider.availability()
        XCTAssertEqual(availability, .unavailable(CommitMessageGenerationError.codexClientRejected.localizedDescription))
        XCTAssertNotNil(try store.loadTokens(), "A blocked client must still be disconnectable")
    }

    func testFailedStreamEventMapsUsageNotIncluded() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: responsesPath, body: sse([
            #"{"type":"response.failed","response":{"error":{"code":"usage_not_included","message":"Not included"}}}"#,
        ]))

        await assertError(.codexPlanNotAllowed) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
    }

    func testUnknownErrorShowsBackendMessage() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: responsesPath, status: 400, body: """
            {"error":{"code":"unsupported_model","message":"The model is not supported."}}
            """)

        await assertError(.providerRequestFailed("The model is not supported.")) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
    }

    func testSignedOutProviderSendsNoRequest() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let http = ChatGPTStubHTTPClient()
        let provider = ChatGPTCodexProvider(
            session: ChatGPTAccountSession(store: store, httpClient: http, configuration: .codex),
            modelStore: InMemoryAIProviderModelStore(),
            httpClient: http
        )

        await assertError(.codexSignInRequired) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        let sent = await http.allRequests()
        XCTAssertTrue(sent.isEmpty)
        let availability = await provider.availability()
        XCTAssertEqual(availability, .unavailable("Sign in to ChatGPT (Codex) in Settings → AI."))
    }

    // MARK: Helpers

    private func makeProvider() async -> (ChatGPTCodexProvider, ChatGPTStubHTTPClient, InMemoryChatGPTCredentialStore) {
        var tokens = ChatGPTTokenSet.expiring(at: Date().addingTimeInterval(3_000))
        tokens.clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
        tokens.accountID = "acct-1"
        tokens.planType = "free"
        let store = InMemoryChatGPTCredentialStore(tokens: tokens)
        let http = ChatGPTStubHTTPClient()
        let provider = ChatGPTCodexProvider(
            session: ChatGPTAccountSession(store: store, httpClient: http, configuration: .codex),
            modelStore: InMemoryAIProviderModelStore(),
            httpClient: http
        )
        return (provider, http, store)
    }

    private func assertError(
        _ expected: CommitMessageGenerationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CommitMessageGenerationError, expected, file: file, line: line)
        }
    }

    private func sse(_ events: [String]) -> String {
        events.map { "data: \($0)\n\n" }.joined() + "data: [DONE]\n\n"
    }

    private func completedEvent(text: String) -> String {
        """
        {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"\(text)"}]}]}}
        """
    }

    private func makeCommitRequest() -> CommitMessageGenerationRequest {
        CommitMessageGenerationRequest(
            repositoryName: "macgit",
            branchName: "main",
            changeSource: .staged,
            changes: CommitChangeSnapshot(fingerprint: "tree-1", context: "M\tfile.swift", isTruncated: false),
            recentCommitSubjects: []
        )
    }
}
