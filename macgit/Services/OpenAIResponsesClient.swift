// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// OpenAI Responses API requests shared by the API-key OpenAI provider and the
/// ChatGPT plan provider. Callers supply the bearer credential and error mapping.
struct OpenAIResponsesClient: Sendable {
    enum Transport: Sendable {
        /// Plain JSON responses; streaming is used only for live repository chat.
        case standard
        /// Every request sends `"stream": true` (required for ChatGPT plan usage).
        /// One-shot calls read the whole event stream and decode the final response.
        case streamingRequired
    }

    let descriptor: AIProviderDescriptor
    let modelStore: any AIProviderModelStore
    let httpClient: any AIProviderHTTPClient
    let endpoint: URL
    let streamingSession: URLSession
    let transport: Transport
    let bearerToken: @Sendable () async throws -> String
    let validate: @Sendable (HTTPURLResponse, Data) async throws -> Void
    /// Maps a `response.failed` or `error` stream event to the error to throw.
    let streamFailure: @Sendable (_ code: String?, _ message: String?) async -> any Error

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        let model = try configuredModel()
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

        let data = try await send(body)
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
        let model = try configuredModel()
        var body: [String: Any] = [
            "model": model,
            "instructions": RepositoryAIPrompt.instructions(for: request),
            "input": RepositoryAIPrompt.userPrompt(for: request),
            "max_output_tokens": 1_200,
            "store": false,
        ]
        AIThinkingPolicy.openAI(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: 1_200).apply(to: &body, maxTokensKey: "max_output_tokens")

        let data = try await send(body)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data),
              let text = outputText(from: payload, rawData: data) else {
            throw RepositoryAIError.invalidResponse(
                "\(descriptor.displayName) did not return a usable Repository AI response."
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
        let model = try configuredModel()
        var urlRequest = try await makeRequest()
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
                    "\(descriptor.displayName) returned an invalid HTTP response."
                )
            }
            guard (200..<300).contains(response.statusCode) else {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    data.append(byte)
                }
                try await validate(response, data)
                throw RepositoryAIError.invalidResponse("\(descriptor.displayName) returned an invalid streaming response.")
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
                if transport == .streamingRequired {
                    if event.type == "response.incomplete" {
                        reachedOutputLimit = true
                    }
                    if let failure = Self.failure(in: data) {
                        throw await streamFailure(failure.code, failure.message)
                    }
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
        let model = try configuredModel()
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

        let data = try await send(body)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw RepositoryAIError.invalidResponse("\(descriptor.displayName) did not return a usable Repository AI response.")
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
                    throw RepositoryAIError.invalidResponse("\(descriptor.displayName) returned an invalid Git tool call.")
                }
                return RepositoryAIAgentToolCall(id: id, name: name, arguments: arguments)
            }
        let text = payload.output.compactMap(\.content).flatMap({ $0 })
            .first(where: { $0.type == "output_text" })?.text ?? ""
        return RepositoryAIAgentTurn(text: text, toolCalls: toolCalls)
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        let model = try configuredModel()
        let context = try ConflictAIPrompt.context(
            for: request.snapshot,
            characterBudget: descriptor.inputCharacterBudget
        )
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

        let data = try await send(body)
        guard let text = outputText(from: data) else {
            throw ConflictAIResolutionError.invalidResponse(
                "\(descriptor.displayName) did not return a conflict-resolution plan."
            )
        }
        return try ConflictAIResolutionResponse.decode(from: text)
    }

    // MARK: Transport

    private func configuredModel() throws -> String {
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("\(descriptor.displayName) model is not configured.")
        }
        return model
    }

    private func makeRequest() async throws -> URLRequest {
        let token = try await bearerToken()
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return urlRequest
    }

    /// Sends one request and returns the Responses API response object as JSON.
    private func send(_ body: [String: Any]) async throws -> Data {
        var urlRequest = try await makeRequest()
        var body = body
        if transport == .streamingRequired {
            body["stream"] = true
            body["store"] = false
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: urlRequest)
        try await validate(response, data)
        guard transport == .streamingRequired else { return data }
        return try await finalResponse(fromEventStream: data)
    }

    private func finalResponse(fromEventStream data: Data) async throws -> Data {
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("data:") {
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let eventData = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else { continue }
            if let failure = Self.failure(in: eventData) {
                throw await streamFailure(failure.code, failure.message)
            }
            let type = event["type"] as? String
            if type == "response.completed" || type == "response.incomplete",
               let response = event["response"] as? [String: Any] {
                return try JSONSerialization.data(withJSONObject: response)
            }
        }
        throw CommitMessageGenerationError.providerRequestFailed(
            "\(descriptor.displayName) ended the response before it completed. Try again."
        )
    }

    /// The error carried by a `response.failed` or `error` stream event.
    static func failure(in eventData: Data) -> (code: String?, message: String?)? {
        guard let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else { return nil }
        switch event["type"] as? String {
        case "response.failed":
            let error = (event["response"] as? [String: Any])?["error"] as? [String: Any]
            return (error?["code"] as? String, error?["message"] as? String)
        case "error":
            let error = event["error"] as? [String: Any] ?? event
            return (error["code"] as? String, error["message"] as? String)
        default:
            return nil
        }
    }

    // MARK: Parsing

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
