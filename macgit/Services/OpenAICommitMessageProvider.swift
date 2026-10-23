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
    private let client: OpenAIResponsesClient

    var supportsRepositoryAgent: Bool { true }

    init(
        credentialStore: any AIProviderCredentialStore,
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        streamingSession: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        let descriptor = descriptor
        client = OpenAIResponsesClient(
            descriptor: descriptor,
            modelStore: modelStore,
            httpClient: httpClient,
            endpoint: endpoint,
            streamingSession: streamingSession,
            transport: .standard,
            bearerToken: {
                try CloudAIProviderSupport.apiKey(for: descriptor, credentialStore: credentialStore)
            },
            validate: { response, data, _ in
                try CloudAIProviderSupport.validate(response: response, data: data, providerName: descriptor.displayName)
            },
            streamFailure: { _, message, _ in
                CommitMessageGenerationError.providerRequestFailed(
                    message ?? "\(descriptor.displayName) request failed."
                )
            }
        )
    }

    func availability() async -> AIProviderAvailability {
        CloudAIProviderSupport.availability(for: descriptor, credentialStore: credentialStore)
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
}
