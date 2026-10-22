// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Caches each OpenRouter model's reasoning capability from OpenRouter's public models API,
/// so the "Thinking" setting only sends reasoning values a model accepts.
actor OpenRouterReasoningCapabilityStore {
    static let shared = OpenRouterReasoningCapabilityStore()

    /// How long a loaded list is used before it is refreshed.
    static let refreshInterval: TimeInterval = 60 * 60
    /// How soon a model missing from the loaded list triggers a refresh, for models released later.
    static let unknownModelRefreshInterval: TimeInterval = 10 * 60
    /// How long requests skip loading after a failed load, so an unreachable API does not
    /// delay every request by the load timeout.
    static let failureBackoff: TimeInterval = 5 * 60

    private let httpClient: any AIProviderHTTPClient
    private let modelsEndpoint: URL
    private let now: @Sendable () -> Date
    private var capabilities: [String: OpenRouterReasoningCapability]?
    /// Every model in the loaded list, including those without reasoning.
    private var knownModels: Set<String> = []
    private var loadedAt: Date?
    private var lastFailureAt: Date?
    private var loadTask: Task<LoadedModels?, Never>?

    init(
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        modelsEndpoint: URL = URL(string: "https://openrouter.ai/api/v1/models")!,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.httpClient = httpClient
        self.modelsEndpoint = modelsEndpoint
        self.now = now
    }

    /// `nil` when the model has no reasoning support or the list could not be loaded.
    func capability(for model: String) async -> OpenRouterReasoningCapability? {
        guard shouldLoad(for: model) else { return capabilities?[model] }
        let task = loadTask ?? Task { [httpClient, modelsEndpoint] in
            await Self.load(httpClient: httpClient, endpoint: modelsEndpoint)
        }
        loadTask = task
        let loaded = await task.value
        loadTask = nil
        if let loaded {
            capabilities = loaded.capabilities
            knownModels = loaded.models
            loadedAt = now()
            lastFailureAt = nil
        } else {
            // Keep any earlier list and back off instead of retrying on every request.
            lastFailureAt = now()
        }
        return capabilities?[model]
    }

    private func shouldLoad(for model: String) -> Bool {
        let date = now()
        if let lastFailureAt, date.timeIntervalSince(lastFailureAt) < Self.failureBackoff {
            return false
        }
        guard capabilities != nil, let loadedAt else { return true }
        let age = date.timeIntervalSince(loadedAt)
        if age >= Self.refreshInterval { return true }
        return !knownModels.contains(model) && age >= Self.unknownModelRefreshInterval
    }

    private static func load(
        httpClient: any AIProviderHTTPClient,
        endpoint: URL
    ) async -> LoadedModels? {
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
        return LoadedModels(models: Set(payload.data.map(\.id)), capabilities: capabilities)
    }

    private struct LoadedModels: Sendable {
        let models: Set<String>
        let capabilities: [String: OpenRouterReasoningCapability]
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
