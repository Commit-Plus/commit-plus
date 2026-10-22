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

struct OpenAICommitMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .openAI,
        displayName: "OpenAI",
        systemImage: "cloud",
        detail: "Cloud · GPT-4o mini",
        dataProcessing: .cloud,
        billing: .bringYourOwnKey,
        requiresProToConfigureAPIKey: false,
        defaultModel: "gpt-4o-mini",
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
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
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
            throw CommitMessageGenerationError.providerRequestFailed("OpenAI model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "instructions": CloudCommitMessagePrompt.instructions,
            "input": CloudCommitMessagePrompt.userPrompt(for: request),
            "max_output_tokens": 250,
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "commit_message",
                    "strict": true,
                    "schema": CloudCommitMessagePrompt.responseSchema,
                ],
            ],
        ]
        AIThinkingPolicy.openAI(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 250).apply(to: &body, maxTokensKey: "max_output_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CommitMessageGenerationError.invalidResponse
        }
        guard let text = outputText(from: payload, rawData: data) else {
            throw CommitMessageGenerationError.invalidResponse
        }
        return try CloudCommitMessageResponse.decode(from: text).formatted()
    }

    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> RepositoryAIAnswer {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("OpenAI model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "instructions": RepositoryAIPrompt.instructions(for: request),
            "input": RepositoryAIPrompt.userPrompt(for: request),
            "max_output_tokens": 1_200,
            "store": false,
        ]
        AIThinkingPolicy.openAI(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 1_200).apply(to: &body, maxTokensKey: "max_output_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data),
              let text = outputText(from: payload, rawData: data) else {
            throw RepositoryAIError.invalidResponse(
                "OpenAI did not return a usable Repository AI response."
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
            throw CommitMessageGenerationError.providerRequestFailed("OpenAI model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "model": model,
            "instructions": RepositoryAIPrompt.instructions(for: request),
            "input": RepositoryAIPrompt.userPrompt(for: request),
            "max_output_tokens": 3_000,
            "stream": true,
            "store": false,
        ]
        AIThinkingPolicy.openAI(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 3_000).apply(to: &body, maxTokensKey: "max_output_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        try Task.checkCancellation()
        let (bytes, urlResponse) = try await streamingSession.bytes(for: urlRequest)
        defer { bytes.task.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard let response = urlResponse as? HTTPURLResponse else {
                throw CommitMessageGenerationError.providerRequestFailed(
                    "OpenAI returned an invalid HTTP response."
                )
            }
            guard (200..<300).contains(response.statusCode) else {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    data.append(byte)
                }
                try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
                throw RepositoryAIError.invalidResponse("OpenAI returned an invalid streaming response.")
            }

            var content = ""
            var reachedOutputLimit = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = payload.data(using: .utf8),
                      let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }
                if event.type == "response.output_text.delta", let delta = event.delta, !delta.isEmpty {
                    content.append(delta)
                    await onTextDelta(delta)
                }
                if event.type == "response.completed",
                   event.response?.incompleteDetails?.reason == "max_output_tokens" {
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
            throw CommitMessageGenerationError.providerRequestFailed("OpenAI model is not configured.")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let tools = RepositoryAIAgentToolSchema
            .declarations(
                includingQuickActions: request.isFirstTurn,
                allowsBuiltInWorkflows: request.allowsBuiltInWorkflows,
                mutationContext: request.mutationContext,
                remoteOperationContext: request.remoteOperationContext
            )
            .map { declaration -> [String: Any] in
                var tool = declaration
                tool["type"] = "function"
                tool["strict"] = true
                return tool
            }
        var body: [String: Any] = [
            "model": model,
            "instructions": RepositoryAIPrompt.agentInstructions,
            "input": repositoryAgentInput(for: request),
            "max_output_tokens": 1_200,
            "store": false,
            "tool_choice": request.isFirstTurn ? "required" : "auto",
            "tools": tools,
        ]
        AIThinkingPolicy.openAI(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 1_200).apply(to: &body, maxTokensKey: "max_output_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw RepositoryAIError.invalidResponse("OpenAI did not return a usable Repository AI response.")
        }
        let toolCalls = try payload.output
            .filter { $0.type == "function_call" }
            .map { output in
                guard let id = output.callID,
                      let name = output.name,
                      let rawArguments = output.arguments,
                      let data = rawArguments.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      Set(object.keys).isSubset(of: ["arguments"]),
                      let arguments = RepositoryAIAgentToolSchema.arguments(
                        forToolNamed: name,
                        suppliedArguments: object["arguments"] as? [String]
                      ) else {
                    throw RepositoryAIError.invalidResponse("OpenAI returned an invalid Git tool call.")
                }
                return RepositoryAIAgentToolCall(id: id, name: name, arguments: arguments)
            }
        let text = payload.output.compactMap(\.content).flatMap({ $0 })
            .first(where: { $0.type == "output_text" })?.text ?? ""
        return RepositoryAIAgentTurn(text: text, toolCalls: toolCalls)
    }

    private func repositoryAgentInput(for request: RepositoryAIAgentRequest) -> [[String: Any]] {
        var input: [[String: Any]] = [[
            "role": "user",
            "content": RepositoryAIPrompt.agentPrompt(for: request),
        ]]
        for toolResult in request.previousToolResults {
            let arguments = (try? JSONSerialization.data(withJSONObject: [
                "arguments": toolResult.toolCall.arguments,
            ]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"arguments\":[]}"
            input.append([
                "type": "function_call",
                "call_id": toolResult.toolCall.id,
                "name": toolResult.toolCall.name,
                "arguments": arguments,
            ])
            input.append([
                "type": "function_call_output",
                "call_id": toolResult.toolCall.id,
                "output": toolResult.commandResult.output,
            ])
        }
        return input
    }

    private func outputText(from payload: Response, rawData: Data) -> String? {
        if let text = payload.output
            .compactMap(\.content)
            .flatMap({ $0 })
            .first(where: { $0.type == "output_text" })?
            .text {
            return text
        }
        return outputText(from: rawData)
    }

    private func outputText(from rawData: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let output = object["output"] as? [[String: Any]] else {
            return nil
        }
        return output
            .compactMap { $0["content"] as? [[String: Any]] }
            .flatMap { $0 }
            .first(where: { $0["type"] as? String == "output_text" })?["text"] as? String
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("OpenAI model is not configured.")
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
            "instructions": ConflictAIPrompt.instructions,
            "input": context,
            "max_output_tokens": 4_000,
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "conflict_resolution",
                    "strict": true,
                    "schema": ConflictAIPrompt.responseSchema,
                ],
            ],
        ]
        AIThinkingPolicy.openAI(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 4_000).apply(to: &body, maxTokensKey: "max_output_tokens")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let text = outputText(from: data) else {
            throw ConflictAIResolutionError.invalidResponse(
                "OpenAI did not return a conflict-resolution plan."
            )
        }
        return try ConflictAIResolutionResponse.decode(from: text)
    }

    private struct Response: Decodable {
        let output: [Output]
    }

    private struct Output: Decodable {
        let type: String?
        let content: [Content]?
        let callID: String?
        let name: String?
        let arguments: String?

        enum CodingKeys: String, CodingKey {
            case type
            case content
            case callID = "call_id"
            case name
            case arguments
        }
    }

    private struct Content: Decodable {
        let type: String
        let text: String?
    }

    private struct StreamEvent: Decodable {
        let type: String
        let delta: String?
        let response: StreamResponse?
    }

    private struct StreamResponse: Decodable {
        let incompleteDetails: IncompleteDetails?

        private enum CodingKeys: String, CodingKey {
            case incompleteDetails = "incomplete_details"
        }
    }

    private struct IncompleteDetails: Decodable {
        let reason: String?
    }
}
