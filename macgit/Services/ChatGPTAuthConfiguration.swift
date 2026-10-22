// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// OpenAI "Sign in with ChatGPT" values for open-source apps, verified against
/// developers.openai.com/siwc/token-sharing-open-source (2026-10-22).
struct ChatGPTAuthConfiguration: Sendable {
    var authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    var tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    var discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    var issuer = "https://auth.openai.com"
    var resource = "https://api.openai.com/v1"
    var responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    var modelsURL = URL(string: "https://api.openai.com/v1/models")!
    var agentName = "Commit+"
    /// First-time registration entry point; the callback returns the issued client ID.
    var dynamicClientID = "dynamic_agent_client"
    var callbackPath = "/auth/callback"
    var preferredLoopbackPort: UInt16 = 1455

    static let planUsageScope = "chatgpt.tokens.use.direct"
    static let scopes = ["openid", "profile", "email", "offline_access", "resource.invoke", planUsageScope]

    static let live = ChatGPTAuthConfiguration()

    func authorizationURL(
        clientID: String?,
        hostID: String,
        loginHint: String?,
        redirectURI: URL,
        state: String,
        nonce: String,
        codeChallenge: String
    ) -> URL {
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
