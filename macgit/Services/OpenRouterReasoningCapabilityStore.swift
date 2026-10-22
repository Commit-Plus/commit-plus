// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Caches each OpenRouter model's reasoning capability from OpenRouter's public models API,
/// so the "Thinking" setting only sends reasoning values a model accepts.
actor OpenRouterReasoningCapabilityStore {
    static let shared = OpenRouterReasoningCapabilityStore()

    private let httpClient: any AIProviderHTTPClient
    private let modelsEndpoint: URL
    private var capabilities: [String: OpenRouterReasoningCapability]?
    private var loadTask: Task<[String: OpenRouterReasoningCapability]?, Never>?

    init(
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        modelsEndpoint: URL = URL(string: "https://openrouter.ai/api/v1/models")!
    ) {
        self.httpClient = httpClient
        self.modelsEndpoint = modelsEndpoint
    }

    /// `nil` when the model has no reasoning support or the list could not be loaded.
    func capability(for model: String) async -> OpenRouterReasoningCapability? {
        if let capabilities { return capabilities[model] }
        let task = loadTask ?? Task { [httpClient, modelsEndpoint] in
            await Self.load(httpClient: httpClient, endpoint: modelsEndpoint)
        }
        loadTask = task
        let loaded = await task.value
        loadTask = nil
        // A failed load is retried on a later request rather than cached.
        if let loaded { capabilities = loaded }
        return loaded?[model]
    }

    private static func load(
        httpClient: any AIProviderHTTPClient,
        endpoint: URL
    ) async -> [String: OpenRouterReasoningCapability]? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        guard let (data, response) = try? await httpClient.data(for: request),
              (200..<300).contains(response.statusCode),
              let payload = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return nil
        }
        var capabilities: [String: OpenRouterReasoningCapability] = [:]
        for model in payload.data {
            guard let reasoning = model.reasoning else { continue }
            capabilities[model.id] = OpenRouterReasoningCapability(
                isMandatory: reasoning.mandatory ?? false,
                supportedEfforts: reasoning.supportedEfforts ?? []
            )
        }
        return capabilities
    }

    private struct ModelsResponse: Decodable {
        let data: [Model]
    }

    private struct Model: Decodable {
        let id: String
        let reasoning: Reasoning?
    }

    private struct Reasoning: Decodable {
        let mandatory: Bool?
        let supportedEfforts: [String]?

        private enum CodingKeys: String, CodingKey {
            case mandatory
            case supportedEfforts = "supported_efforts"
        }
    }
}
