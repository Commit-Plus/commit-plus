// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import macgit

final class ChatGPTSubscriptionProviderTests: XCTestCase {
    func testCommitRequestStreamsWithBearerTokenOnlyInHeader() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: "/v1/responses", body: sse([
            #"{"type":"response.created","response":{"id":"r1"}}"#,
            #"{"type":"response.output_text.delta","delta":"{"}"#,
            completedEvent(text: #"{\"type\":\"feat\",\"subject\":\"Use ChatGPT plan\",\"body\":\"\"}"#),
        ]))

        let message = try await provider.generateCommitMessage(request: makeCommitRequest())

        XCTAssertEqual(message.text, "feat: Use ChatGPT plan")
        let requestRequests = await http.requests(path: "/v1/responses")
        let request = try XCTUnwrap(requestRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        let bodyText = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertFalse(bodyText.contains("access-1"))
        XCTAssertFalse(bodyText.contains("refresh-1"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["model"] as? String, "gpt-6.1-sol")
    }

    func testAgentTurnDecodesToolCallFromEventStream() async throws {
        let (provider, http, _) = await makeProvider()
        let completed = """
            {"type":"response.completed","response":{"output":[{"type":"function_call","call_id":"call_1","name":"execute_git","arguments":"{\\"arguments\\":[\\"diff\\",\\"--cached\\"]}"}]}}
            """
        await http.respond(to: "/v1/responses", body: sse([completed]))

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
        let agentRequests = await http.requests(path: "/v1/responses")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try XCTUnwrap(agentRequests.first?.httpBody)
        ) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNotNil(body["tools"])
    }

    func testUsageLimitMarksProviderUnavailableWithoutFallback() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: "/v1/responses", status: 429, body: """
            {"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"Usage limit reached"}}
            """)

        await assertError(.chatGPTUsageLimitReached) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        let availability = await provider.availability()
        XCTAssertEqual(availability, .unavailable(CommitMessageGenerationError.chatGPTUsageLimitReached.localizedDescription))
        let requests = await http.allRequests()
        XCTAssertEqual(requests.compactMap(\.url?.host), ["api.openai.com"])
    }

    func testIneligiblePlanMarksProviderUnavailable() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: "/v1/responses", status: 403, body: """
            {"error":{"code":"subscription_sharing_user_not_eligible","message":"Not eligible"}}
            """)

        await assertError(.chatGPTPlanNotEligible) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        let availability = await provider.availability()
        XCTAssertFalse(availability.isAvailable)
    }

    func testInvalidUserClearsSignIn() async throws {
        let (provider, http, store) = await makeProvider()
        await http.respond(to: "/v1/responses", status: 401, body: """
            {"error":{"code":"subscription_sharing_invalid_user","message":"Invalid user"}}
            """)

        await assertError(.chatGPTSignInRequired) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        XCTAssertNil(try store.loadTokens())
        let availability = await provider.availability()
        XCTAssertFalse(availability.isAvailable)
    }

    func testRejectedAccessTokenClearsSignIn() async throws {
        let (provider, http, store) = await makeProvider()
        await http.respond(to: "/v1/responses", status: 401, body: """
            {"error":{"message":"Invalid token"}}
            """)

        await assertError(.chatGPTSignInRequired) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        XCTAssertNil(try store.loadTokens())
        let availability = await provider.availability()
        XCTAssertFalse(availability.isAvailable)
    }

    func testRejectionOfReplacedAccessTokenKeepsCurrentSignIn() async throws {
        let (provider, _, store) = await makeProvider()

        for code in ["subscription_sharing_invalid_user", nil] {
            let error = await ChatGPTSubscriptionProvider.error(
                status: 401,
                code: code,
                message: nil,
                session: provider.session,
                rejectedAccessToken: "replaced-access"
            )
            XCTAssertEqual(error as? CommitMessageGenerationError, .chatGPTSignInRequired)
        }
        XCTAssertNotNil(try store.loadTokens())
        let availability = await provider.availability()
        XCTAssertTrue(availability.isAvailable)
    }

    func testFailedStreamEventMapsToPlanError() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: "/v1/responses", body: sse([
            #"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"Limit"}}}"#,
        ]))

        await assertError(.chatGPTUsageLimitReached) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
    }

    func testSignedOutProviderSendsNoRequest() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let http = ChatGPTStubHTTPClient()
        let provider = ChatGPTSubscriptionProvider(
            session: ChatGPTAccountSession(store: store, httpClient: http),
            modelStore: InMemoryAIProviderModelStore(),
            httpClient: http
        )

        await assertError(.chatGPTSignInRequired) {
            _ = try await provider.generateCommitMessage(request: self.makeCommitRequest())
        }
        let requests = await http.allRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testModelListKeepsListedSlugs() async throws {
        let (provider, http, _) = await makeProvider()
        await http.respond(to: "/v1/models", body: """
            {"models":[{"slug":"gpt-6.1-sol","visibility":"list"},{"slug":"internal","visibility":"hidden"},{"slug":"gpt-6-luna","visibility":"list"}]}
            """)

        let models = try await provider.availableModels()

        XCTAssertEqual(models.map(\.id), ["gpt-6.1-sol", "gpt-6-luna"])
        XCTAssertEqual(models.first?.name, "GPT-6.1 Sol")
        let requestRequests = await http.requests(path: "/v1/models")
        let request = try XCTUnwrap(requestRequests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
    }

    // MARK: Helpers

    private func makeProvider() async -> (ChatGPTSubscriptionProvider, ChatGPTStubHTTPClient, InMemoryChatGPTCredentialStore) {
        let store = InMemoryChatGPTCredentialStore(tokens: .expiring(at: Date().addingTimeInterval(3_000)))
        let http = ChatGPTStubHTTPClient()
        let provider = ChatGPTSubscriptionProvider(
            session: ChatGPTAccountSession(store: store, httpClient: http),
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
