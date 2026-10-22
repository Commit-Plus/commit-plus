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

struct AnthropicCommitMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .anthropic,
        displayName: "Claude",
        systemImage: "cloud",
        detail: "Cloud · Claude Haiku 5.5",
        dataProcessing: .cloud,
        billing: .bringYourOwnKey,
        requiresProToConfigureAPIKey: true,
        defaultModel: "claude-haiku-5-5",
        inputCharacterBudget: 12_000,
        isImplemented: true
    )

    private let credentialStore: any AIProviderCredentialStore
    private let modelStore: any AIProviderModelStore
    private let httpClient: any AIProviderHTTPClient
    private let endpoint: URL

    var supportsRepositoryAgent: Bool { true }

    init(
        credentialStore: any AIProviderCredentialStore,
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!
    ) {
        self.credentialStore = credentialStore
        self.modelStore = modelStore
        self.httpClient = httpClient
        self.endpoint = endpoint
    }

    func availability() async -> AIProviderAvailability {
        CloudAIProviderSupport.availability(for: descriptor, credentialStore: credentialStore)
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("Claude model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 250,
            "system": CloudCommitMessagePrompt.instructions,
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": CloudCommitMessagePrompt.responseSchema,
                ],
            ],
            "messages": [[
                "role": "user",
                "content": CloudCommitMessagePrompt.userPrompt(for: request),
            ]],
        ]
        AIThinkingPolicy.claude(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 250).apply(to: &body, maxTokensKey: "max_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CommitMessageGenerationError.invalidResponse
        }
        guard let text = payload.content.first(where: { $0.type == "text" })?.text else {
            throw CommitMessageGenerationError.invalidResponse
        }
        return try CloudCommitMessageResponse.decode(from: text).formatted()
    }

    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> RepositoryAIAnswer {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("Claude model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 3_000,
            "system": RepositoryAIPrompt.instructions(for: request),
            "messages": [[
                "role": "user",
                "content": RepositoryAIPrompt.userPrompt(for: request),
            ]],
        ]
        AIThinkingPolicy.claude(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 3_000).apply(to: &body, maxTokensKey: "max_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data),
              let text = payload.content.first(where: { $0.type == "text" })?.text else {
            throw RepositoryAIError.invalidResponse(
                "Claude did not return a usable Repository AI response."
            )
        }
        return try RepositoryAIAnswerDecoder.decodeProviderText(text, requiresStructuredResponse: request.requiresStructuredResponse)
    }

    func generateRepositoryAgentTurn(
        request: RepositoryAIAgentRequest
    ) async throws -> RepositoryAIAgentTurn {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("Claude model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var messages: [[String: Any]] = [[
            "role": "user",
            "content": RepositoryAIPrompt.agentPrompt(for: request),
        ]]
        for group in Self.toolResultGroups(request.previousToolResults) {
            let thinkingBlocks = group.first?.toolCall.claudeToolUseState?.thinkingBlocks ?? []
            messages.append([
                "role": "assistant",
                "content": thinkingBlocks.map(Self.requestContent) + group.map { toolResult in
                    [
                        "type": "tool_use",
                        "id": toolResult.toolCall.id,
                        "name": toolResult.toolCall.name,
                        "input": ["arguments": toolResult.toolCall.arguments],
                    ] as [String: Any]
                },
            ])
            messages.append([
                "role": "user",
                "content": group.map { toolResult in
                    [
                        "type": "tool_result",
                        "tool_use_id": toolResult.toolCall.id,
                        "content": toolResult.commandResult.output,
                    ] as [String: Any]
                },
            ])
        }
        let tools = RepositoryAIAgentToolSchema
            .declarations(
                includingQuickActions: request.isFirstTurn,
                allowsBuiltInWorkflows: request.allowsBuiltInWorkflows,
                mutationContext: request.mutationContext,
                remoteOperationContext: request.remoteOperationContext
            )
            .map { declaration in
                [
                    "name": declaration["name"] as? String ?? "",
                    "description": declaration["description"] as? String ?? "",
                    "input_schema": declaration["parameters"] as? [String: Any] ?? [:],
                ] as [String: Any]
            }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1_200,
            "system": RepositoryAIPrompt.agentInstructions,
            "messages": messages,
            "tools": tools,
        ]
        let thinking = AIThinkingPolicy.claude(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 1_200)
        thinking.apply(to: &body, maxTokensKey: "max_tokens")
        // Newer models and thinking requests reject forced tool use; the agent prompt already asks for a tool call.
        if request.isFirstTurn, thinking.allowsForcedToolChoice {
            body["tool_choice"] = ["type": "any"]
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw RepositoryAIError.invalidResponse("Claude did not return a usable Git tool response.")
        }
        let toolUseState = RepositoryAIClaudeToolUseState(
            messageID: payload.id ?? UUID().uuidString,
            thinkingBlocks: payload.content.compactMap { content in
                guard content.type == "thinking" || content.type == "redacted_thinking" else { return nil }
                return RepositoryAIClaudeThinkingBlock(
                    type: content.type,
                    thinking: content.thinking,
                    signature: content.signature,
                    data: content.data
                )
            }
        )
        let toolCalls: [RepositoryAIAgentToolCall] = try payload.content.compactMap { content in
            guard content.type == "tool_use" else { return nil }
            guard let id = content.id,
                  let name = content.name,
                  let arguments = RepositoryAIAgentToolSchema.arguments(
                    forToolNamed: name,
                    suppliedArguments: content.input?.arguments
                  ) else {
                throw RepositoryAIError.invalidResponse("Claude returned an invalid Git tool call.")
            }
            return RepositoryAIAgentToolCall(
                id: id,
                name: name,
                arguments: arguments,
                claudeToolUseState: toolUseState
            )
        }
        let text = payload.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
        return RepositoryAIAgentTurn(text: text, toolCalls: toolCalls)
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("Claude model is not configured.")
        }
        let context = try ConflictAIPrompt.context(
            for: request.snapshot,
            characterBudget: descriptor.inputCharacterBudget
        )
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4_000,
            "system": ConflictAIPrompt.instructions,
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": ConflictAIPrompt.responseSchema,
                ],
            ],
            "messages": [["role": "user", "content": context]],
        ]
        AIThinkingPolicy.claude(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 4_000).apply(to: &body, maxTokensKey: "max_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data),
              let text = payload.content.first(where: { $0.type == "text" })?.text else {
            throw ConflictAIResolutionError.invalidResponse(
                "Claude did not return a conflict-resolution plan."
            )
        }
        return try ConflictAIResolutionResponse.decode(from: text)
    }

    /// Splits tool results into runs issued by the same Claude message, so each run is
    /// replayed as one assistant message followed by one user message of results.
    private static func toolResultGroups(
        _ toolResults: [RepositoryAIAgentToolResult]
    ) -> [[RepositoryAIAgentToolResult]] {
        var groups: [[RepositoryAIAgentToolResult]] = []
        for toolResult in toolResults {
            if let messageID = toolResult.toolCall.claudeToolUseState?.messageID,
               groups.last?.last?.toolCall.claudeToolUseState?.messageID == messageID {
                groups[groups.count - 1].append(toolResult)
            } else {
                groups.append([toolResult])
            }
        }
        return groups
    }

    private static func requestContent(for block: RepositoryAIClaudeThinkingBlock) -> [String: Any] {
        var content: [String: Any] = ["type": block.type]
        content["thinking"] = block.thinking
        content["signature"] = block.signature
        content["data"] = block.data
        return content
    }

    private struct Response: Decodable {
        let id: String?
        let content: [Content]
    }

    private struct Content: Decodable {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: RepositoryAIAgentToolArgumentsPayload?
        let thinking: String?
        let signature: String?
        let data: String?
    }
}
