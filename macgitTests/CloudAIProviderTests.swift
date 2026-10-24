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

final class CloudAIProviderTests: XCTestCase {
    @MainActor
    func testPersistedProProviderIsBlockedAfterDowngradeWithoutRemovingKeyOrSelection() async throws {
        let credentials = InMemoryAIProviderCredentialStore(keys: [.deepSeek: "saved-key"])
        let client = StubAIProviderHTTPClient(responseBody: #"{"choices":[{"message":{"role":"assistant","content":"{\"type\":\"feat\",\"subject\":\"Add feature\",\"body\":\"\"}"}}]}"#)
        var access = FeatureAccessDecision.allowed
        let defaults = makeDefaults()
        defaults.set(AIProviderID.deepSeek.rawValue, forKey: "ai.commitMessage.selectedProvider")
        let controller = AIProviderController(
            registry: .live(credentialStore: credentials, httpClient: client),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: defaults,
            credentialStore: credentials,
            restrictedProviderAccess: { access }
        )
        _ = try await controller.generateCommitMessage(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            branchName: "main", changeSource: .staged, recentCommitSubjects: []
        )
        access = .denied(.requiresPro)
        do {
            _ = try await controller.generateCommitMessage(
                repositoryURL: URL(fileURLWithPath: "/tmp/example"),
                branchName: "main", changeSource: .staged, recentCommitSubjects: []
            )
            XCTFail("Expected generation to reject the previously selected Pro provider")
        } catch let error as AIProviderConfigurationError {
            XCTAssertEqual(error, .unavailableOnCurrentPlan(providerName: "DeepSeek"))
        }
        do {
            _ = try await controller.answerRepositoryQuestionWithAgent(
                repositoryURL: URL(fileURLWithPath: "/tmp/example"),
                branchName: "main", question: "Explain this repository"
            )
            XCTFail("Expected chat to reject the previously selected Pro provider")
        } catch let error as AIProviderConfigurationError {
            XCTAssertEqual(error, .unavailableOnCurrentPlan(providerName: "DeepSeek"))
        }
        let countAfterDenial = await client.requestCount()
        XCTAssertEqual(countAfterDenial, 1)
        XCTAssertEqual(controller.selectedProviderID, .deepSeek)
        XCTAssertEqual(try credentials.apiKey(for: .deepSeek), "saved-key")
        XCTAssertFalse(controller.isGenerating)
        access = .allowed
        _ = try await controller.generateCommitMessage(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            branchName: "main", changeSource: .staged, recentCommitSubjects: []
        )
        let countAfterUpgrade = await client.requestCount()
        XCTAssertEqual(countAfterUpgrade, 2)
    }

    @MainActor
    func testFreeGenerationStillAllowsOpenAIAndGemini() async throws {
        for id in [AIProviderID.openAI, .googleGemini] {
            let credentials = InMemoryAIProviderCredentialStore(keys: [id: "saved-key"])
            let response = id == .openAI
                ? #"{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"type\":\"feat\",\"subject\":\"Add feature\",\"body\":\"\"}"}]}]}"#
                : #"{"candidates":[{"content":{"parts":[{"text":"{\"type\":\"feat\",\"subject\":\"Add feature\",\"body\":\"\"}"}]}}]}"#
            let client = StubAIProviderHTTPClient(responseBody: response)
            let controller = AIProviderController(
                registry: .live(credentialStore: credentials, httpClient: client),
                snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
                defaults: makeDefaults(), credentialStore: credentials,
                restrictedProviderAccess: { .denied(.requiresPro) }
            )
            controller.selectProvider(id)
            _ = try await controller.generateCommitMessage(
                repositoryURL: URL(fileURLWithPath: "/tmp/example"),
                branchName: "main", changeSource: .staged, recentCommitSubjects: []
            )
            let count = await client.requestCount()
            XCTAssertEqual(count, 1)
        }
    }

    @MainActor
    func testControllerSavesAndRemovesCloudAPIKeyWithoutExposingIt() async throws {
        let credentialStore = InMemoryAIProviderCredentialStore()
        let defaults = makeDefaults()
        let controller = AIProviderController(
            registry: .live(credentialStore: credentialStore),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: defaults,
            credentialStore: credentialStore
        )

        try controller.saveAPIKey("  secret-openai-key  ", for: .openAI)
        await controller.refreshAvailability()

        XCTAssertTrue(controller.isAPIKeyConfigured(for: .openAI))
        XCTAssertEqual(controller.availability(for: .openAI), .available)
        XCTAssertEqual(try credentialStore.apiKey(for: .openAI), "secret-openai-key")

        controller.selectProvider(.openAI)
        try controller.removeAPIKey(for: .openAI)

        XCTAssertFalse(controller.isAPIKeyConfigured(for: .openAI))
        XCTAssertNil(try credentialStore.apiKey(for: .openAI))
        XCTAssertEqual(controller.selectedProviderID, .appleIntelligence)
    }

    @MainActor
    func testControllerAppliesAllDraftedAPIKeyChangesTogether() throws {
        let credentialStore = InMemoryAIProviderCredentialStore(keys: [
            .openAI: "old-openai-key",
            .googleGemini: "old-gemini-key",
        ])
        let controller = AIProviderController(
            registry: .live(credentialStore: credentialStore),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: makeDefaults(),
            credentialStore: credentialStore
        )

        try controller.applyProviderChanges([
            AIProviderConfigurationDraft(
                id: .openAI,
                apiKey: " new-openai-key ",
                shouldRemoveAPIKey: true
            ),
            AIProviderConfigurationDraft(id: .anthropic, apiKey: "anthropic-key"),
            AIProviderConfigurationDraft(id: .googleGemini, shouldRemoveAPIKey: true),
        ], restrictedProviderAccess: .allowed)

        XCTAssertEqual(try credentialStore.apiKey(for: .openAI), "new-openai-key")
        XCTAssertEqual(try credentialStore.apiKey(for: .anthropic), "anthropic-key")
        XCTAssertNil(try credentialStore.apiKey(for: .googleGemini))
        XCTAssertTrue(controller.isAPIKeyConfigured(for: .openAI))
        XCTAssertTrue(controller.isAPIKeyConfigured(for: .anthropic))
        XCTAssertFalse(controller.isAPIKeyConfigured(for: .googleGemini))
    }

    @MainActor
    func testControllerLeavesConfiguredKeyUnchangedWhenDraftIsEmpty() async throws {
        let credentialStore = InMemoryAIProviderCredentialStore(keys: [
            .openAI: "existing-openai-key",
        ])
        let controller = AIProviderController(
            registry: .live(credentialStore: credentialStore),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: makeDefaults(),
            credentialStore: credentialStore
        )

        try controller.applyProviderChanges([
            AIProviderConfigurationDraft(id: .openAI),
        ], restrictedProviderAccess: .allowed)

        await controller.refreshAvailability()
        XCTAssertEqual(try credentialStore.apiKey(for: .openAI), "existing-openai-key")
        XCTAssertTrue(controller.isAPIKeyConfigured(for: .openAI))
    }

    @MainActor
    func testFreeAccessCanConfigureOpenAIAndGeminiButNotRestrictedProviders() throws {
        let credentialStore = InMemoryAIProviderCredentialStore()
        let controller = AIProviderController(
            registry: .live(credentialStore: credentialStore),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: makeDefaults(),
            credentialStore: credentialStore
        )

        try controller.applyProviderChanges([
            AIProviderConfigurationDraft(id: .openAI, apiKey: "openai-key"),
            AIProviderConfigurationDraft(id: .googleGemini, apiKey: "gemini-key"),
        ], restrictedProviderAccess: .denied(.requiresPro))

        XCTAssertEqual(try credentialStore.apiKey(for: .openAI), "openai-key")
        XCTAssertEqual(try credentialStore.apiKey(for: .googleGemini), "gemini-key")

        XCTAssertThrowsError(try controller.applyProviderChanges([
            AIProviderConfigurationDraft(id: .anthropic, apiKey: "anthropic-key"),
        ], restrictedProviderAccess: .denied(.requiresPro))) { error in
            XCTAssertEqual(
                error as? AIProviderConfigurationError,
                .requiresPro(providerName: "Claude")
            )
        }
        XCTAssertNil(try credentialStore.apiKey(for: .anthropic))

        for (id, name) in [(AIProviderID.deepSeek, "DeepSeek"), (.openRouter, "OpenRouter"), (.groq, "Groq")] {
            XCTAssertThrowsError(try controller.applyProviderChanges([
                AIProviderConfigurationDraft(id: id, apiKey: "restricted-key"),
            ], restrictedProviderAccess: .denied(.requiresPro))) { error in
                XCTAssertEqual(
                    error as? AIProviderConfigurationError,
                    .requiresPro(providerName: name)
                )
            }
            XCTAssertNil(try credentialStore.apiKey(for: id))
        }
    }

    @MainActor
    func testFreeAccessCanRemoveExistingRestrictedProviderKey() throws {
        let credentialStore = InMemoryAIProviderCredentialStore(keys: [.anthropic: "existing-key"])
        let controller = AIProviderController(
            registry: .live(credentialStore: credentialStore),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: makeDefaults(),
            credentialStore: credentialStore
        )

        try controller.applyProviderChanges([
            AIProviderConfigurationDraft(id: .anthropic, shouldRemoveAPIKey: true),
        ], restrictedProviderAccess: .denied(.requiresPro))

        XCTAssertNil(try credentialStore.apiKey(for: .anthropic))
    }

    @MainActor
    func testExistingRestrictedProviderCanCustomizeAndResetModelOnFreePlan() throws {
        let credentialStore = InMemoryAIProviderCredentialStore(keys: [.anthropic: "existing-key"])
        let modelStore = InMemoryAIProviderModelStore()
        let controller = AIProviderController(
            registry: .live(credentialStore: credentialStore, modelStore: modelStore),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: makeDefaults(),
            credentialStore: credentialStore,
            modelStore: modelStore
        )
        let descriptor = try XCTUnwrap(controller.descriptors.first { $0.id == .anthropic })

        try controller.applyProviderChanges([
            AIProviderConfigurationDraft(id: .anthropic, model: "  claude-custom  "),
        ], restrictedProviderAccess: .denied(.requiresPro))

        XCTAssertEqual(modelStore.customModel(for: .anthropic), "claude-custom")
        XCTAssertEqual(controller.model(for: descriptor), "claude-custom")

        try controller.applyProviderChanges([
            AIProviderConfigurationDraft(id: .anthropic, model: "claude-haiku-5-5"),
        ], restrictedProviderAccess: .denied(.requiresPro))

        XCTAssertNil(modelStore.customModel(for: .anthropic))
        XCTAssertEqual(controller.model(for: descriptor), "claude-haiku-5-5")
    }

    func testOpenAIRequestUsesBearerKeyAndParsesStructuredResponse() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openAI: "openai-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.openAI: "gpt-custom"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"output":[{"content":[{"type":"output_text","text":"{\\"type\\":\\"feat\\",\\"subject\\":\\"Configure cloud AI providers\\",\\"body\\":\\"\\"}"}]}]}
            """)
        let provider = OpenAICommitMessageProvider(
            credentialStore: store,
            modelStore: modelStore,
            httpClient: client
        )

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-secret")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(result.text, "feat: Configure cloud AI providers")
        let body = try requestJSONObject(request)
        XCTAssertEqual(body["model"] as? String, "gpt-custom")
        XCTAssertNil(body["reasoning"])
        XCTAssertEqual((body["store"] as? Bool), false)
    }

    func testOpenAIConflictRequestUsesStrictSchemaAndParsesReplacement() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openAI: "openai-secret"])
        let plan = """
            {"decisions":[{"sectionIndex":0,"action":"replace","replacementText":"merged()\\n","reason":"Combines both implementations","question":"","options":[]}],"summary":"Merged both behaviors"}
            """
        let responseData = try JSONSerialization.data(withJSONObject: [
            "output": [["content": [["type": "output_text", "text": plan]]]],
        ])
        let client = StubAIProviderHTTPClient(responseBody: String(decoding: responseData, as: UTF8.self))
        let provider = OpenAICommitMessageProvider(
            credentialStore: store,
            httpClient: client
        )

        let result = try await provider.generateConflictResolution(request: makeConflictRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)
        let body = try requestJSONObject(request)
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])

        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(result.decisions.first?.action, .replace)
        XCTAssertEqual(result.decisions.first?.replacementText, "merged()\n")
    }

    func testOpenAIAgentRequestUsesStrictGitToolAndCarriesToolOutput() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openAI: "openai-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"output":[{"type":"function_call","call_id":"call_staged","name":"execute_git","arguments":"{\\"arguments\\":[\\"diff\\",\\"--cached\\"]}"}]}
            """)
        let provider = OpenAICommitMessageProvider(
            credentialStore: store,
            httpClient: client
        )
        let priorCall = RepositoryAIAgentToolCall(
            id: "call_status",
            name: "execute_git",
            arguments: ["status", "--short"]
        )
        let request = RepositoryAIAgentRequest(
            repositoryName: "Example",
            branchName: "main",
            question: "Review staged files",
            conversation: [],
            previousToolResults: [RepositoryAIAgentToolResult(
                toolCall: priorCall,
                commandResult: RepositoryAIGitCommandResult(
                    displayCommand: "git status --short",
                    output: "M  App.swift",
                    succeeded: true,
                    isTruncated: false
                )
            )],
            isFirstTurn: false
        )

        let turn = try await provider.generateRepositoryAgentTurn(request: request)
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let tool = try XCTUnwrap(tools.first)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])

        XCTAssertEqual(tool["name"] as? String, "execute_git")
        XCTAssertEqual(tool["strict"] as? Bool, true)
        XCTAssertEqual(input.dropFirst().first?["type"] as? String, "function_call")
        XCTAssertEqual(input.last?["type"] as? String, "function_call_output")
        XCTAssertEqual(input.last?["call_id"] as? String, "call_status")
        XCTAssertEqual(turn.toolCalls.first?.arguments, ["diff", "--cached"])
    }

    func testOpenAIAgentFirstTurnOffersQuickActionsAndParsesSelection() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openAI: "openai-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"output":[{"type":"function_call","call_id":"call_review_file","name":"review_file","arguments":"{}"}]}
            """)
        let provider = OpenAICommitMessageProvider(
            credentialStore: store,
            httpClient: client
        )
        let request = RepositoryAIAgentRequest(
            repositoryName: "Example",
            branchName: "main",
            question: "review file",
            conversation: [],
            previousToolResults: [],
            isFirstTurn: true
        )

        let turn = try await provider.generateRepositoryAgentTurn(request: request)
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })

        XCTAssertEqual(names, Set([
            "execute_git",
            "review_changes",
            "explain_commit",
            "review_file",
            "compare_refs",
            "analyze_pull_request",
        ]))
        XCTAssertEqual(turn.toolCalls.first?.name, "review_file")
        XCTAssertEqual(turn.toolCalls.first?.arguments, [])
    }

    func testAnthropicRequestUsesRequiredHeadersAndParsesResponse() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.anthropic: "anthropic-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.anthropic: "claude-custom"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"content":[{"type":"text","text":"{\\"type\\":\\"fix\\",\\"subject\\":\\"Handle provider API errors\\",\\"body\\":\\"Surface actionable failures to users.\\"}"}]}
            """)
        let provider = AnthropicCommitMessageProvider(
            credentialStore: store,
            modelStore: modelStore,
            httpClient: client
        )

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(result.subject, "fix: Handle provider API errors")
        XCTAssertEqual(result.body, "Surface actionable failures to users.")
        let body = try requestJSONObject(request)
        XCTAssertEqual(body["model"] as? String, "claude-custom")
        XCTAssertNotNil(body["output_config"])
    }

    func testAnthropicLowersEffortWhenThinkingCannotBeDisabled() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.anthropic: "anthropic-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.anthropic: "claude-opus-5-5"], thinkingEnabled: false)
        let client = StubAIProviderHTTPClient(responseBody: """
            {"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\\"type\\":\\"fix\\",\\"subject\\":\\"Handle errors\\",\\"body\\":\\"\\"}"}]}
            """)
        let provider = AnthropicCommitMessageProvider(credentialStore: store, modelStore: modelStore, httpClient: client)

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))

        XCTAssertEqual(result.subject, "fix: Handle errors")
        XCTAssertNil(body["thinking"])
        let outputConfig = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "low")
        XCTAssertNotNil(outputConfig["format"])
        XCTAssertEqual(body["max_tokens"] as? Int, 250 + AIThinkingPolicy.minimalReasoningHeadroom)
    }

    func testAnthropicAgentDoesNotForceToolUseWhileThinking() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.anthropic: "anthropic-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.anthropic: "claude-haiku-5-5"], thinkingEnabled: true)
        let client = StubAIProviderHTTPClient(responseBody: """
            {"content":[{"type":"tool_use","id":"toolu_1","name":"review_file","input":{}}]}
            """)
        let provider = AnthropicCommitMessageProvider(credentialStore: store, modelStore: modelStore, httpClient: client)
        let request = RepositoryAIAgentRequest(
            repositoryName: "Example",
            branchName: "main",
            question: "review file",
            conversation: [],
            previousToolResults: [],
            isFirstTurn: true
        )

        _ = try await provider.generateRepositoryAgentTurn(request: request)
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))

        XCTAssertNil(body["tool_choice"])
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "adaptive")
    }

    func testAnthropicAgentReplaysThinkingBlocksWithTheirToolUses() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.anthropic: "anthropic-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.anthropic: "claude-haiku-5-5"], thinkingEnabled: true)
        let client = StubAIProviderHTTPClient(responseBody: """
            {"id":"msg_1","content":[{"type":"thinking","thinking":"Check the diff.","signature":"sig-1"},{"type":"redacted_thinking","data":"opaque"},{"type":"tool_use","id":"toolu_1","name":"execute_git","input":{"arguments":["status"]}},{"type":"tool_use","id":"toolu_2","name":"execute_git","input":{"arguments":["diff"]}}]}
            """)
        let provider = AnthropicCommitMessageProvider(credentialStore: store, modelStore: modelStore, httpClient: client)
        let firstTurn = try await provider.generateRepositoryAgentTurn(request: RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review changes",
            conversation: [],
            previousToolResults: [],
            isFirstTurn: true
        ))
        let results = firstTurn.toolCalls.map { call in
            RepositoryAIAgentToolResult(
                toolCall: call,
                commandResult: RepositoryAIGitCommandResult(
                    displayCommand: "git \(call.arguments.joined(separator: " "))",
                    output: "output \(call.id)",
                    succeeded: true,
                    isTruncated: false
                )
            )
        }

        _ = try await provider.generateRepositoryAgentTurn(request: RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review changes",
            conversation: [],
            previousToolResults: results,
            isFirstTurn: false
        ))
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let firstTurnToolNames = RepositoryAIAgentToolSchema
            .declarations(includingQuickActions: true)
            .compactMap { $0["name"] as? String }

        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, firstTurnToolNames)
        XCTAssertEqual(messages.count, 3)
        let assistantContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantContent.map { $0["type"] as? String }, ["thinking", "redacted_thinking", "tool_use", "tool_use"])
        XCTAssertEqual(assistantContent[0]["thinking"] as? String, "Check the diff.")
        XCTAssertEqual(assistantContent[0]["signature"] as? String, "sig-1")
        XCTAssertEqual(assistantContent[1]["data"] as? String, "opaque")
        XCTAssertEqual(assistantContent.compactMap { $0["id"] as? String }, ["toolu_1", "toolu_2"])
        let resultContent = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(resultContent.compactMap { $0["tool_use_id"] as? String }, ["toolu_1", "toolu_2"])
    }

    func testAnthropicAgentRetriesFirstTurnOnceWhenToolUseCannotBeForced() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.anthropic: "anthropic-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.anthropic: "claude-sonnet-5-5"])
        let client = StubAIProviderHTTPClient(responseBodies: [
            #"{"content":[{"type":"text","text":"Looks fine."}]}"#,
            #"{"content":[{"type":"tool_use","id":"toolu_1","name":"execute_git","input":{"arguments":["status"]}}]}"#,
        ])
        let provider = AnthropicCommitMessageProvider(credentialStore: store, modelStore: modelStore, httpClient: client)

        let turn = try await provider.generateRepositoryAgentTurn(request: RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review changes",
            conversation: [],
            previousToolResults: [],
            isFirstTurn: true
        ))
        let requestCount = await client.requestCount()
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))

        XCTAssertEqual(requestCount, 2)
        XCTAssertNil(body["tool_choice"])
        XCTAssertEqual(turn.toolCalls.map(\.name), ["execute_git"])
    }

    func testAnthropicAgentKeepsThinkingSettingForTheWholeLoop() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.anthropic: "anthropic-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.anthropic: "claude-sonnet-4-5"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"id":"msg_1","content":[{"type":"tool_use","id":"toolu_1","name":"execute_git","input":{"arguments":["status"]}}]}
            """)
        let provider = AnthropicCommitMessageProvider(credentialStore: store, modelStore: modelStore, httpClient: client)
        let firstTurn = try await provider.generateRepositoryAgentTurn(request: RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review changes",
            conversation: [],
            previousToolResults: [],
            isFirstTurn: true
        ))
        let results = firstTurn.toolCalls.map { call in
            RepositoryAIAgentToolResult(
                toolCall: call,
                commandResult: RepositoryAIGitCommandResult(
                    displayCommand: "git status",
                    output: "clean",
                    succeeded: true,
                    isTruncated: false
                )
            )
        }
        modelStore.setThinkingEnabled(true)

        _ = try await provider.generateRepositoryAgentTurn(request: RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review changes",
            conversation: [],
            previousToolResults: results,
            isFirstTurn: false
        ))
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))

        // The replayed tool use has no thinking block, so thinking must stay off.
        XCTAssertNil(body["thinking"])
    }

    func testOpenRouterCapabilityStoreBacksOffAfterAFailedLoad() async {
        let client = StubAIProviderHTTPClient(responseBody: "{}", statusCode: 503)
        let capabilities = OpenRouterReasoningCapabilityStore(httpClient: client)

        let first = await capabilities.capability(for: "z-ai/glm-5.3-flash")
        let second = await capabilities.capability(for: "z-ai/glm-5.3-flash")
        let requestCount = await client.requestCount()

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(requestCount, 1)
    }

    func testOpenRouterCapabilityStoreRefreshesForUnknownModelsAfterInterval() async {
        let client = StubAIProviderHTTPClient(responseBodies: [
            #"{"data":[]}"#,
            #"{"data":[{"id":"new/model","reasoning":{"mandatory":false,"supported_efforts":["none","low"]}}]}"#,
        ])
        let clock = TestClock()
        let capabilities = OpenRouterReasoningCapabilityStore(httpClient: client, now: { clock.now })

        let before = await capabilities.capability(for: "new/model")
        let cached = await capabilities.capability(for: "new/model")
        clock.advance(by: OpenRouterReasoningCapabilityStore.unknownModelRefreshInterval)
        let after = await capabilities.capability(for: "new/model")
        let requestCount = await client.requestCount()

        XCTAssertNil(before)
        XCTAssertNil(cached)
        XCTAssertEqual(after?.supportedEfforts, ["none", "low"])
        XCTAssertEqual(requestCount, 2)
    }

    func testGeminiRequestUsesHeaderKeyAndStructuredOutputSchema() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.googleGemini: "gemini-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.googleGemini: "gemini-custom"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"candidates":[{"content":{"parts":[{"thought":true,"text":"internal reasoning"},{"text":"{\\"type\\":\\"chore\\",\\"subject\\":\\"Store AI keys in Keychain\\",\\"body\\":\\"\\"}"}]},"finishReason":"STOP"}]}
            """)
        let provider = GeminiCommitMessageProvider(
            credentialStore: store,
            modelStore: modelStore,
            httpClient: client
        )

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-secret")
        XCTAssertEqual(result.text, "chore: Store AI keys in Keychain")
        let body = try requestJSONObject(request)
        let generationConfig = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["responseMimeType"] as? String, "application/json")
        let responseJSONSchema = try XCTUnwrap(generationConfig["responseJsonSchema"] as? [String: Any])
        XCTAssertEqual(responseJSONSchema["additionalProperties"] as? Bool, false)
        XCTAssertNil(generationConfig["responseSchema"])
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-custom:generateContent"
        )
        XCTAssertEqual(generationConfig["maxOutputTokens"] as? Int, 512)
        let thinkingConfig = try XCTUnwrap(generationConfig["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinkingConfig["thinkingLevel"] as? String, "MINIMAL")
        XCTAssertNil(thinkingConfig["thinkingBudget"])
        XCTAssertEqual(thinkingConfig["includeThoughts"] as? Bool, false)
    }

    func testGeminiReportsOutputLimitInsteadOfInvalidResponse() async {
        let store = InMemoryAIProviderCredentialStore(keys: [.googleGemini: "gemini-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"candidates":[{"content":{"parts":[]},"finishReason":"MAX_TOKENS"}]}
            """)
        let provider = GeminiCommitMessageProvider(credentialStore: store, httpClient: client)

        do {
            _ = try await provider.generateCommitMessage(request: makeRequest())
            XCTFail("Expected an output-limit error")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(
                error,
                .providerRequestFailed(
                    "Gemini reached its output limit before returning a commit message. Try generating from a smaller change."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiAgentUsesCompatibleFunctionSchemaAndMatchesCallIDs() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.googleGemini: "gemini-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.googleGemini: "gemini-custom"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"candidates":[{"content":{"parts":[{"thoughtSignature":"opaque-gemini-thought-signature","functionCall":{"id":"gemini-call-1","name":"execute_git","args":{"arguments":["diff","--cached"]}}}]}}]}
            """)
        let provider = GeminiCommitMessageProvider(
            credentialStore: store,
            modelStore: modelStore,
            httpClient: client
        )
        let firstRequest = RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review staged files",
            conversation: [],
            previousToolResults: [],
            isFirstTurn: true
        )
        let firstTurn = try await provider.generateRepositoryAgentTurn(request: firstRequest)
        let call = try XCTUnwrap(firstTurn.toolCalls.first)
        let request = RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review staged files",
            conversation: [],
            previousToolResults: [RepositoryAIAgentToolResult(
                toolCall: call,
                commandResult: RepositoryAIGitCommandResult(
                    displayCommand: "git diff --cached",
                    output: "diff --git a/App.swift b/App.swift",
                    succeeded: true,
                    isTruncated: false
                )
            )],
            isFirstTurn: false
        )

        let turn = try await provider.generateRepositoryAgentTurn(request: request)
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let declarations = try XCTUnwrap(tools.first?["functionDeclarations"] as? [[String: Any]])
        let parameters = try XCTUnwrap(declarations.first?["parameters"] as? [String: Any])
        let functionCallingConfig = try XCTUnwrap(
            (try XCTUnwrap(body["toolConfig"] as? [String: Any]))["functionCallingConfig"] as? [String: Any]
        )
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let functionCallPart = try XCTUnwrap(
            (contents.dropLast().last?["parts"] as? [[String: Any]])?.first
        )
        let functionCall = try XCTUnwrap(functionCallPart["functionCall"] as? [String: Any])
        let functionResponse = try XCTUnwrap(
            (contents.last?["parts"] as? [[String: Any]])?.first?["functionResponse"] as? [String: Any]
        )

        XCTAssertNil(parameters["additionalProperties"])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(functionCallingConfig["mode"] as? String, "AUTO")
        XCTAssertNil(functionCallingConfig["allowedFunctionNames"])
        XCTAssertEqual(functionCall["id"] as? String, "gemini-call-1")
        XCTAssertEqual(functionResponse["id"] as? String, "gemini-call-1")
        XCTAssertEqual(functionCallPart["thoughtSignature"] as? String, "opaque-gemini-thought-signature")
        XCTAssertEqual(turn.toolCalls.first?.id, "gemini-call-1")
        XCTAssertEqual(turn.toolCalls.first?.arguments, ["diff", "--cached"])
        XCTAssertEqual(call.geminiFunctionCallState?.thoughtSignature, "opaque-gemini-thought-signature")
    }

    func testDeepSeekRequestUsesBearerKeyAndJSONMode() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.deepSeek: "deepseek-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.deepSeek: "deepseek-custom"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"choices":[{"message":{"role":"assistant","content":"{\\"type\\":\\"feat\\",\\"subject\\":\\"Add DeepSeek generation\\",\\"body\\":\\"\\"}"}}]}
            """)
        let provider = DeepSeekCommitMessageProvider(
            credentialStore: store,
            modelStore: modelStore,
            httpClient: client
        )

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer deepseek-secret")
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(result.text, "feat: Add DeepSeek generation")
        let body = try requestJSONObject(request)
        XCTAssertEqual(body["model"] as? String, "deepseek-custom")
        XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
    }

    func testGroqRequestUsesBearerKeyAndJSONMode() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.groq: "groq-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.groq: "groq-custom"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"choices":[{"message":{"role":"assistant","content":"{\\"type\\":\\"feat\\",\\"subject\\":\\"Add Groq generation\\",\\"body\\":\\"\\"}"}}]}
            """)
        let provider = GroqCommitMessageProvider(
            credentialStore: store,
            modelStore: modelStore,
            httpClient: client
        )

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer groq-secret")
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(result.text, "feat: Add Groq generation")
        let body = try requestJSONObject(request)
        XCTAssertEqual(body["model"] as? String, "groq-custom")
        XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        XCTAssertNil(body["thinking"])
    }

    func testGroqRecoversJSONFromFailedGeneration() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.groq: "groq-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"error":{"message":"Failed to validate JSON.","type":"invalid_request_error","code":"json_validate_failed","failed_generation":"Here it is: {\\"type\\":\\"feat\\",\\"subject\\":\\"Add Groq\\",\\"body\\":\\"\\"}"}}
            """, statusCode: 400)
        let provider = GroqCommitMessageProvider(
            credentialStore: store,
            modelStore: InMemoryAIProviderModelStore(models: [.groq: "llama-3.3-70b-versatile"]),
            httpClient: client
        )

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let requestCount = await client.requestCount()

        XCTAssertEqual(result.subject, "feat: Add Groq")
        XCTAssertEqual(requestCount, 1)
    }

    func testOpenRouterUsesLowestEffortForMandatoryReasoningWhenThinkingIsOff() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openRouter: "openrouter-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.openRouter: "z-ai/glm-5.3-flash"])
        let capabilities = OpenRouterReasoningCapabilityStore(httpClient: StubAIProviderHTTPClient(responseBody: """
            {"data":[{"id":"z-ai/glm-5.3-flash","reasoning":{"mandatory":true,"supported_efforts":["max","high","low"]}}]}
            """))
        let client = StubAIProviderHTTPClient(responseBody: """
            {"choices":[{"message":{"role":"assistant","content":"{\\"type\\":\\"feat\\",\\"subject\\":\\"Add GLM\\",\\"body\\":\\"\\"}"}}]}
            """)
        let provider = OpenRouterCommitMessageProvider(
            credentialStore: store,
            modelStore: modelStore,
            httpClient: client,
            reasoningCapabilities: capabilities
        )

        _ = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))

        let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "low")
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 250 + AIThinkingPolicy.minimalReasoningHeadroom)
    }

    func testDeepSeekAgentAcceptsAnEquivalentRawArgumentArray() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.deepSeek: "deepseek-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"call-1","function":{"name":"execute_git","arguments":"[\\"diff\\",\\"--cached\\"]"}}]}}]}
            """)
        let provider = DeepSeekCommitMessageProvider(credentialStore: store, httpClient: client)
        let request = RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review changes",
            conversation: [],
            previousToolResults: [],
            isFirstTurn: true
        )

        let turn = try await provider.generateRepositoryAgentTurn(request: request)

        XCTAssertEqual(turn.toolCalls.first?.name, "execute_git")
        XCTAssertEqual(turn.toolCalls.first?.arguments, ["diff", "--cached"])
    }

    func testDeepSeekAgentKeepsThinkingDisabledWithForcedToolUse() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.deepSeek: "deepseek-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.deepSeek: "deepseek-custom"], thinkingEnabled: true)
        let client = StubAIProviderHTTPClient(responseBody: """
            {"choices":[{"message":{"role":"assistant","tool_calls":[{"id":"call-1","function":{"name":"execute_git","arguments":"{\\"arguments\\":[\\"status\\"]}"}}]}}]}
            """)
        let provider = DeepSeekCommitMessageProvider(credentialStore: store, modelStore: modelStore, httpClient: client)

        _ = try await provider.generateRepositoryAgentTurn(request: RepositoryAIAgentRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review changes",
            conversation: [],
            previousToolResults: [],
            isFirstTurn: true
        ))
        let receivedRequest = await client.receivedRequest()
        let body = try requestJSONObject(try XCTUnwrap(receivedRequest))

        XCTAssertEqual(body["tool_choice"] as? String, "required")
        XCTAssertEqual((body["thinking"] as? [String: Any])?["type"] as? String, "disabled")
        XCTAssertEqual(body["max_tokens"] as? Int, 1_200)
    }

    func testOpenRouterRequestUsesBearerKeyAndStructuredOutput() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openRouter: "openrouter-secret"])
        let modelStore = InMemoryAIProviderModelStore(models: [.openRouter: "vendor/model"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"choices":[{"message":{"role":"assistant","content":"{\\"type\\":\\"fix\\",\\"subject\\":\\"Route commit generation\\",\\"body\\":\\"Require structured output support.\\"}"}}]}
            """)
        let provider = OpenRouterCommitMessageProvider(
            credentialStore: store,
            modelStore: modelStore,
            httpClient: client,
            reasoningCapabilities: .offline
        )

        let result = try await provider.generateCommitMessage(request: makeRequest())
        let receivedRequest = await client.receivedRequest()
        let request = try XCTUnwrap(receivedRequest)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openrouter-secret")
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(result.subject, "fix: Route commit generation")
        XCTAssertEqual(result.body, "Require structured output support.")
        let body = try requestJSONObject(request)
        XCTAssertEqual(body["model"] as? String, "vendor/model")
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let providerRouting = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(providerRouting["require_parameters"] as? Bool, true)
        let plugins = try XCTUnwrap(body["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.first?["id"] as? String, "response-healing")
    }

    func testOpenRouterParsesTextPartsAndEmbeddedJSON() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openRouter: "openrouter-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"choices":[{"message":{"role":"assistant","content":[{"type":"text","text":"Commit message:\\n```json\\n{\\"type\\":\\"feat\\",\\"subject\\":\\"Parse OpenRouter content parts\\",\\"body\\":null}\\n```"}]}}]}
            """)
        let provider = OpenRouterCommitMessageProvider(
            credentialStore: store,
            httpClient: client,
            reasoningCapabilities: .offline
        )

        let result = try await provider.generateCommitMessage(request: makeRequest())

        XCTAssertEqual(result.text, "feat: Parse OpenRouter content parts")
    }

    func testOpenRouterSurfacesEmbeddedProviderError() async {
        let store = InMemoryAIProviderCredentialStore(keys: [.openRouter: "openrouter-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"choices":[{"finish_reason":"error","message":{"role":"assistant","content":""},"error":{"code":502,"message":"Provider disconnected mid-stream"}}]}
            """)
        let provider = OpenRouterCommitMessageProvider(
            credentialStore: store,
            httpClient: client,
            reasoningCapabilities: .offline
        )

        do {
            _ = try await provider.generateCommitMessage(request: makeRequest())
            XCTFail("Expected the embedded OpenRouter error")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(
                error,
                .providerRequestFailed(
                    "OpenRouter request failed: Provider disconnected mid-stream"
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenRouterRepositoryResponseUsesStableSessionID() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openRouter: "openrouter-secret"])
        let client = StubAIProviderHTTPClient(responseBody: """
            {"model":"anthropic/claude-sonnet-4.5","choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"No material issues found."}}]}
            """)
        let provider = OpenRouterCommitMessageProvider(
            credentialStore: store,
            httpClient: client,
            reasoningCapabilities: .offline
        )

        let result = try await provider.generateRepositoryResponse(
            request: makeRepositoryRequest(sessionID: "repository-chat-session")
        )
        let request = await client.receivedRequest()
        let receivedRequest = try XCTUnwrap(request)
        let body = try requestJSONObject(receivedRequest)

        XCTAssertEqual(result.text, "No material issues found.")
        XCTAssertEqual(body["session_id"] as? String, "repository-chat-session")
    }

    func testOpenRouterRepositoryResponseRetriesMissingContentOnce() async throws {
        let store = InMemoryAIProviderCredentialStore(keys: [.openRouter: "openrouter-secret"])
        let client = StubAIProviderHTTPClient(responseBodies: [
            """
            {"model":"google/gemini-3.5-flash","choices":[{"finish_reason":"length","message":{"role":"assistant","content":null}}]}
            """,
            """
            {"model":"anthropic/claude-sonnet-4.5","choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Recovered response."}}]}
            """,
        ])
        let provider = OpenRouterCommitMessageProvider(
            credentialStore: store,
            httpClient: client,
            reasoningCapabilities: .offline
        )

        let result = try await provider.generateRepositoryResponse(
            request: makeRepositoryRequest(sessionID: "repository-chat-session")
        )

        XCTAssertEqual(result.text, "Recovered response.")
        let requestCount = await client.requestCount()
        XCTAssertEqual(requestCount, 2)
    }

    func testOpenRouterRepositoryResponseReportsResolvedModelAfterRetry() async {
        let store = InMemoryAIProviderCredentialStore(keys: [.openRouter: "openrouter-secret"])
        let response = """
            {"model":"google/gemini-3.5-flash","choices":[{"finish_reason":"length","message":{"role":"assistant","content":null}}]}
            """
        let client = StubAIProviderHTTPClient(responseBodies: [response, response])
        let provider = OpenRouterCommitMessageProvider(
            credentialStore: store,
            httpClient: client,
            reasoningCapabilities: .offline
        )

        do {
            _ = try await provider.generateRepositoryResponse(
                request: makeRepositoryRequest(sessionID: "repository-chat-session")
            )
            XCTFail("Expected the missing response to fail")
        } catch let error as RepositoryAIError {
            XCTAssertEqual(
                error,
                .invalidResponse(
                    "OpenRouter (google/gemini-3.5-flash) reached its output limit before returning a final answer."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloudProviderRejectsGenerationWithoutAPIKey() async {
        let provider = OpenAICommitMessageProvider(
            credentialStore: InMemoryAIProviderCredentialStore(),
            httpClient: StubAIProviderHTTPClient(responseBody: "{}")
        )

        do {
            _ = try await provider.generateCommitMessage(request: makeRequest())
            XCTFail("Expected a missing API key error")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(error, .missingAPIKey("OpenAI"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    private func requestJSONObject(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    private func makeDefaults() -> UserDefaults {
        let suiteName = "CloudAIProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        return defaults ?? .standard
    }
}

extension CloudAIProviderTests {
    @MainActor
    func testChatGPTIsSelectableOnlyWhenSignedInAvailableAndAllowed() async throws {
        let signedOut = makeChatGPTController(tokens: nil)
        await signedOut.controller.refreshAvailability()
        let descriptor = try XCTUnwrap(signedOut.controller.descriptors.first { $0.id == .chatGPTSubscription })
        XCTAssertEqual(descriptor.billing, .connectedAccount)
        XCTAssertFalse(signedOut.controller.isAPIKeyConfigured(for: .chatGPTSubscription))
        XCTAssertFalse(signedOut.controller.canSelect(descriptor, restrictedProviderAccess: .allowed))

        let signedIn = makeChatGPTController(tokens: .expiring(at: Date().addingTimeInterval(3_000)))
        await signedIn.controller.refreshAvailability()
        XCTAssertTrue(signedIn.controller.isAPIKeyConfigured(for: .chatGPTSubscription))
        XCTAssertEqual(signedIn.controller.connectedAccount(for: .chatGPTSubscription)?.email, "dev@example.com")
        XCTAssertTrue(signedIn.controller.canSelect(descriptor, restrictedProviderAccess: .allowed))
        XCTAssertFalse(signedIn.controller.canSelect(descriptor, restrictedProviderAccess: .denied(.requiresPro)))

        await signedIn.session.recordPlanIssue(.notEligible)
        signedIn.controller.invalidateAvailability()
        await signedIn.controller.refreshAvailability()
        XCTAssertFalse(signedIn.controller.canSelect(descriptor, restrictedProviderAccess: .allowed))
    }

    @MainActor
    func testOpenAIAndChatGPTAreSeparateProviders() async throws {
        let credentialStore = InMemoryAIProviderCredentialStore(keys: [.openAI: "openai-key"])
        let chatGPT = makeChatGPTController(
            tokens: .expiring(at: Date().addingTimeInterval(3_000)),
            credentialStore: credentialStore
        )
        await chatGPT.controller.refreshAvailability()

        XCTAssertTrue(chatGPT.controller.isAPIKeyConfigured(for: .openAI))
        XCTAssertTrue(chatGPT.controller.isAPIKeyConfigured(for: .chatGPTSubscription))
        chatGPT.controller.selectProvider(.chatGPTSubscription)
        XCTAssertEqual(chatGPT.controller.selectedProviderID, .chatGPTSubscription)
        chatGPT.controller.selectProvider(.openAI)
        XCTAssertEqual(chatGPT.controller.selectedProviderID, .openAI)
    }

    @MainActor
    func testDisconnectingDefaultChatGPTFallsBackToAppleIntelligence() async throws {
        let chatGPT = makeChatGPTController(tokens: .expiring(at: Date().addingTimeInterval(3_000)))
        await chatGPT.controller.refreshAvailability()
        chatGPT.controller.selectProvider(.chatGPTSubscription)
        XCTAssertEqual(chatGPT.controller.selectedProviderID, .chatGPTSubscription)

        await chatGPT.controller.disconnect(.chatGPTSubscription)

        XCTAssertNil(try chatGPT.store.loadTokens())
        XCTAssertNil(chatGPT.controller.connectedAccount(for: .chatGPTSubscription))
        XCTAssertFalse(chatGPT.controller.isAPIKeyConfigured(for: .chatGPTSubscription))
        XCTAssertEqual(chatGPT.controller.selectedProviderID, .appleIntelligence)
        let availability = await chatGPT.session.availability()
        XCTAssertFalse(availability.isAvailable)
    }

    @MainActor
    func testOpenAIChatGPTAndCodexStayIndependent() async throws {
        let credentialStore = InMemoryAIProviderCredentialStore(keys: [.openAI: "openai-key"])
        let providers = makeChatGPTController(
            tokens: .expiring(at: Date().addingTimeInterval(3_000)),
            codexTokens: .expiring(at: Date().addingTimeInterval(3_000)),
            credentialStore: credentialStore
        )
        await providers.controller.refreshAvailability()

        for id in [AIProviderID.openAI, .chatGPTSubscription, .chatGPTCodex] {
            XCTAssertTrue(providers.controller.isAPIKeyConfigured(for: id))
        }

        await providers.controller.disconnect(.chatGPTCodex)

        XCTAssertNil(try providers.codexStore.loadTokens())
        XCTAssertNotNil(try providers.store.loadTokens())
        XCTAssertEqual(try credentialStore.apiKey(for: .openAI), "openai-key")
        XCTAssertFalse(providers.controller.isAPIKeyConfigured(for: .chatGPTCodex))
        await providers.controller.refreshAvailability()
        XCTAssertTrue(providers.controller.isAPIKeyConfigured(for: .chatGPTSubscription))
        XCTAssertTrue(providers.controller.isAPIKeyConfigured(for: .openAI))
        XCTAssertTrue(providers.controller.availability(for: .chatGPTSubscription).isAvailable)
    }

    @MainActor
    func testDisconnectingDefaultCodexFallsBackToAppleIntelligence() async throws {
        let providers = makeChatGPTController(tokens: nil, codexTokens: .expiring(at: Date().addingTimeInterval(3_000)))
        await providers.controller.refreshAvailability()
        providers.controller.selectProvider(.chatGPTCodex)
        XCTAssertEqual(providers.controller.selectedProviderID, .chatGPTCodex)

        await providers.controller.disconnect(.chatGPTCodex)

        XCTAssertNil(try providers.codexStore.loadTokens())
        XCTAssertNil(providers.controller.connectedAccount(for: .chatGPTCodex))
        XCTAssertEqual(providers.controller.selectedProviderID, .appleIntelligence)
    }

    @MainActor
    func testCodexSignInIsRefusedUntilRiskIsAcknowledged() async throws {
        var openedURLs: [URL] = []
        let providers = makeChatGPTController(tokens: nil, codexTokens: nil) { openedURLs.append($0) }
        XCTAssertFalse(providers.controller.isUnofficialProviderRiskAcknowledged)

        providers.controller.signIn(to: .chatGPTCodex, restrictedProviderAccess: .allowed)

        XCTAssertEqual(providers.controller.signInState(for: .chatGPTCodex), .idle)
        XCTAssertNotNil(providers.controller.signInErrorMessage(for: .chatGPTCodex))
        XCTAssertTrue(openedURLs.isEmpty)

        providers.controller.acknowledgeUnofficialProviderRisk()
        XCTAssertTrue(providers.controller.isUnofficialProviderRiskAcknowledged)
        XCTAssertTrue(providers.defaults.bool(forKey: "ai.chatgptCodex.riskAcknowledged"))
    }

    @MainActor
    func testCodexAccountShowsPlanType() async throws {
        var codexTokens = ChatGPTTokenSet.expiring(at: Date().addingTimeInterval(3_000))
        codexTokens.planType = "free"
        let providers = makeChatGPTController(tokens: nil, codexTokens: codexTokens)

        await providers.controller.refreshAvailability()

        XCTAssertEqual(
            providers.controller.connectedAccount(for: .chatGPTCodex),
            ConnectedAIAccountSummary(email: "dev@example.com", planType: "free")
        )
        XCTAssertNil(providers.controller.connectedAccount(for: .chatGPTSubscription))
    }

    @MainActor
    private func makeChatGPTController(
        tokens: ChatGPTTokenSet?,
        codexTokens: ChatGPTTokenSet? = nil,
        credentialStore: InMemoryAIProviderCredentialStore = InMemoryAIProviderCredentialStore(),
        openURL: @escaping @MainActor (URL) -> Void = { _ in }
    ) -> (
        controller: AIProviderController,
        session: ChatGPTAccountSession,
        store: InMemoryChatGPTCredentialStore,
        codexStore: InMemoryChatGPTCredentialStore,
        defaults: UserDefaults
    ) {
        let store = InMemoryChatGPTCredentialStore(tokens: tokens)
        let codexStore = InMemoryChatGPTCredentialStore(tokens: codexTokens)
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http)
        let defaults = makeDefaults()
        let controller = AIProviderController(
            registry: .live(
                credentialStore: credentialStore,
                modelStore: InMemoryAIProviderModelStore(),
                httpClient: http,
                chatGPTSession: session,
                chatGPTCodexSession: ChatGPTAccountSession(store: codexStore, httpClient: http, configuration: .codex)
            ),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: defaults,
            credentialStore: credentialStore,
            restrictedProviderAccess: { .allowed },
            openURL: openURL
        )
        return (controller, session, store, codexStore, defaults)
    }
}

final class InMemoryAIProviderCredentialStore: AIProviderCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [AIProviderID: String]

    init(keys: [AIProviderID: String] = [:]) {
        self.keys = keys
    }

    func apiKey(for providerID: AIProviderID) throws -> String? {
        lock.withLock { keys[providerID] }
    }

    func saveAPIKey(_ apiKey: String, for providerID: AIProviderID) throws {
        lock.withLock { keys[providerID] = apiKey }
    }

    func deleteAPIKey(for providerID: AIProviderID) throws {
        lock.withLock { keys.removeValue(forKey: providerID) }
    }
}

final class InMemoryAIProviderModelStore: AIProviderModelStore, @unchecked Sendable {
    private let lock = NSLock()
    private var models: [AIProviderID: String]
    private var thinkingEnabled: Bool

    init(models: [AIProviderID: String] = [:], thinkingEnabled: Bool = false) {
        self.models = models
        self.thinkingEnabled = thinkingEnabled
    }

    var isThinkingEnabled: Bool {
        lock.withLock { thinkingEnabled }
    }

    func setThinkingEnabled(_ isEnabled: Bool) {
        lock.withLock { thinkingEnabled = isEnabled }
    }

    func customModel(for providerID: AIProviderID) -> String? {
        lock.withLock { models[providerID] }
    }

    func saveCustomModel(_ model: String, for providerID: AIProviderID) {
        lock.withLock { models[providerID] = model }
    }

    func resetModel(for providerID: AIProviderID) {
        lock.withLock { models.removeValue(forKey: providerID) }
    }
}

extension OpenRouterReasoningCapabilityStore {
    /// Never loads capabilities, so tests send no extra request and no reasoning fields.
    static let offline = OpenRouterReasoningCapabilityStore(httpClient: OfflineAIProviderHTTPClient())
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 0)

    var now: Date { lock.withLock { date } }

    func advance(by interval: TimeInterval) {
        lock.withLock { date += interval }
    }
}

struct OfflineAIProviderHTTPClient: AIProviderHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

private actor StubAIProviderHTTPClient: AIProviderHTTPClient {
    private let responseBodies: [String]
    private let statusCode: Int
    private var requests: [URLRequest] = []

    init(responseBody: String, statusCode: Int = 200) {
        responseBodies = [responseBody]
        self.statusCode = statusCode
    }

    init(responseBodies: [String], statusCode: Int = 200) {
        self.responseBodies = responseBodies
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let responseIndex = min(requests.count, max(0, responseBodies.count - 1))
        requests.append(request)
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
              ) else {
            throw CommitMessageGenerationError.invalidResponse
        }
        let responseBody = responseBodies.isEmpty ? "{}" : responseBodies[responseIndex]
        return (Data(responseBody.utf8), response)
    }

    func receivedRequest() -> URLRequest? {
        requests.last
    }

    func requestCount() -> Int {
        requests.count
    }
}

private actor StubCloudCommitChangeSnapshotLoader: CommitChangeSnapshotLoading {
    func commitChangeSnapshot(
        in repositoryURL: URL,
        source: CommitChangeSource,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        CommitChangeSnapshot(fingerprint: "tree-1", context: "M\tfile", isTruncated: false)
    }

    func changesFingerprint(
        in repositoryURL: URL,
        source: CommitChangeSource
    ) async throws -> String {
        "tree-1"
    }
}

extension CloudAIProviderTests {
    @MainActor
    func testCopilotIsSelectableOnlyWhenConnectedAndAvailableWithoutPro() async throws {
        let notConnected = makeCopilotController(connectedLogin: nil)
        await notConnected.controller.refreshAvailability()
        let descriptor = try XCTUnwrap(notConnected.controller.descriptors.first { $0.id == .githubCopilot })
        XCTAssertEqual(descriptor.billing, .connectedAccount)
        XCTAssertFalse(notConnected.controller.isAPIKeyConfigured(for: .githubCopilot))
        XCTAssertFalse(notConnected.controller.canSelect(descriptor, restrictedProviderAccess: .allowed))
        let notConnectedMethods = await notConnected.server.methods
        XCTAssertTrue(notConnectedMethods.isEmpty)

        let connected = makeCopilotController(connectedLogin: "octocat")
        await connected.controller.refreshAvailability()
        XCTAssertTrue(connected.controller.isAPIKeyConfigured(for: .githubCopilot))
        XCTAssertEqual(connected.controller.connectedAccount(for: .githubCopilot)?.username, "octocat")
        XCTAssertTrue(connected.controller.canSelect(descriptor, restrictedProviderAccess: .denied(.requiresPro)))

        await connected.server.setStatus("NotSignedIn")
        connected.controller.invalidateAvailability()
        await connected.controller.refreshAvailability()
        XCTAssertTrue(connected.controller.isAPIKeyConfigured(for: .githubCopilot))
        XCTAssertEqual(connected.controller.connectedAccount(for: .githubCopilot)?.requiresSignIn, true)
        XCTAssertFalse(connected.controller.canSelect(descriptor, restrictedProviderAccess: .allowed))
    }

    @MainActor
    func testCopilotDeviceCodeSignInConnectsWithoutPro() async throws {
        let copilot = makeCopilotController(connectedLogin: nil, status: "NotSignedIn")

        // The fake approves the device code as soon as the confirm request arrives.
        copilot.controller.signIn(to: .githubCopilot, restrictedProviderAccess: .denied(.requiresPro))
        for _ in 0..<200 where copilot.controller.signInState(for: .githubCopilot) != .idle {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(copilot.controller.signInErrorMessage(for: .githubCopilot))
        XCTAssertTrue(copilot.controller.isAPIKeyConfigured(for: .githubCopilot))
        XCTAssertEqual(copilot.controller.connectedAccount(for: .githubCopilot)?.username, "octocat")
        XCTAssertEqual(copilot.controller.models(forConnectedAccount: .githubCopilot).map(\.id), ["auto"])
        let methods = await copilot.server.methods
        XCTAssertTrue(methods.contains("signInInitiate"))
        XCTAssertTrue(methods.contains("workspace/executeCommand"))
    }

    @MainActor
    func testRemovingDefaultCopilotSignsOutAndFallsBackToAppleIntelligence() async throws {
        let copilot = makeCopilotController(connectedLogin: "octocat")
        await copilot.controller.refreshAvailability()
        copilot.controller.selectProvider(.githubCopilot)
        XCTAssertEqual(copilot.controller.selectedProviderID, .githubCopilot)

        await copilot.controller.disconnect(.githubCopilot)

        let methods = await copilot.server.methods
        XCTAssertEqual(methods.last, "signOut")
        XCTAssertNil(copilot.defaults.string(forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey))
        XCTAssertNil(copilot.controller.connectedAccount(for: .githubCopilot))
        XCTAssertFalse(copilot.controller.isAPIKeyConfigured(for: .githubCopilot))
        XCTAssertEqual(copilot.controller.selectedProviderID, .appleIntelligence)
    }

    @MainActor
    private func makeCopilotController(
        connectedLogin: String?,
        status: String = "OK"
    ) -> (controller: AIProviderController, server: FakeCopilotServer, defaults: UserDefaults) {
        let defaults = makeDefaults()
        if let connectedLogin {
            defaults.set(connectedLogin, forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey)
        }
        let server = FakeCopilotServer(status: status)
        let http = ChatGPTStubHTTPClient()
        let controller = AIProviderController(
            registry: .live(
                credentialStore: InMemoryAIProviderCredentialStore(),
                modelStore: InMemoryAIProviderModelStore(),
                httpClient: http,
                chatGPTSession: ChatGPTAccountSession(store: InMemoryChatGPTCredentialStore(tokens: nil), httpClient: http),
                chatGPTCodexSession: ChatGPTAccountSession(
                    store: InMemoryChatGPTCredentialStore(tokens: nil),
                    httpClient: http,
                    configuration: .codex
                ),
                copilotSession: GitHubCopilotAccountSession(client: server, defaults: defaults)
            ),
            snapshotLoader: StubCloudCommitChangeSnapshotLoader(),
            defaults: defaults,
            restrictedProviderAccess: { .denied(.requiresPro) }
        )
        return (controller, server, defaults)
    }
}
