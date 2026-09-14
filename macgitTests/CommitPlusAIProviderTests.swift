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
import Foundation
import XCTest
@testable import macgit

@MainActor
final class CommitPlusAIProviderTests: XCTestCase {
    func testAllFiveOperationsUseManagedTransportAndExistingDecoders() async throws {
        let sender = ManagedFixtureSender()
        let provider = CommitPlusAIProvider(client: sender, usage: CommitPlusAIUsageController(), canAccess: { true })
        let commit = try await provider.generateCommitMessage(request: makeRequest())
        XCTAssertEqual(commit.subject, "feat: Add feature")
        XCTAssertEqual(commit.body, "Explain the change")
        let answer = try await provider.generateRepositoryResponse(request: makeRepositoryRequest())
        XCTAssertEqual(answer.text, "Repository answer")
        let streamed = try await provider.streamRepositoryResponse(request: makeRepositoryRequest()) { _ in }
        XCTAssertEqual(streamed.text, "Repository answer")
        let conflict = try await provider.generateConflictResolution(request: makeConflictRequest())
        XCTAssertEqual(conflict.summary, "Needs review")
        let agent = try await provider.generateRepositoryAgentTurn(request: RepositoryAIAgentRequest(
            repositoryName: "macgit", branchName: "main", question: "Inspect status",
            conversation: [], previousToolResults: [], isFirstTurn: true))
        XCTAssertEqual(agent.text, "Agent answer")
        let requests = await sender.recorded()
        XCTAssertEqual(requests.map(\.operation), [.commitMessage, .repositoryResponse, .repositoryResponse, .conflictResolution, .repositoryAgent])
        XCTAssertEqual(requests.map(\.structured), [true, false, false, true, false])
        XCTAssertEqual(requests.map(\.streaming), [false, false, true, false, false])
        XCTAssertTrue(requests.allSatisfy { $0.messages.map(\.role).prefix(2) == ["system", "user"] })
        XCTAssertFalse(try XCTUnwrap(JSONSerialization.jsonObject(with: requests[4].tools) as? [Any]).isEmpty)
        XCTAssertNil(provider.descriptor.defaultModel)
        XCTAssertEqual(provider.descriptor.billing, .commitPlus)
    }

    func testFreeAccessNeverReachesTransport() async {
        let sender = ManagedFixtureSender()
        let provider = CommitPlusAIProvider(client: sender, usage: CommitPlusAIUsageController(), canAccess: { false })
        do {
            _ = try await provider.generateCommitMessage(request: makeRequest())
            XCTFail("Expected Pro gate")
        } catch { XCTAssertTrue(error is CommitPlusAIError) }
        let requests = await sender.recorded()
        XCTAssertTrue(requests.isEmpty)
    }

    func testMalformedConflictOutputFailsDecoding() async {
        let provider = CommitPlusAIProvider(client: ManagedFixtureSender(responseOverride: "{}"),
            usage: CommitPlusAIUsageController(), canAccess: { true })
        do {
            _ = try await provider.generateConflictResolution(request: makeConflictRequest())
            XCTFail("Incomplete conflict output must not become a plan")
        } catch { XCTAssertTrue(error is ConflictAIResolutionError) }
    }

    func testStructuredStreamingKeepsJSONOutOfTextDeltas() async throws {
        let sender = ManagedFixtureSender(responseOverride: #"{"text":"File answer","citations":[]}"#)
        let provider = CommitPlusAIProvider(client: sender, usage: CommitPlusAIUsageController(), canAccess: { true })
        let request = RepositoryAIRequest(repositoryName: "macgit", branchName: "main", question: "Explain file",
            toolResult: RepositoryAIToolResult(toolName: "read_file_context", title: "File", fingerprint: "one", content: "let value = 1", isTruncated: false))
        let answer = try await provider.streamRepositoryResponse(request: request) { _ in XCTFail("Structured JSON must not leak as partial text") }
        XCTAssertEqual(answer.text, "File answer")
        let requests = await sender.recorded()
        XCTAssertTrue(requests[0].structured)
        XCTAssertFalse(requests[0].streaming)
    }

    func testAgentFollowupPreservesToolIdentityAndOutput() async throws {
        let sender = ManagedFixtureSender()
        let provider = CommitPlusAIProvider(client: sender, usage: CommitPlusAIUsageController(), canAccess: { true })
        let previous = RepositoryAIAgentToolResult(toolCall: .init(id: "tool-one", name: "execute_git", arguments: ["status", "--short"]),
            commandResult: .init(displayCommand: "git status --short", output: "M file.swift", succeeded: true, isTruncated: false))
        _ = try await provider.generateRepositoryAgentTurn(request: .init(repositoryName: "macgit", branchName: "main", question: "Inspect",
            conversation: [], previousToolResults: [previous], isFirstTurn: false))
        let requests = await sender.recorded()
        XCTAssertEqual(requests[0].messages[2].toolCalls?.first?.id, "tool-one")
        XCTAssertNil(requests[0].messages[2].content)
        XCTAssertEqual(requests[0].messages[3].toolCallID, "tool-one")
        XCTAssertEqual(requests[0].messages[3].content, "M file.swift")
    }

    func testCancelledGenerationDoesNotReachTransport() async {
        let sender = ManagedFixtureSender()
        let provider = CommitPlusAIProvider(client: sender, usage: CommitPlusAIUsageController(), canAccess: { true })
        let request = makeRequest()
        let task = Task { try await provider.generateCommitMessage(request: request) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let requests = await sender.recorded()
        XCTAssertTrue(requests.isEmpty)
    }

    private func makeRequest() -> CommitMessageGenerationRequest {
        CommitMessageGenerationRequest(
            repositoryName: "macgit",
            branchName: "codex/byok-ai-providers",
            changeSource: .staged,
            changes: CommitChangeSnapshot(
                fingerprint: "tree-1",
                context: "M\tmacgit/App/AIProviderController.swift\n+save API key",
                isTruncated: false
            ),
            recentCommitSubjects: ["feat: Add Apple Intelligence generation"]
        )
    }

    private func makeRepositoryRequest(sessionID: String? = nil) -> RepositoryAIRequest {
        RepositoryAIRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review the current changes",
            toolResult: RepositoryAIToolResult(
                toolName: "working_tree_changes",
                title: "Working changes",
                fingerprint: "tree-1",
                content: "M\tmacgit/App/AIProviderController.swift",
                isTruncated: false
            ),
            sessionID: sessionID
        )
    }

    private func makeConflictRequest() -> ConflictAIResolutionRequest {
        ConflictAIResolutionRequest(snapshot: ConflictAIFileSnapshot(
            repositoryName: "macgit",
            branchName: "main",
            filePath: "Example.swift",
            fingerprint: "conflict-1",
            baseContent: "func value() { old() }\n",
            currentContent: "func value() { current() }\n",
            incomingContent: "func value() { incoming() }\n",
            sections: [ConflictAISectionSnapshot(
                sectionIndex: 0,
                contextBefore: "",
                currentText: "current()\n",
                incomingText: "incoming()\n",
                contextAfter: ""
            )],
            isTruncated: false
        ))
    }

}

private actor ManagedFixtureSender: CommitPlusAIRequestSending {
    struct Request: Sendable {
        let operation: CommitPlusAIOperation
        let messages: [CommitPlusAIWireMessage]
        let tools: Data
        let structured: Bool
        let streaming: Bool
    }
    private var requests: [Request] = []
    private let responseOverride: String?
    init(responseOverride: String? = nil) { self.responseOverride = responseOverride }
    func recorded() -> [Request] { requests }
    func send(operation: CommitPlusAIOperation, messages: [CommitPlusAIWireMessage], toolsData: Data,
              structured: Bool, onTextDelta: (@Sendable (String) async -> Void)?) async throws -> CommitPlusAIResult {
        requests.append(Request(operation: operation, messages: messages, tools: toolsData, structured: structured, streaming: onTextDelta != nil))
        let text: String
        switch operation {
        case .commitMessage: text = #"{"type":"feat","subject":"Add feature","body":"Explain the change"}"#
        case .repositoryResponse: text = "Repository answer"
        case .repositoryAgent: text = "Agent answer"
        case .conflictResolution: text = #"{"decisions":[],"summary":"Needs review"}"#
        }
        await onTextDelta?(text)
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/CommitPlusAI/allowance.json")
        return CommitPlusAIResult(requestID: UUID().uuidString, text: responseOverride ?? text, toolCalls: [],
            allowance: try JSONDecoder().decode(CommitPlusAIAllowance.self, from: Data(contentsOf: fixtureURL)), settlement: "settled")
    }
}
