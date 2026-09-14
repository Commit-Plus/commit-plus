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

struct AIProviderRegistry: Sendable {
    let providers: [any CommitMessageAIProvider]

    var descriptors: [AIProviderDescriptor] {
        providers.map(\.descriptor)
    }

    func provider(for id: AIProviderID) -> (any CommitMessageAIProvider)? {
        providers.first { $0.descriptor.id == id }
    }

    static func live(
        credentialStore: any AIProviderCredentialStore = KeychainAIProviderCredentialStore(),
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        managedProvider: CommitPlusAIProvider? = nil
    ) -> Self {
        var providers: [any CommitMessageAIProvider] = [
            AppleIntelligenceCommitMessageProvider(),
            OpenAICommitMessageProvider(
                credentialStore: credentialStore,
                modelStore: modelStore,
                httpClient: httpClient
            ),
            GeminiCommitMessageProvider(
                credentialStore: credentialStore,
                modelStore: modelStore,
                httpClient: httpClient
            ),
            // Providers requiring Commit+ Pro are listed after the Free-plan providers.
            AnthropicCommitMessageProvider(
                credentialStore: credentialStore,
                modelStore: modelStore,
                httpClient: httpClient
            ),
            DeepSeekCommitMessageProvider(
                credentialStore: credentialStore,
                modelStore: modelStore,
                httpClient: httpClient
            ),
            OpenRouterCommitMessageProvider(
                credentialStore: credentialStore,
                modelStore: modelStore,
                httpClient: httpClient
            ),
        ]
        if let managedProvider { providers.insert(managedProvider, at: 1) }
        return Self(providers: providers)
    }
}
