// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Uses a connected ChatGPT plan through OpenAI's "Sign in with ChatGPT" plan
/// usage. Plan-limit failures never fall back to API billing or another provider.
struct ChatGPTSubscriptionProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .chatGPTSubscription,
        displayName: "ChatGPT",
        systemImage: "person.crop.circle",
        detail: "ChatGPT plan · GPT-6.1 Sol",
        dataProcessing: .cloud,
        billing: .connectedAccount,
        requiresProToConfigureAPIKey: true,
        defaultModel: "gpt-6.1-sol",
        inputCharacterBudget: 12_000,
        isImplemented: true
    )

    let session: ChatGPTAccountSession
    private let httpClient: any AIProviderHTTPClient
    private let modelsURL: URL
    private let client: OpenAIResponsesClient

    var supportsRepositoryAgent: Bool { true }

    init(
        session: ChatGPTAccountSession,
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        configuration: ChatGPTAuthConfiguration = .live,
        streamingSession: URLSession = .shared
    ) {
        self.session = session
        self.httpClient = httpClient
        modelsURL = configuration.modelsURL
        client = OpenAIResponsesClient(
            descriptor: descriptor,
            modelStore: modelStore,
            httpClient: httpClient,
            endpoint: configuration.responsesURL,
            streamingSession: streamingSession,
            transport: .streamingRequired,
            bearerToken: { try await session.accessToken() },
            validate: { response, data in
                guard !(200..<300).contains(response.statusCode) else { return }
                let failure = Self.failure(in: data)
                throw await Self.error(
                    status: response.statusCode,
                    code: failure.code,
                    message: failure.message,
                    session: session
                )
            },
            streamFailure: { code, message in
                await Self.error(status: nil, code: code, message: message, session: session)
            }
        )
    }

    func availability() async -> AIProviderAvailability {
        await session.availability()
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        try await client.generateCommitMessage(request: request)
    }

    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> RepositoryAIAnswer {
        try await client.generateRepositoryResponse(request: request)
    }

    func streamRepositoryResponse(
        request: RepositoryAIRequest,
        onTextDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> RepositoryAIAnswer {
        try await client.streamRepositoryResponse(request: request, onTextDelta: onTextDelta)
    }

    func generateRepositoryAgentTurn(
        request: RepositoryAIAgentRequest
    ) async throws -> RepositoryAIAgentTurn {
        try await client.generateRepositoryAgentTurn(request: request)
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        try await client.generateConflictResolution(request: request)
    }

    /// Models the signed-in account can use, from `GET /v1/models`.
    func availableModels() async throws -> [AIProviderModelOption] {
        var request = URLRequest(url: modelsURL, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try await session.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let failure = Self.failure(in: data)
            throw await Self.error(status: response.statusCode, code: failure.code, message: failure.message, session: session)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let listed: [String]
        if let models = object["models"] as? [[String: Any]] {
            listed = models
                .filter { ($0["visibility"] as? String).map { $0 == "list" } ?? true }
                .compactMap { $0["slug"] as? String }
        } else {
            listed = (object["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        }
        return listed.map {
            AIProviderModelOption(
                id: $0,
                name: AIProviderModelCatalog.displayName(for: $0, provider: .chatGPTSubscription),
                group: "Available Models"
            )
        }
    }

    // MARK: Error mapping

    static func failure(in data: Data) -> (code: String?, message: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        if let error = object["error"] as? [String: Any] {
            return (error["code"] as? String, error["message"] as? String)
        }
        return (nil, (object["detail"] as? String) ?? (object["message"] as? String))
    }

    static func error(
        status: Int?,
        code: String?,
        message: String?,
        session: ChatGPTAccountSession
    ) async -> any Error {
        switch code {
        case "subscription_sharing_usage_limit_exceeded":
            await session.recordPlanIssue(.usageLimitReached)
            return CommitMessageGenerationError.chatGPTUsageLimitReached
        case "subscription_sharing_user_not_eligible":
            await session.recordPlanIssue(.notEligible)
            return CommitMessageGenerationError.chatGPTPlanNotEligible
        case "subscription_sharing_invalid_user":
            await session.signOutLocally()
            return CommitMessageGenerationError.chatGPTSignInRequired
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            return CommitMessageGenerationError.providerRequestFailed(
                "ChatGPT plan usage is temporarily unavailable. Try again shortly."
            )
        default:
            if status == 401 {
                // The access token was rejected; keeping it would fail every later request.
                await session.signOutLocally()
                return CommitMessageGenerationError.chatGPTSignInRequired
            }
            let fallback = status.map { "ChatGPT request failed (HTTP \($0))." } ?? "ChatGPT request failed."
            return CommitMessageGenerationError.providerRequestFailed(message ?? fallback)
        }
    }
}
