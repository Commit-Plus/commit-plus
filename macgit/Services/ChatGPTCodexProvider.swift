// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A provider the user connects by signing in to an account instead of saving an API key.
protocol ConnectedAccountAIProvider: CommitMessageAIProvider {
    var session: ChatGPTAccountSession { get }
    /// Models the account can use; empty when the provider has no model list.
    func availableModels() async throws -> [AIProviderModelOption]
}

extension ChatGPTSubscriptionProvider: ConnectedAccountAIProvider {}

/// Unofficial: signs in through the Codex CLI's public OAuth client and sends requests
/// to ChatGPT's Codex backend, billed to the account's Codex usage. This also reaches
/// ChatGPT Free, which the official provider cannot. OpenAI does not support this
/// interface, so failures never fall back to API billing or another provider.
struct ChatGPTCodexProvider: ConnectedAccountAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .chatGPTCodex,
        displayName: "ChatGPT (Codex)",
        systemImage: "person.crop.circle.badge.exclamationmark",
        detail: "Unofficial · ChatGPT Codex usage",
        dataProcessing: .cloud,
        billing: .connectedAccount,
        requiresProToConfigureAPIKey: true,
        defaultModel: "gpt-5.6-sol",
        inputCharacterBudget: 12_000,
        isImplemented: true,
        isUnofficial: true
    )

    let session: ChatGPTAccountSession
    private let client: OpenAIResponsesClient

    var supportsRepositoryAgent: Bool { true }

    init(
        session: ChatGPTAccountSession,
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        streamingSession: URLSession = .shared
    ) {
        self.session = session
        let sessionID = UUID().uuidString
        client = OpenAIResponsesClient(
            descriptor: descriptor,
            modelStore: modelStore,
            httpClient: httpClient,
            endpoint: session.configuration.responsesURL,
            streamingSession: streamingSession,
            transport: .codexBackend,
            bearerToken: { try await session.accessToken() },
            validate: { response, data, bearerToken in
                guard !(200..<300).contains(response.statusCode) else { return }
                let failure = Self.failure(in: data)
                throw await Self.error(
                    status: response.statusCode,
                    code: failure.code,
                    message: failure.message,
                    session: session,
                    rejectedAccessToken: bearerToken
                )
            },
            streamFailure: { code, message, bearerToken in
                await Self.error(
                    status: nil,
                    code: code,
                    message: message,
                    session: session,
                    rejectedAccessToken: bearerToken
                )
            },
            extraHeaders: {
                var headers = [
                    "session-id": sessionID,
                    "originator": ChatGPTAuthConfiguration.codexOriginator,
                    "User-Agent": ChatGPTAuthConfiguration.codexUserAgent,
                ]
                if let accountID = await session.chatGPTAccountID(), !accountID.isEmpty {
                    headers["ChatGPT-Account-ID"] = accountID
                }
                return headers
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

    /// The Codex backend has no model list; Settings shows the curated catalog.
    func availableModels() async throws -> [AIProviderModelOption] { [] }

    // MARK: Error mapping

    /// The Codex backend puts the cause in `error.type` on HTTP 429 and in
    /// `error.code` elsewhere, so the code falls back to the type.
    static func failure(in data: Data) -> (code: String?, message: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        if let error = object["error"] as? [String: Any] {
            let code = (error["code"] as? String) ?? (error["type"] as? String)
            return (code, error["message"] as? String)
        }
        return (nil, (object["detail"] as? String) ?? (object["message"] as? String))
    }

    static func error(
        status: Int?,
        code: String?,
        message: String?,
        session: ChatGPTAccountSession,
        rejectedAccessToken: String
    ) async -> any Error {
        switch code {
        case "usage_limit_reached", "rate_limit_exceeded":
            await session.recordPlanIssue(.usageLimitReached)
            return CommitMessageGenerationError.codexUsageLimitReached
        case "usage_not_included":
            await session.recordPlanIssue(.notEligible)
            return CommitMessageGenerationError.codexPlanNotAllowed
        case "invalid_client", "unauthorized_client":
            await session.recordPlanIssue(.clientRejected)
            return CommitMessageGenerationError.codexClientRejected
        default:
            switch status {
            case 401:
                // The access token was rejected; keeping it would fail every later request.
                await session.signOutLocally(rejectedAccessToken: rejectedAccessToken)
                return CommitMessageGenerationError.codexSignInRequired
            case 429:
                await session.recordPlanIssue(.usageLimitReached)
                return CommitMessageGenerationError.codexUsageLimitReached
            case 403:
                await session.recordPlanIssue(.clientRejected)
                return CommitMessageGenerationError.codexClientRejected
            default:
                let fallback = status.map { "ChatGPT (Codex) request failed (HTTP \($0))." }
                    ?? "ChatGPT (Codex) request failed."
                return CommitMessageGenerationError.providerRequestFailed(message ?? fallback)
            }
        }
    }
}
