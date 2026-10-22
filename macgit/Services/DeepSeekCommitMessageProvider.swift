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

struct DeepSeekCommitMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .deepSeek,
        displayName: "DeepSeek",
        systemImage: "cloud",
        detail: "Cloud · DeepSeek V4.1 Flash",
        dataProcessing: .cloud,
        billing: .bringYourOwnKey,
        requiresProToConfigureAPIKey: true,
        defaultModel: "deepseek-flash",
        inputCharacterBudget: 12_000,
        isImplemented: true
    )

    private let credentialStore: any AIProviderCredentialStore
    private let modelStore: any AIProviderModelStore
    private let httpClient: any AIProviderHTTPClient
    private let endpoint: URL
    private let streamingSession: URLSession

    var supportsRepositoryAgent: Bool { true }

    init(
        credentialStore: any AIProviderCredentialStore,
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!,
        streamingSession: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.modelStore = modelStore
        self.httpClient = httpClient
        self.endpoint = endpoint
        self.streamingSession = streamingSession
    }

    func availability() async -> AIProviderAvailability {
        CloudAIProviderSupport.availability(for: descriptor, credentialStore: credentialStore)
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("DeepSeek model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": CloudCommitMessagePrompt.jsonInstructions],
                ["role": "user", "content": CloudCommitMessagePrompt.userPrompt(for: request)],
            ],
            "max_tokens": 250,
            "response_format": ["type": "json_object"],
            "thinking": ["type": "disabled"],
        ]
        AIThinkingPolicy.deepSeek(enabled: modelStore.isThinkingEnabled, maxTokens: 250).apply(to: &body, maxTokensKey: "max_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CommitMessageGenerationError.invalidResponse
        }
        guard let text = payload.choices.first?.message.content else {
            throw CommitMessageGenerationError.invalidResponse
        }
        return try CloudCommitMessageResponse.decode(from: text).formatted()
    }

    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> RepositoryAIAnswer {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("DeepSeek model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": RepositoryAIPrompt.instructions(for: request)],
                ["role": "user", "content": RepositoryAIPrompt.userPrompt(for: request)],
            ],
            "max_tokens": 3_000,
            "thinking": ["type": "disabled"],
        ]
        if request.requiresStructuredResponse {
            body["response_format"] = ["type": "json_object"]
        }
        AIThinkingPolicy.deepSeek(enabled: modelStore.isThinkingEnabled, maxTokens: 3_000).apply(to: &body, maxTokensKey: "max_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data),
              let text = payload.choices.first?.message.content else {
            throw RepositoryAIError.invalidResponse(
                "DeepSeek did not return a usable Repository AI response."
            )
        }
        return try RepositoryAIAnswerDecoder.decodeProviderText(text, requiresStructuredResponse: request.requiresStructuredResponse)
    }

    func streamRepositoryResponse(
        request: RepositoryAIRequest,
        onTextDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> RepositoryAIAnswer {
        guard !request.requiresStructuredResponse else {
            return try await generateRepositoryResponse(request: request)
        }
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("DeepSeek model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": RepositoryAIPrompt.instructions(for: request)],
                ["role": "user", "content": RepositoryAIPrompt.userPrompt(for: request)],
            ],
            "max_tokens": 3_000,
            "stream": true,
            "thinking": ["type": "disabled"],
        ]
        AIThinkingPolicy.deepSeek(enabled: modelStore.isThinkingEnabled, maxTokens: 3_000).apply(to: &body, maxTokensKey: "max_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        try Task.checkCancellation()
        let (bytes, urlResponse) = try await streamingSession.bytes(for: urlRequest)
        defer { bytes.task.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard let response = urlResponse as? HTTPURLResponse else {
                throw CommitMessageGenerationError.providerRequestFailed(
                    "DeepSeek returned an invalid HTTP response."
                )
            }
            guard (200..<300).contains(response.statusCode) else {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    data.append(byte)
                }
                try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
                throw RepositoryAIError.invalidResponse("DeepSeek returned an invalid streaming response.")
            }

            var content = ""
            var reachedOutputLimit = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8),
                      let event = try? JSONDecoder().decode(StreamEvent.self, from: data),
                      let choice = event.choices.first else { continue }
                if let delta = choice.delta?.content, !delta.isEmpty {
                    content.append(delta)
                    await onTextDelta(delta)
                }
                if choice.finishReason?.lowercased() == "length" {
                    reachedOutputLimit = true
                }
            }
            try Task.checkCancellation()
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RepositoryAIError.emptyResponse
            }
            return RepositoryAIAnswer(text: content, isTruncated: reachedOutputLimit)
        } onCancel: {
            bytes.task.cancel()
        }
    }

    func generateRepositoryAgentTurn(
        request: RepositoryAIAgentRequest
    ) async throws -> RepositoryAIAgentTurn {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("DeepSeek model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let messages = agentMessages(for: request)
        let tools = RepositoryAIAgentToolSchema
            .declarations(
                includingQuickActions: request.isFirstTurn,
                allowsBuiltInWorkflows: request.allowsBuiltInWorkflows,
                mutationContext: request.mutationContext,
                remoteOperationContext: request.remoteOperationContext
            )
            .map { declaration in
                ["type": "function", "function": declaration] as [String: Any]
            }
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "tools": tools,
            "tool_choice": request.isFirstTurn ? "required" : "auto",
            "max_tokens": 1_200,
            "thinking": ["type": "disabled"],
        ]
        AIThinkingPolicy.deepSeek(enabled: modelStore.isThinkingEnabled, maxTokens: 1_200).apply(to: &body, maxTokensKey: "max_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data),
              let message = payload.choices.first?.message else {
            throw RepositoryAIError.invalidResponse("DeepSeek did not return a usable Git tool response.")
        }
        let toolCalls = try (message.toolCalls ?? []).map { toolCall in
            let suppliedArguments = Self.decodedToolArguments(from: toolCall.function.arguments)
            guard let arguments = RepositoryAIAgentToolSchema.arguments(
                forToolNamed: toolCall.function.name,
                suppliedArguments: suppliedArguments
            ) else {
                throw RepositoryAIError.invalidResponse("DeepSeek returned an invalid Git tool call.")
            }
            return RepositoryAIAgentToolCall(
                id: toolCall.id,
                name: toolCall.function.name,
                arguments: arguments
            )
        }
        return RepositoryAIAgentTurn(text: message.content ?? "", toolCalls: toolCalls)
    }

    private func agentMessages(for request: RepositoryAIAgentRequest) -> [[String: Any]] {
        var messages: [[String: Any]] = [
            ["role": "system", "content": RepositoryAIPrompt.agentInstructions],
            ["role": "user", "content": RepositoryAIPrompt.agentPrompt(for: request)],
        ]
        for toolResult in request.previousToolResults {
            let arguments = (try? JSONSerialization.data(withJSONObject: ["arguments": toolResult.toolCall.arguments]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"arguments\":[]}"
            messages.append([
                "role": "assistant",
                "content": NSNull(),
                "tool_calls": [[
                    "id": toolResult.toolCall.id,
                    "type": "function",
                    "function": ["name": toolResult.toolCall.name, "arguments": arguments],
                ]],
            ])
            messages.append([
                "role": "tool",
                "tool_call_id": toolResult.toolCall.id,
                "content": toolResult.commandResult.output,
            ])
        }
        return messages
    }

    /// DeepSeek normally returns the schema object, but some compatible-model
    /// responses serialize the sole array value directly or double-encode the
    /// object. Both are semantically equivalent and remain subject to the
    /// read-only Git command policy in the harness.
    static func decodedToolArguments(from rawArguments: String) -> [String]? {
        guard let data = rawArguments.data(using: .utf8) else { return nil }
        if let decoded = try? JSONDecoder().decode(RepositoryAIAgentToolArgumentsPayload.self, from: data) {
            return decoded.arguments
        }
        if let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        guard let encoded = try? JSONDecoder().decode(String.self, from: data),
              encoded != rawArguments else {
            return nil
        }
        return decodedToolArguments(from: encoded)
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("DeepSeek model is not configured.")
        }
        let context = try ConflictAIPrompt.context(
            for: request.snapshot,
            characterBudget: descriptor.inputCharacterBudget
        )
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": ConflictAIPrompt.instructions],
                ["role": "user", "content": context],
            ],
            "max_tokens": 4_000,
            "response_format": ["type": "json_object"],
            "thinking": ["type": "disabled"],
        ]
        AIThinkingPolicy.deepSeek(enabled: modelStore.isThinkingEnabled, maxTokens: 4_000).apply(to: &body, maxTokensKey: "max_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data),
              let text = payload.choices.first?.message.content else {
            throw ConflictAIResolutionError.invalidResponse(
                "DeepSeek did not return a conflict-resolution plan."
            )
        }
        return try ConflictAIResolutionResponse.decode(from: text)
    }

    private struct Response: Decodable {
        let choices: [Choice]
    }

    private struct Choice: Decodable {
        let message: Message
    }

    private struct StreamEvent: Decodable {
        let choices: [StreamChoice]
    }

    private struct StreamChoice: Decodable {
        let delta: StreamDelta?
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    private struct StreamDelta: Decodable {
        let content: String?
    }

    private struct Message: Decodable {
        let content: String?
        let toolCalls: [ToolCall]?

        private enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    private struct ToolCall: Decodable {
        let id: String
        let function: ToolFunction
    }

    private struct ToolFunction: Decodable {
        let name: String
        let arguments: String
    }

}
