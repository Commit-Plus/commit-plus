// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// How a device-code sign-in starts: the server may already hold a valid sign-in.
enum DeviceCodeSignInStart: Equatable, Sendable {
    case signedIn(ConnectedAIAccountSummary)
    case deviceCode(GitProviderDeviceAuthorization)
}

/// A connected-account provider that signs in with a GitHub device code inside a
/// vendor process (GitHub Copilot), so Commit+ never handles the account's token.
protocol DeviceCodeAccountAIProvider: CommitMessageAIProvider {
    var isTelemetryEnabled: Bool { get }
    func setTelemetryEnabled(_ isEnabled: Bool) async
    /// The account connected on this Mac, or nil when it was never connected or was removed.
    func connectedAccount() async -> ConnectedAIAccountSummary?
    func beginSignIn() async throws -> DeviceCodeSignInStart
    /// Waits until the device code is approved. Cancelling the task cancels the wait.
    func completeSignIn() async throws -> ConnectedAIAccountSummary
    /// Cleans up after a sign-in that was cancelled or failed, so nothing stays signed in.
    func cancelSignIn() async
    func signOut() async
    func resetAfterFailure() async
    /// Chat models the signed-in account can use, the account's default model first.
    func availableModels() async throws -> [AIProviderModelOption]
}

/// The part of `CopilotLanguageServerClient` the account session uses; a seam for tests.
nonisolated protocol CopilotLanguageServerRequesting: Sendable {
    var isRunning: Bool { get async }
    func request(
        _ method: String,
        params: CopilotJSON,
        progressToken: String?,
        onProgress: CopilotLanguageServerClient.ProgressHandler?
    ) async throws -> CopilotJSON
    func setNotificationHandler(_ handler: CopilotLanguageServerClient.NotificationHandler?) async
    func setTelemetryEnabled(_ enabled: Bool) async
    func resetAfterFailure() async
    func terminate() async
}

extension CopilotLanguageServerClient: CopilotLanguageServerRequesting {}

nonisolated extension CopilotLanguageServerRequesting {
    func request(_ method: String, params: CopilotJSON = .object([:])) async throws -> CopilotJSON {
        try await request(method, params: params, progressToken: nil, onProgress: nil)
    }
}

/// Owns Copilot sign-in, entitlement, quota, and model state on top of the language
/// server. Only the GitHub login is stored, locally, to remember that Copilot was
/// connected; tokens stay inside the server's own isolated auth store.
actor GitHubCopilotAccountSession {
    enum Status: Equatable {
        case signedIn(String)
        case notSignedIn
        case noAccess
    }

    static let shared: GitHubCopilotAccountSession = {
        let client = CopilotLanguageServerClient.shared
        client.terminateOnAppQuit()
        return GitHubCopilotAccountSession(
            client: client,
            authDirectory: CopilotLanguageServerRuntime.configHomeDirectory
        )
    }()

    static let connectedLoginDefaultsKey = "ai.githubCopilot.connectedLogin"
    static let telemetryDefaultsKey = "ai.githubCopilot.telemetryEnabled"
    /// How long an exhausted quota keeps the provider unavailable before it is tried again.
    static let quotaCooldown: TimeInterval = 15 * 60
    static let modelGroup = "Available Models"

    private let client: any CopilotLanguageServerRequesting
    nonisolated let defaults: UserDefaults
    /// The server's auth store; deleted on sign-out so the Mac is signed out even when the server cannot run.
    private let authDirectory: URL?
    private let now: @Sendable () -> Date
    private var didPrepare = false
    private var pendingCommand: CopilotJSON?
    private var status: Status?
    private var plan: String?
    private var quotaExhaustedAt: Date?
    private var models: [CopilotJSON]?

    init(
        client: any CopilotLanguageServerRequesting,
        defaults: UserDefaults = .standard,
        authDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.defaults = defaults
        self.authDirectory = authDirectory
        self.now = now
    }

    // MARK: Account state

    nonisolated var isTelemetryEnabled: Bool {
        // The server's own default is to send telemetry.
        defaults.object(forKey: Self.telemetryDefaultsKey) as? Bool ?? true
    }

    func setTelemetryEnabled(_ isEnabled: Bool) async {
        defaults.set(isEnabled, forKey: Self.telemetryDefaultsKey)
        await client.setTelemetryEnabled(isEnabled)
    }

    private var connectedLogin: String? {
        defaults.string(forKey: Self.connectedLoginDefaultsKey)
    }

    func connectedAccount() -> ConnectedAIAccountSummary? {
        guard let login = connectedLogin else { return nil }
        return ConnectedAIAccountSummary(planType: plan, username: login, requiresSignIn: status == .notSignedIn)
    }

    func availability() async -> AIProviderAvailability {
        guard connectedLogin != nil else {
            return .unavailable("Sign in to GitHub Copilot in Settings → AI.")
        }
        do {
            switch try await checkStatus() {
            case .signedIn:
                if let quotaExhaustedAt, now().timeIntervalSince(quotaExhaustedAt) < Self.quotaCooldown {
                    return .unavailable(CommitMessageGenerationError.copilotQuotaExhausted.localizedDescription)
                }
                return .available
            case .notSignedIn:
                return .unavailable(CommitMessageGenerationError.copilotSignInRequired.localizedDescription)
            case .noAccess:
                return .unavailable(CommitMessageGenerationError.copilotNoAccess.localizedDescription)
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func resetAfterFailure() async {
        await client.resetAfterFailure()
    }

    // MARK: Sign-in

    func beginSignIn() async throws -> DeviceCodeSignInStart {
        pendingCommand = nil
        switch try await checkStatus() {
        case .signedIn(let login):
            return .signedIn(connect(login))
        case .noAccess:
            // Signed in to an account without Copilot; sign out so another account can be used.
            _ = try? await request("signOut")
        case .notSignedIn:
            break
        }
        let result = try await request("signInInitiate")
        switch result["status"]?.stringValue {
        case "AlreadySignedIn":
            return .signedIn(try await verifyEntitlement())
        case "PromptUserDeviceFlow":
            guard let userCode = result["userCode"]?.stringValue,
                  let verificationURI = result["verificationUri"]?.stringValue.flatMap(URL.init(string:)),
                  let command = result["command"] else {
                throw CopilotLanguageServerError.invalidResponse
            }
            pendingCommand = command
            return .deviceCode(GitProviderDeviceAuthorization(
                provider: .github,
                deviceCode: "",
                userCode: userCode,
                verificationURI: verificationURI,
                expiresIn: Int(result["expiresIn"]?.numberValue ?? 900),
                interval: Int(result["interval"]?.numberValue ?? 5)
            ))
        default:
            throw CopilotLanguageServerError.invalidResponse
        }
    }

    func completeSignIn() async throws -> ConnectedAIAccountSummary {
        guard let command = pendingCommand else {
            throw CommitMessageGenerationError.providerRequestFailed("No GitHub Copilot sign-in is in progress.")
        }
        // The server answers only after GitHub approves the device code.
        _ = try await request("workspace/executeCommand", params: .object([
            "command": command["command"] ?? .null,
            "arguments": command["arguments"] ?? .array([])
        ]))
        pendingCommand = nil
        return try await verifyEntitlement()
    }

    private func verifyEntitlement() async throws -> ConnectedAIAccountSummary {
        switch try await checkStatus() {
        case .signedIn(let login):
            return connect(login)
        case .noAccess:
            // Keep nothing for an account that cannot use Copilot.
            _ = try? await request("signOut")
            status = .notSignedIn
            throw CommitMessageGenerationError.copilotNoAccess
        case .notSignedIn:
            throw CommitMessageGenerationError.providerRequestFailed("GitHub sign-in did not complete. Try again.")
        }
    }

    private func connect(_ login: String) -> ConnectedAIAccountSummary {
        defaults.set(login, forKey: Self.connectedLoginDefaultsKey)
        quotaExhaustedAt = nil
        models = nil
        return ConnectedAIAccountSummary(planType: plan, username: login)
    }

    func cancelSignIn() async {
        pendingCommand = nil
        // A code approved just before cancelling leaves the server signed in; a new
        // connection must not be kept. An existing connection keeps its sign-in.
        guard connectedLogin == nil, await client.isRunning else { return }
        if case .signedIn? = try? await checkStatus() {
            _ = try? await request("signOut")
            status = .notSignedIn
        }
    }

    func signOut() async {
        pendingCommand = nil
        if await client.isRunning || connectedLogin != nil {
            _ = try? await request("signOut")
        }
        await client.terminate()
        await client.resetAfterFailure()
        if let authDirectory {
            try? FileManager.default.removeItem(at: authDirectory.appendingPathComponent("github-copilot", isDirectory: true))
        }
        defaults.removeObject(forKey: Self.connectedLoginDefaultsKey)
        status = nil
        plan = nil
        quotaExhaustedAt = nil
        models = nil
    }

    // MARK: Models

    func availableModels() async throws -> [AIProviderModelOption] {
        let chatModels = try await loadModels()
        let defaultID = Self.defaultModelID(in: chatModels)
        let options = chatModels.compactMap { model -> AIProviderModelOption? in
            guard let id = model["id"]?.stringValue else { return nil }
            return AIProviderModelOption(id: id, name: model["modelName"]?.stringValue ?? id, group: Self.modelGroup)
        }
        return options.filter { $0.id == defaultID } + options.filter { $0.id != defaultID }
    }

    /// The saved model while the account still offers it, else the account's default model.
    func resolvedModel(_ savedModel: String?) async throws -> String {
        let chatModels = try await loadModels()
        if let savedModel, chatModels.contains(where: { $0["id"]?.stringValue == savedModel }) {
            return savedModel
        }
        return Self.defaultModelID(in: chatModels)
    }

    private func loadModels() async throws -> [CopilotJSON] {
        if let models { return models }
        let listed = try await request("copilot/models").arrayValue ?? []
        // Only chat-panel models can serve a conversation turn.
        let chatModels = listed.filter { model in
            model["scopes"]?.arrayValue?.contains(.string("chat-panel")) == true
        }
        models = chatModels
        return chatModels
    }

    static func defaultModelID(in chatModels: [CopilotJSON]) -> String {
        let model = chatModels.first { $0["isChatDefault"]?.boolValue == true } ?? chatModels.first
        return model?["id"]?.stringValue ?? "auto"
    }

    // MARK: Chat

    /// Runs one single-turn conversation and returns the full reply.
    func chat(
        prompt: String,
        savedModel: String?,
        onTextDelta: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        let model = try await resolvedModel(savedModel)
        let token = UUID().uuidString
        let (progress, continuation) = AsyncStream<CopilotJSON>.makeStream()
        // Replies stream as `$/progress` reports; a failed turn arrives on the `end` report.
        let collector = Task { () -> (text: String, failure: CopilotJSON?) in
            var text = ""
            var failure: CopilotJSON?
            for await value in progress {
                switch value["kind"]?.stringValue {
                case "report":
                    for round in value["editAgentRounds"]?.arrayValue ?? [] {
                        guard let delta = round["reply"]?.stringValue, !delta.isEmpty else { continue }
                        text += delta
                        await onTextDelta?(delta)
                    }
                case "end":
                    failure = value["error"]
                default:
                    break
                }
            }
            return (text, failure)
        }
        do {
            _ = try await request(
                "conversation/create",
                params: .object([
                    "workDoneToken": .string(token),
                    "turns": .array([.object(["request": .string(prompt)])]),
                    "capabilities": .object(["skills": .array([]), "allSkills": .bool(false)]),
                    "source": .string("panel"),
                    "chatMode": .string("Ask"),
                    "needToolCallConfirmation": .bool(false),
                    "modelInfo": .object(["id": .string(model)])
                ]),
                progressToken: token,
                onProgress: { continuation.yield($0) }
            )
        } catch {
            continuation.finish()
            collector.cancel()
            throw error
        }
        continuation.finish()
        let result = await collector.value
        try Task.checkCancellation()
        if let failure = result.failure, failure != .null {
            throw record(Self.failure(
                code: failure["code"]?.numberValue.map(Int.init),
                message: failure["message"]?.stringValue ?? ""
            ))
        }
        return result.text
    }

    // MARK: Server access

    private func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true
        await client.setTelemetryEnabled(isTelemetryEnabled)
        await client.setNotificationHandler { [weak self] method, params in
            Task { await self?.handleNotification(method, params: params) }
        }
    }

    private func request(_ method: String, params: CopilotJSON = .object([:])) async throws -> CopilotJSON {
        try await request(method, params: params, progressToken: nil, onProgress: nil)
    }

    private func request(
        _ method: String,
        params: CopilotJSON,
        progressToken: String?,
        onProgress: CopilotLanguageServerClient.ProgressHandler?
    ) async throws -> CopilotJSON {
        await prepare()
        do {
            return try await client.request(method, params: params, progressToken: progressToken, onProgress: onProgress)
        } catch {
            throw record(Self.mapped(error))
        }
    }

    private func checkStatus() async throws -> Status {
        let result = try await request("checkStatus")
        let next: Status
        switch result["status"]?.stringValue {
        case "OK", "MaybeOK":
            next = .signedIn(result["user"]?.stringValue ?? connectedLogin ?? "GitHub")
        case "NotSignedIn":
            next = .notSignedIn
        default:
            next = .noAccess
        }
        status = next
        if case .signedIn(let login) = next, connectedLogin != nil, connectedLogin != login {
            defaults.set(login, forKey: Self.connectedLoginDefaultsKey)
        }
        return next
    }

    func handleNotification(_ method: String, params: CopilotJSON) {
        switch method {
        case "copilot/quotaChange":
            plan = params["copilotPlan"]?.stringValue ?? plan
            if let chat = params["chat"] {
                let isUnlimited = chat["unlimited"]?.boolValue == true
                let remaining = chat["percentRemaining"]?.numberValue ?? 100
                quotaExhaustedAt = !isUnlimited && remaining <= 0 ? now() : nil
            }
        case "didChangeStatus/v2":
            guard params["category"]?.stringValue == "auth" else { return }
            let authStatus = params["result"]?["status"]?.stringValue ?? params["status"]?.stringValue
            if authStatus == "NotSignedIn" { status = .notSignedIn }
        default:
            break
        }
    }

    /// Keeps availability in step with failures the server reports on a request.
    private func record(_ error: any Error) -> any Error {
        switch error as? CommitMessageGenerationError {
        case .copilotSignInRequired?: status = .notSignedIn
        case .copilotNoAccess?: status = .noAccess
        case .copilotQuotaExhausted?: quotaExhaustedAt = now()
        default: break
        }
        return error
    }

    // MARK: Error mapping

    static func mapped(_ error: any Error) -> any Error {
        switch error {
        case let error as CopilotLanguageServerRuntimeError:
            return CommitMessageGenerationError.copilotServerUnavailable(error.localizedDescription)
        case let error as CopilotLanguageServerError:
            switch error {
            case .responseError(let code, let message):
                return failure(code: code, message: message)
            case .serverExited, .serverUnavailable, .invalidResponse:
                let message = error.localizedDescription
                return CommitMessageGenerationError.copilotServerUnavailable(
                    message.hasSuffix("Try again.") ? message : "\(message) Try again."
                )
            }
        default:
            return error
        }
    }

    /// Maps a Copilot request or turn failure. The server reports HTTP-like codes for
    /// Copilot API failures and code 1000 when it is not signed in.
    static func failure(code: Int?, message: String) -> CommitMessageGenerationError {
        let lowercased = message.lowercased()
        if code == 1000 || code == 401 || lowercased.contains("not authenticated") || lowercased.contains("notsignedin") {
            return .copilotSignInRequired
        }
        if code == 402 || lowercased.contains("quota") {
            return .copilotQuotaExhausted
        }
        if code == 429 || lowercased.contains("rate limit") {
            return .copilotRateLimited
        }
        if code == 403 || lowercased.contains("not authorized") || lowercased.contains("entitle") {
            return .copilotNoAccess
        }
        return .providerRequestFailed(message.isEmpty ? "GitHub Copilot request failed." : message)
    }
}

/// Uses the user's GitHub Copilot plan, including Copilot Free, through GitHub's
/// Copilot language server. No Commit+ plan is required.
struct GitHubCopilotProvider: DeviceCodeAccountAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .githubCopilot,
        displayName: "GitHub Copilot",
        systemImage: "person.crop.circle",
        detail: "Copilot plan · Free or paid",
        dataProcessing: .cloud,
        billing: .connectedAccount,
        requiresProToConfigureAPIKey: false,
        defaultModel: "auto",
        // Model context differs by Copilot plan, and the server adds its own prompt.
        inputCharacterBudget: 12_000,
        isImplemented: true
    )

    let session: GitHubCopilotAccountSession
    private let modelStore: any AIProviderModelStore

    init(
        session: GitHubCopilotAccountSession = .shared,
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore()
    ) {
        self.session = session
        self.modelStore = modelStore
    }

    var isTelemetryEnabled: Bool { session.isTelemetryEnabled }

    func setTelemetryEnabled(_ isEnabled: Bool) async {
        await session.setTelemetryEnabled(isEnabled)
    }

    func availability() async -> AIProviderAvailability {
        await session.availability()
    }

    func connectedAccount() async -> ConnectedAIAccountSummary? {
        await session.connectedAccount()
    }

    func beginSignIn() async throws -> DeviceCodeSignInStart {
        try await session.beginSignIn()
    }

    func completeSignIn() async throws -> ConnectedAIAccountSummary {
        try await session.completeSignIn()
    }

    func cancelSignIn() async {
        await session.cancelSignIn()
    }

    func signOut() async {
        await session.signOut()
    }

    func resetAfterFailure() async {
        await session.resetAfterFailure()
    }

    func availableModels() async throws -> [AIProviderModelOption] {
        try await session.availableModels()
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        let text = try await session.chat(
            prompt: Self.prompt(
                instructions: CloudCommitMessagePrompt.jsonInstructions,
                userPrompt: CloudCommitMessagePrompt.userPrompt(for: request)
            ),
            savedModel: modelStore.model(for: descriptor)
        )
        return try CloudCommitMessageResponse.decode(from: text).formatted()
    }

    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> RepositoryAIAnswer {
        let text = try await session.chat(
            prompt: Self.repositoryPrompt(for: request),
            savedModel: modelStore.model(for: descriptor)
        )
        return try RepositoryAIAnswerDecoder.decodeProviderText(
            text,
            requiresStructuredResponse: request.requiresStructuredResponse
        )
    }

    func streamRepositoryResponse(
        request: RepositoryAIRequest,
        onTextDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> RepositoryAIAnswer {
        // Structured answers are JSON, which must not be shown while it streams.
        guard !request.requiresStructuredResponse else {
            let answer = try await generateRepositoryResponse(request: request)
            await onTextDelta(answer.text)
            return answer
        }
        let text = try await session.chat(
            prompt: Self.repositoryPrompt(for: request),
            savedModel: modelStore.model(for: descriptor),
            onTextDelta: onTextDelta
        )
        return try RepositoryAIAnswerDecoder.decodeProviderText(text)
    }

    static func repositoryPrompt(for request: RepositoryAIRequest) -> String {
        prompt(
            instructions: RepositoryAIPrompt.instructions(for: request),
            userPrompt: RepositoryAIPrompt.userPrompt(for: request)
        )
    }

    /// Copilot conversations take one user message, so the instructions lead it.
    static func prompt(instructions: String, userPrompt: String) -> String {
        """
        \(instructions)

        \(userPrompt)
        """
    }
}