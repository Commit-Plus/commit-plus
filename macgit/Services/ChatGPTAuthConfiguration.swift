// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The OAuth values for one ChatGPT sign-in flow. `.live` is OpenAI's "Sign in with
/// ChatGPT" for open-source apps, verified against
/// developers.openai.com/siwc/token-sharing-open-source (2026-10-22). `.codex` is the
/// unofficial Codex CLI flow; see `codex` for its sources.
struct ChatGPTAuthConfiguration: Sendable {
    nonisolated enum Flow: Equatable, Sendable {
        /// Official plan usage: dynamic client registration, nonce, and the plan-usage scope.
        case signInWithChatGPT
        /// The Codex CLI's public client: a fixed client ID, no nonce, and Codex usage.
        case codex
    }

    var flow = Flow.signInWithChatGPT
    var authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    var tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    var discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    /// Fixed revocation endpoint; nil reads it from the OpenID discovery document.
    var revocationURL: URL?
    var issuer = "https://auth.openai.com"
    var resource = "https://api.openai.com/v1"
    var responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    var modelsURL = URL(string: "https://api.openai.com/v1/models")!
    var agentName = "Commit+"
    /// First-time registration entry point; the callback returns the issued client ID.
    var dynamicClientID = "dynamic_agent_client"
    /// Fixed client ID for flows without dynamic registration.
    var fixedClientID: String?
    var callbackPath = "/auth/callback"
    var preferredLoopbackPort: UInt16 = 1455
    /// When true the sign-in fails instead of using another port, because the client
    /// allows only `preferredLoopbackPort` in its redirect URI.
    var requiresPreferredLoopbackPort = false
    var loopbackRedirectHost = "127.0.0.1"
    var scopes = Self.scopes

    static let planUsageScope = "chatgpt.tokens.use.direct"
    static let scopes = ["openid", "profile", "email", "offline_access", "resource.invoke", planUsageScope]

    static let live = ChatGPTAuthConfiguration()

    /// The Codex CLI flow, which ChatGPT Free accounts can also use. None of these
    /// values are documented by OpenAI; they were checked against the Codex CLI
    /// (`codex-rs/login`) and TablePro (`Core/AI/ChatGPTCodex`) on 2026-10-23.
    static let codex = ChatGPTAuthConfiguration(
        flow: .codex,
        authorizeURL: URL(string: "https://auth.openai.com/oauth/authorize")!,
        tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
        revocationURL: URL(string: "https://auth.openai.com/oauth/revoke")!,
        responsesURL: URL(string: "https://chatgpt.com/backend-api/codex/responses")!,
        fixedClientID: "app_EMoamEEZ73f0CkXaXp7hrann",
        requiresPreferredLoopbackPort: true,
        loopbackRedirectHost: "localhost",
        scopes: ["openid", "profile", "email", "offline_access", "api.connectors.read", "api.connectors.invoke"]
    )

    /// Identifies requests as the Codex CLI, which the Codex backend requires.
    static let codexOriginator = "codex_cli_rs"
    static let codexUserAgent = "codex_cli_rs/0.1.0"
    static let codexAuthClaimsKey = "https://api.openai.com/auth"
    static let codexProfileClaimsKey = "https://api.openai.com/profile"

    var usesDynamicRegistration: Bool { flow == .signInWithChatGPT }

    func authorizationURL(
        clientID: String?,
        hostID: String,
        loginHint: String?,
        redirectURI: URL,
        state: String,
        nonce: String,
        codeChallenge: String
    ) -> URL {
        if flow == .codex {
            return codexAuthorizationURL(redirectURI: redirectURI, state: state, codeChallenge: codeChallenge)
        }
        var items = [URLQueryItem(name: "client_id", value: clientID ?? dynamicClientID)]
        if clientID == nil {
            items.append(URLQueryItem(name: "agent_name_hint", value: agentName))
        }
        items.append(URLQueryItem(name: "ext_agent_host_id", value: hostID))
        if clientID != nil, let loginHint, !loginHint.isEmpty {
            items.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        items += [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        return components.url!
    }

    private func codexAuthorizationURL(redirectURI: URL, state: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: fixedClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: Self.codexOriginator),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields.map { name, value in
            let value = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(name)=\(value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}
