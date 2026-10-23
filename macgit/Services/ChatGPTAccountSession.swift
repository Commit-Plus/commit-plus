// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

struct ChatGPTAccountSummary: Equatable, Sendable {
    var email: String?
    /// The ChatGPT plan type, known only for the Codex flow (for example "free" or "plus").
    var planType: String?
}

/// A previously registered ChatGPT account that a plain sign-in returns to.
struct ChatGPTReturningAccount: Equatable, Sendable {
    var email: String?
}

enum ChatGPTPlanIssue: Equatable, Sendable {
    case usageLimitReached
    case notEligible
    /// OpenAI refused the unofficial Codex client; retried after the usage-limit cooldown.
    case clientRejected
}

enum ChatGPTAuthError: LocalizedError, Equatable {
    case consentDenied
    case planScopeNotGranted
    case missingClientID
    case invalidIDToken
    case tokenRequestFailed(String)
    case noPendingSignIn
    case timedOut
    case clientRejected
    case loopbackPortInUse(UInt16)

    var errorDescription: String? {
        switch self {
        case .consentDenied:
            "ChatGPT sign-in was canceled."
        case .planScopeNotGranted:
            "ChatGPT plan access was not granted. Sign in again and allow Commit+ to use your ChatGPT plan."
        case .missingClientID:
            "ChatGPT did not return a client registration for Commit+. Try signing in again."
        case .invalidIDToken:
            "ChatGPT returned a sign-in that could not be verified. Try signing in again."
        case .tokenRequestFailed(let message):
            message
        case .noPendingSignIn:
            "No ChatGPT sign-in is in progress."
        case .timedOut:
            "ChatGPT sign-in timed out. Try again."
        case .clientRejected:
            CommitMessageGenerationError.codexClientRejected.localizedDescription
        case .loopbackPortInUse(let port):
            "Port \(port) is in use. Close other ChatGPT sign-ins and try again."
        }
    }
}

/// Owns the ChatGPT sign-in: the PKCE authorization, Keychain token storage,
/// and refresh. Tokens never leave this actor except as the bearer credential.
actor ChatGPTAccountSession {
    private struct PendingAuthorization {
        let state: String
        let nonce: String
        let codeVerifier: String
        let redirectURI: URL
        let clientID: String?
    }

    /// The access token is refreshed when it expires within this interval.
    static let refreshLeeway: TimeInterval = 300
    /// How long a reached plan limit keeps the provider unavailable before it is tried again.
    static let usageLimitCooldown: TimeInterval = 15 * 60

    let configuration: ChatGPTAuthConfiguration
    private let store: any ChatGPTCredentialStoring
    private let httpClient: any AIProviderHTTPClient
    private let now: @Sendable () -> Date
    private var pending: PendingAuthorization?
    private var cachedTokens: ChatGPTTokenSet??
    private var refreshTask: Task<ChatGPTTokenSet, any Error>?
    /// Changes whenever the local tokens are cleared or replaced, so a refresh that
    /// was in flight at that point cannot save its result over the newer state.
    private var credentialGeneration = 0
    private var planIssue: (issue: ChatGPTPlanIssue, date: Date)?

    init(
        store: any ChatGPTCredentialStoring = KeychainChatGPTCredentialStore(),
        httpClient: any AIProviderHTTPClient = URLSessionAIProviderHTTPClient(),
        configuration: ChatGPTAuthConfiguration = .live,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.httpClient = httpClient
        self.configuration = configuration
        self.now = now
    }

    // MARK: Account state

    func account() -> ChatGPTAccountSummary? {
        guard let tokens = try? tokens() else { return nil }
        return ChatGPTAccountSummary(email: tokens.email, planType: tokens.planType)
    }

    /// The ChatGPT account ID the Codex backend expects in `ChatGPT-Account-ID`.
    func chatGPTAccountID() -> String? {
        (try? tokens())??.accountID
    }

    func availability() -> AIProviderAvailability {
        guard (try? tokens()) != nil else {
            return .unavailable(
                configuration.flow == .codex
                    ? "Sign in to ChatGPT (Codex) in Settings → AI."
                    : "Sign in to ChatGPT in Settings → AI."
            )
        }
        switch planIssue {
        case (.notEligible, _)?:
            return .unavailable(planNotEligibleError.localizedDescription)
        case (.usageLimitReached, let date)? where now().timeIntervalSince(date) < Self.usageLimitCooldown:
            return .unavailable(usageLimitError.localizedDescription)
        case (.clientRejected, let date)? where now().timeIntervalSince(date) < Self.usageLimitCooldown:
            return .unavailable(CommitMessageGenerationError.codexClientRejected.localizedDescription)
        default:
            return .available
        }
    }

    private var signInRequiredError: CommitMessageGenerationError {
        configuration.flow == .codex ? .codexSignInRequired : .chatGPTSignInRequired
    }

    private var usageLimitError: CommitMessageGenerationError {
        configuration.flow == .codex ? .codexUsageLimitReached : .chatGPTUsageLimitReached
    }

    private var planNotEligibleError: CommitMessageGenerationError {
        configuration.flow == .codex ? .codexPlanNotAllowed : .chatGPTPlanNotEligible
    }

    func recordPlanIssue(_ issue: ChatGPTPlanIssue) {
        planIssue = (issue, now())
    }

    /// Clears the local tokens after OpenAI rejects `rejectedAccessToken`, unless a
    /// refresh or a new sign-in has already replaced it.
    func signOutLocally(rejectedAccessToken: String) {
        guard (try? tokens())??.accessToken == rejectedAccessToken else { return }
        signOutLocally()
    }

    /// Clears the local tokens; the user must sign in again.
    func signOutLocally() {
        try? store.deleteTokens()
        cachedTokens = .some(nil)
        refreshTask = nil
        planIssue = nil
        credentialGeneration += 1
    }

    // MARK: Authorization

    /// The account whose issued client ID a plain sign-in reuses, if one was registered.
    func returningAccount() -> ChatGPTReturningAccount? {
        guard configuration.usesDynamicRegistration,
              let registration = try? store.loadRegistration(), registration.clientID != nil else { return nil }
        return ChatGPTReturningAccount(email: registration.email)
    }

    /// Starts a sign-in. An issued client ID is bound to the account and workspace that
    /// registered it, so `newAccount` registers a fresh client for a different account.
    func beginAuthorization(redirectURI: URL, newAccount: Bool = false) throws -> URL {
        if !configuration.usesDynamicRegistration {
            // A fixed client: no registration, and the Codex flow sends no nonce.
            let verifier = GitProviderPKCE.generateVerifier()
            let request = PendingAuthorization(
                state: GitProviderPKCE.generateVerifier(),
                nonce: "",
                codeVerifier: verifier,
                redirectURI: redirectURI,
                clientID: configuration.fixedClientID
            )
            pending = request
            return configuration.authorizationURL(
                clientID: request.clientID,
                hostID: "",
                loginHint: nil,
                redirectURI: redirectURI,
                state: request.state,
                nonce: request.nonce,
                codeChallenge: GitProviderPKCE.challenge(for: verifier)
            )
        }
        var registration: ChatGPTRegistration
        if let saved = try store.loadRegistration() {
            registration = saved
        } else {
            registration = ChatGPTRegistration(hostID: "urn:uuid:\(UUID().uuidString.lowercased())")
            try store.saveRegistration(registration)
        }
        if newAccount {
            registration.clientID = nil
            registration.email = nil
        }
        let verifier = GitProviderPKCE.generateVerifier()
        let request = PendingAuthorization(
            state: GitProviderPKCE.generateVerifier(),
            nonce: GitProviderPKCE.generateVerifier(),
            codeVerifier: verifier,
            redirectURI: redirectURI,
            clientID: registration.clientID
        )
        pending = request
        return configuration.authorizationURL(
            clientID: registration.clientID,
            hostID: registration.hostID,
            loginHint: registration.email,
            redirectURI: redirectURI,
            state: request.state,
            nonce: request.nonce,
            codeChallenge: GitProviderPKCE.challenge(for: verifier)
        )
    }

    func cancelAuthorization() {
        pending = nil
    }

    /// Completes the pending sign-in from the loopback callback. A callback that
    /// does not match the pending state throws `GitProviderOAuthError` and leaves
    /// the sign-in pending, so unsolicited requests are ignored.
    func completeAuthorization(callbackURL: URL) async throws -> ChatGPTAccountSummary {
        guard let request = pending else { throw ChatGPTAuthError.noPendingSignIn }
        let callback: GitProviderOAuthCallback
        do {
            callback = try GitProviderOAuthCallback.parse(
                callbackURL,
                redirectURI: request.redirectURI,
                expectedState: request.state
            )
        } catch let error as GitProviderOAuthError {
            switch error {
            case .stateMismatch, .missingState, .unsupportedCallback:
                throw error
            case .accessDenied:
                pending = nil
                throw ChatGPTAuthError.consentDenied
            case .providerMessage:
                // Parsing verifies the state first; keep the check so an unsolicited
                // error callback can never cancel the pending sign-in.
                guard Self.queryValue("state", in: callbackURL) == request.state else {
                    throw GitProviderOAuthError.stateMismatch
                }
                pending = nil
                let code = Self.queryValue("error", in: callbackURL)
                if configuration.flow == .codex, let code, Self.rejectedClientErrors.contains(code) {
                    throw ChatGPTAuthError.clientRejected
                }
                throw code == "access_denied" ? ChatGPTAuthError.consentDenied : error
            case .missingCode:
                pending = nil
                throw error
            }
        }
        pending = nil

        if !configuration.usesDynamicRegistration {
            return try await completeFixedClientAuthorization(request: request, code: callback.code)
        }

        let callbackClientID = Self.queryValue("client_id", in: callbackURL)
        if let saved = request.clientID, let callbackClientID, callbackClientID != saved {
            throw ChatGPTAuthError.missingClientID
        }
        guard let clientID = callbackClientID ?? request.clientID,
              clientID != configuration.dynamicClientID else {
            throw ChatGPTAuthError.missingClientID
        }
        var registration = try store.loadRegistration()
            ?? ChatGPTRegistration(hostID: "urn:uuid:\(UUID().uuidString.lowercased())")
        let replacesSavedClient = registration.clientID != nil && registration.clientID != clientID
        if registration.clientID != clientID {
            // A new registration replaces the previous account's client ID and email.
            registration.email = nil
        }
        registration.clientID = clientID
        // Another account's registration replaces the saved one only after its sign-in succeeds.
        if !replacesSavedClient {
            try store.saveRegistration(registration)
        }

        let response = try await tokenRequest([
            ("grant_type", "authorization_code"),
            ("code", callback.code),
            ("redirect_uri", request.redirectURI.absoluteString),
            ("client_id", clientID),
            ("code_verifier", request.codeVerifier),
            ("resource", configuration.resource),
        ])
        if case .failure(let code, let message, let status) = response {
            if code == "invalid_client", !replacesSavedClient {
                // The saved registration is no longer valid; the next sign-in registers again.
                registration.clientID = nil
                try? store.saveRegistration(registration)
            }
            throw ChatGPTAuthError.tokenRequestFailed(
                message ?? "ChatGPT sign-in failed (\(code ?? "HTTP \(status)")). Try again."
            )
        }
        guard case .success(let payload) = response,
              let refreshToken = payload.refreshToken else {
            throw ChatGPTAuthError.tokenRequestFailed("ChatGPT did not return a renewable sign-in.")
        }
        let scopes = payload.scope?.split(separator: " ").map(String.init) ?? []
        guard scopes.contains(ChatGPTAuthConfiguration.planUsageScope) else {
            throw ChatGPTAuthError.planScopeNotGranted
        }
        guard let idToken = payload.idToken,
              let claims = Self.validatedClaims(
                idToken: idToken,
                issuer: configuration.issuer,
                clientID: clientID,
                nonce: request.nonce,
                now: now()
              ) else {
            throw ChatGPTAuthError.invalidIDToken
        }

        let tokens = ChatGPTTokenSet(
            clientID: clientID,
            accessToken: payload.accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            expiresAt: now().addingTimeInterval(payload.expiresIn ?? 3_600),
            scopes: scopes,
            email: claims["email"] as? String,
            accountID: claims["sub"] as? String
        )
        credentialGeneration += 1
        try store.saveTokens(tokens)
        cachedTokens = .some(tokens)
        refreshTask = nil
        planIssue = nil
        registration.email = tokens.email
        try? store.saveRegistration(registration)
        return ChatGPTAccountSummary(email: tokens.email)
    }

    /// Exchanges the code for the Codex flow: a fixed client, no `resource`, and the
    /// account ID and plan type read from the ID token's OpenAI claims.
    private func completeFixedClientAuthorization(
        request: PendingAuthorization,
        code: String
    ) async throws -> ChatGPTAccountSummary {
        guard let clientID = request.clientID else { throw ChatGPTAuthError.missingClientID }
        let response = try await tokenRequest([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", request.redirectURI.absoluteString),
            ("client_id", clientID),
            ("code_verifier", request.codeVerifier),
        ])
        if case .failure(let code, let message, let status) = response {
            if let code, Self.rejectedClientErrors.contains(code) {
                throw ChatGPTAuthError.clientRejected
            }
            throw ChatGPTAuthError.tokenRequestFailed(
                message ?? "ChatGPT sign-in failed (\(code ?? "HTTP \(status)")). Try again."
            )
        }
        guard case .success(let payload) = response,
              let refreshToken = payload.refreshToken else {
            throw ChatGPTAuthError.tokenRequestFailed("ChatGPT did not return a renewable sign-in.")
        }
        guard let idToken = payload.idToken,
              let claims = Self.validatedClaims(
                idToken: idToken,
                issuer: configuration.issuer,
                clientID: clientID,
                nonce: nil,
                now: now()
              ),
              let auth = claims[ChatGPTAuthConfiguration.codexAuthClaimsKey] as? [String: Any],
              let accountID = auth["chatgpt_account_id"] as? String,
              !accountID.isEmpty else {
            throw ChatGPTAuthError.invalidIDToken
        }
        let profile = claims[ChatGPTAuthConfiguration.codexProfileClaimsKey] as? [String: Any]
        let tokens = ChatGPTTokenSet(
            clientID: clientID,
            accessToken: payload.accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            expiresAt: now().addingTimeInterval(payload.expiresIn ?? 3_600),
            scopes: payload.scope?.split(separator: " ").map(String.init) ?? configuration.scopes,
            email: (profile?["email"] as? String) ?? (claims["email"] as? String),
            accountID: accountID,
            planType: auth["chatgpt_plan_type"] as? String
        )
        credentialGeneration += 1
        try store.saveTokens(tokens)
        cachedTokens = .some(tokens)
        refreshTask = nil
        planIssue = nil
        return ChatGPTAccountSummary(email: tokens.email, planType: tokens.planType)
    }

    private static let rejectedClientErrors: Set<String> = ["invalid_client", "unauthorized_client"]

    // MARK: Tokens

    /// A valid access token, refreshed when it is about to expire. Concurrent
    /// callers share one refresh because refresh tokens rotate.
    func accessToken() async throws -> String {
        guard let tokens = try tokens() else {
            throw signInRequiredError
        }
        if tokens.expiresAt.timeIntervalSince(now()) > Self.refreshLeeway {
            return tokens.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        let generation = credentialGeneration
        let task = Task { try await self.refresh(tokens, generation: generation) }
        refreshTask = task
        defer { if refreshTask == task { refreshTask = nil } }
        return try await task.value.accessToken
    }

    private func refresh(_ tokens: ChatGPTTokenSet, generation: Int) async throws -> ChatGPTTokenSet {
        let response = try await tokenRequest([
            ("grant_type", "refresh_token"),
            ("client_id", tokens.clientID),
            ("refresh_token", tokens.refreshToken),
            configuration.flow == .codex
                ? ("scope", configuration.scopes.joined(separator: " "))
                : ("resource", configuration.resource),
        ])
        let isCurrent = generation == credentialGeneration
        switch response {
        case .failure(let code, let message, let status):
            // The Codex CLI also treats any 401 from the token endpoint as permanent.
            let isTerminal = code.map(Self.terminalRefreshErrors.contains) ?? false
                || (configuration.flow == .codex && status == 401)
            if isTerminal {
                if isCurrent { signOutLocally() }
                throw signInRequiredError
            }
            throw CommitMessageGenerationError.providerRequestFailed(
                message ?? "ChatGPT sign-in could not be renewed. Try again."
            )
        case .success(let payload):
            var updated = tokens
            updated.accessToken = payload.accessToken
            updated.refreshToken = payload.refreshToken ?? tokens.refreshToken
            updated.expiresAt = now().addingTimeInterval(payload.expiresIn ?? 3_600)
            if let scope = payload.scope {
                updated.scopes = scope.split(separator: " ").map(String.init)
            }
            if let idToken = payload.idToken { updated.idToken = idToken }
            guard isCurrent else {
                // Signed out or signed in again while this refresh was in flight.
                if case .some(nil) = cachedTokens { await revoke(updated) }
                throw signInRequiredError
            }
            try store.saveTokens(updated)
            cachedTokens = .some(updated)
            return updated
        }
    }

    private static let terminalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
        "refresh_token_invalidated", "refresh_token_reused", "invalid_client",
    ]

    private func tokens() throws -> ChatGPTTokenSet? {
        if let cachedTokens { return cachedTokens }
        let loaded = try store.loadTokens()
        cachedTokens = .some(loaded)
        return loaded
    }

    // MARK: Disconnect

    /// Deletes the local tokens, then revokes the grant when OpenAI is reachable.
    /// The registration (issued client ID and host ID) is kept for later sign-ins.
    func disconnect() async {
        pending = nil
        let current = try? tokens()
        signOutLocally()
        if let current {
            await revoke(current)
        }
    }

    private func revoke(_ tokens: ChatGPTTokenSet) async {
        guard let endpoint = await revocationEndpoint() else { return }
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ChatGPTAuthConfiguration.formBody([
            ("token", tokens.refreshToken),
            ("token_type_hint", "refresh_token"),
            ("client_id", tokens.clientID),
        ])
        _ = try? await httpClient.data(for: request)
    }

    private func revocationEndpoint() async -> URL? {
        if let revocationURL = configuration.revocationURL { return revocationURL }
        var discovery = URLRequest(url: configuration.discoveryURL, timeoutInterval: 10)
        discovery.httpMethod = "GET"
        guard let (data, response) = try? await httpClient.data(for: discovery),
              (200..<300).contains(response.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (object["revocation_endpoint"] as? String).flatMap(URL.init(string:))
    }

    // MARK: Token endpoint

    private struct TokenPayload: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: TimeInterval?
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
            case scope
        }
    }

    private enum TokenResponse {
        case success(TokenPayload)
        case failure(code: String?, message: String?, status: Int)
    }

    private func tokenRequest(_ fields: [(String, String)]) async throws -> TokenResponse {
        var request = URLRequest(url: configuration.tokenURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = ChatGPTAuthConfiguration.formBody(fields)
        let (data, response) = try await httpClient.data(for: request)
        if (200..<300).contains(response.statusCode) {
            guard let payload = try? JSONDecoder().decode(TokenPayload.self, from: data) else {
                return .failure(
                    code: nil,
                    message: "ChatGPT returned an unexpected sign-in response. Try again.",
                    status: response.statusCode
                )
            }
            return .success(payload)
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let nested = object?["error"] as? [String: Any]
        let code = (object?["error"] as? String) ?? (nested?["code"] as? String)
        let message = (object?["error_description"] as? String) ?? (nested?["message"] as? String)
        return .failure(code: code, message: message, status: response.statusCode)
    }

    // MARK: Helpers

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    /// Checks the ID token's issuer, audience, expiry, and nonce (when one was sent).
    /// The token comes directly from the token endpoint over TLS, which OIDC Core
    /// §3.1.3.7 accepts in place of a signature check.
    static func validatedClaims(
        idToken: String,
        issuer: String,
        clientID: String,
        nonce: String?,
        now: Date
    ) -> [String: Any]? {
        let parts = idToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              claims["iss"] as? String == issuer,
              nonce == nil || claims["nonce"] as? String == nonce,
              let exp = claims["exp"] as? TimeInterval,
              Date(timeIntervalSince1970: exp) > now else {
            return nil
        }
        let audiences = (claims["aud"] as? [String]) ?? [claims["aud"] as? String].compactMap { $0 }
        guard audiences.contains(clientID) else { return nil }
        return claims
    }
}
