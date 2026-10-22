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

struct GeminiCommitMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .googleGemini,
        displayName: "Gemini",
        systemImage: "cloud",
        detail: "Cloud · Gemini 3.5 Flash-Lite",
        dataProcessing: .cloud,
        billing: .bringYourOwnKey,
        requiresProToConfigureAPIKey: false,
        defaultModel: "gemini-3.5-flash-lite",
        inputCharacterBudget: 12_000,
        isImplemented: true
    )

    private let credentialStore: any AIProviderCredentialStore
    private let modelStore: any AIProviderModelStore
    private let httpClient: any AIProviderHTTPClient
    private let modelsEndpoint: URL

    var supportsRepositoryAgent: Bool { true }

    init(
        credentialStore: any AIProviderCredentialStore,
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        modelsEndpoint: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
    ) {
        self.credentialStore = credentialStore
        self.modelStore = modelStore
        self.httpClient = httpClient
        self.modelsEndpoint = modelsEndpoint
    }

    func availability() async -> AIProviderAvailability {
        CloudAIProviderSupport.availability(for: descriptor, credentialStore: credentialStore)
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("Gemini model is not configured.")
        }
        let endpoint = modelsEndpoint.appending(path: "\(model):generateContent")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": [
                "parts": [["text": CloudCommitMessagePrompt.instructions]],
            ],
            "contents": [[
                "role": "user",
                "parts": [["text": CloudCommitMessagePrompt.userPrompt(for: request)]],
            ]],
            "generationConfig": [
                "maxOutputTokens": thinking(for: model, maxTokens: 512).maxTokens,
                "responseMimeType": "application/json",
                "responseJsonSchema": CloudCommitMessagePrompt.responseSchema,
                "thinkingConfig": thinking(for: model, maxTokens: 512).thinkingConfig,
            ],
            "store": false,
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        let payload: Response
        do {
            payload = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CommitMessageGenerationError.invalidResponse
        }
        let candidates = payload.candidates ?? []
        let responseTexts = candidates
            .compactMap(\.content)
            .flatMap(\.parts)
            .filter { $0.thought != true }
            .compactMap(\.text)

        for text in responseTexts {
            if let generated = try? CloudCommitMessageResponse.decode(from: text).formatted() {
                return generated
            }
        }

        if let blockReason = payload.promptFeedback?.blockReason {
            throw CommitMessageGenerationError.providerRequestFailed(
                "Gemini blocked the request (\(blockReason)). Try generating from a smaller or different set of changes."
            )
        }
        if let candidate = candidates.first {
            switch candidate.finishReason {
            case "MAX_TOKENS":
                throw CommitMessageGenerationError.providerRequestFailed(
                    "Gemini reached its output limit before returning a commit message. Try generating from a smaller change."
                )
            case "STOP":
                throw CommitMessageGenerationError.providerRequestFailed(
                    "Gemini completed the request but returned no valid commit-message JSON. Generate it again."
                )
            case let reason?:
                let detail = candidate.finishMessage.map { ": \($0)" } ?? "."
                throw CommitMessageGenerationError.providerRequestFailed(
                    "Gemini stopped generating (\(reason))\(detail)"
                )
            case nil:
                break
            }
        }
        throw CommitMessageGenerationError.providerRequestFailed(
            "Gemini returned an empty response. Generate the commit message again."
        )
    }

    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> RepositoryAIAnswer {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("Gemini model is not configured.")
        }
        let endpoint = modelsEndpoint.appending(path: "\(model):generateContent")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": RepositoryAIPrompt.instructions(for: request)]]],
            "contents": [[
                "role": "user",
                "parts": [["text": RepositoryAIPrompt.userPrompt(for: request)]],
            ]],
            "generationConfig": [
                "maxOutputTokens": thinking(for: model, maxTokens: 3_000).maxTokens,
                "thinkingConfig": thinking(for: model, maxTokens: 3_000).thinkingConfig,
            ],
            "store": false,
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw RepositoryAIError.invalidResponse(
                "Gemini did not return a usable Repository AI response."
            )
        }
        let text = (payload.candidates ?? [])
            .compactMap(\.content)
            .flatMap(\.parts)
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let blockReason = payload.promptFeedback?.blockReason {
                throw CommitMessageGenerationError.providerRequestFailed("Gemini blocked the request (\(blockReason)).")
            }
            throw RepositoryAIError.emptyResponse
        }
        return try RepositoryAIAnswerDecoder.decodeProviderText(text, requiresStructuredResponse: request.requiresStructuredResponse)
    }

    func generateRepositoryAgentTurn(
        request: RepositoryAIAgentRequest
    ) async throws -> RepositoryAIAgentTurn {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("Gemini model is not configured.")
        }
        let endpoint = modelsEndpoint.appending(path: "\(model):generateContent")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var contents: [[String: Any]] = [[
            "role": "user",
            "parts": [["text": RepositoryAIPrompt.agentPrompt(for: request)]],
        ]]
        for toolResult in request.previousToolResults {
            let geminiState = toolResult.toolCall.geminiFunctionCallState
            var functionCall: [String: Any] = [
                "name": toolResult.toolCall.name,
                "args": ["arguments": toolResult.toolCall.arguments],
            ]
            if let callID = geminiState?.callID {
                functionCall["id"] = callID
            }
            var functionCallPart: [String: Any] = ["functionCall": functionCall]
            if let thoughtSignature = geminiState?.thoughtSignature {
                functionCallPart["thoughtSignature"] = thoughtSignature
            }

            var functionResponse: [String: Any] = [
                "name": toolResult.toolCall.name,
                "response": ["output": toolResult.commandResult.output],
            ]
            if let callID = geminiState?.callID {
                functionResponse["id"] = callID
            }
            contents.append([
                "role": "model",
                "parts": [functionCallPart],
            ])
            contents.append([
                "role": "user",
                "parts": [["functionResponse": functionResponse]],
            ])
        }
        let functionCallingConfig: [String: Any] = [
            "mode": request.isFirstTurn ? "ANY" : "AUTO",
        ]
        let functionDeclarations = RepositoryAIAgentToolSchema.declarations(
            includingQuickActions: request.isFirstTurn,
            allowsBuiltInWorkflows: request.allowsBuiltInWorkflows,
            forGemini: true,
            mutationContext: request.mutationContext,
            remoteOperationContext: request.remoteOperationContext
        )
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": RepositoryAIPrompt.agentInstructions]]],
            "contents": contents,
            "tools": [[
                "functionDeclarations": functionDeclarations,
            ]],
            "toolConfig": [
                "functionCallingConfig": functionCallingConfig,
            ],
            "generationConfig": [
                "maxOutputTokens": thinking(for: model, maxTokens: 1_200).maxTokens,
                "thinkingConfig": thinking(for: model, maxTokens: 1_200).thinkingConfig,
            ],
            "store": false,
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw RepositoryAIError.invalidResponse("Gemini did not return a usable Git tool response.")
        }
        let parts = (payload.candidates ?? []).compactMap(\.content).flatMap(\.parts)
        let toolCalls: [RepositoryAIAgentToolCall] = try parts.compactMap { part -> RepositoryAIAgentToolCall? in
            guard let functionCall = part.functionCall else { return nil }
            guard let arguments = RepositoryAIAgentToolSchema.arguments(
                forToolNamed: functionCall.name,
                suppliedArguments: functionCall.args?.arguments
            ) else {
                throw RepositoryAIError.invalidResponse("Gemini returned an invalid Git tool call.")
            }
            return RepositoryAIAgentToolCall(
                id: functionCall.id ?? UUID().uuidString,
                name: functionCall.name,
                arguments: arguments,
                geminiFunctionCallState: RepositoryAIGeminiFunctionCallState(
                    callID: functionCall.id,
                    thoughtSignature: part.thoughtSignature
                )
            )
        }
        let text = parts
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined(separator: "\n")
        return RepositoryAIAgentTurn(text: text, toolCalls: toolCalls)
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        let apiKey = try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
        guard let model = modelStore.model(for: descriptor) else {
            throw CommitMessageGenerationError.providerRequestFailed("Gemini model is not configured.")
        }
        let context = try ConflictAIPrompt.context(
            for: request.snapshot,
            characterBudget: descriptor.inputCharacterBudget
        )
        let endpoint = modelsEndpoint.appending(path: "\(model):generateContent")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": ConflictAIPrompt.instructions]]],
            "contents": [["role": "user", "parts": [["text": context]]]],
            "generationConfig": [
                "maxOutputTokens": thinking(for: model, maxTokens: 4_096).maxTokens,
                "responseMimeType": "application/json",
                "responseJsonSchema": ConflictAIPrompt.responseSchema,
                "thinkingConfig": thinking(for: model, maxTokens: 4_096).thinkingConfig,
            ],
            "store": false,
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ConflictAIResolutionError.invalidResponse(
                "Gemini did not return a conflict-resolution plan."
            )
        }
        let responseTexts = (payload.candidates ?? [])
            .compactMap(\.content)
            .flatMap(\.parts)
            .filter { $0.thought != true }
            .compactMap(\.text)
        for text in responseTexts {
            if let plan = try? ConflictAIResolutionResponse.decode(from: text) {
                return plan
            }
        }
        if let blockReason = payload.promptFeedback?.blockReason {
            throw CommitMessageGenerationError.providerRequestFailed(
                "Gemini blocked the conflict request (\(blockReason))."
            )
        }
        throw ConflictAIResolutionError.invalidResponse(
            "Gemini did not return a conflict-resolution plan."
        )
    }

    private func thinking(for model: String, maxTokens: Int) -> (thinkingConfig: [String: Any], maxTokens: Int) {
        AIThinkingPolicy.gemini(model: model, enabled: modelStore.isThinkingEnabled, maxTokens: maxTokens)
    }

    private struct Response: Decodable {
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    private struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
        let finishMessage: String?
    }

    private struct Content: Decodable {
        let parts: [Part]
    }

    private struct Part: Decodable {
        let text: String?
        let thought: Bool?
        let thoughtSignature: String?
        let functionCall: FunctionCall?
    }

    private struct FunctionCall: Decodable {
        let id: String?
        let name: String
        let args: RepositoryAIAgentToolArgumentsPayload?
    }

    private struct PromptFeedback: Decodable {
        let blockReason: String?
    }
}
