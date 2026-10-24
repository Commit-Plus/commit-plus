// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class GitHubCopilotProviderTests: XCTestCase {
    // MARK: Prompt routing

    func testCommitMessageUsesOneTurnWithCommitPromptAndDefaultModel() async throws {
        let server = FakeCopilotServer(replyDeltas: [#"{"type":"feat","#, #""subject":"Add Copilot provider","body":""}"#])
        let provider = makeProvider(server: server)

        let generated = try await provider.generateCommitMessage(request: makeCommitRequest())

        XCTAssertEqual(generated.subject, "feat: Add Copilot provider")
        let create = try await server.lastRequest("conversation/create")
        let prompt = try XCTUnwrap(create["turns"]?.arrayValue?.first?["request"]?.stringValue)
        XCTAssertTrue(prompt.hasPrefix(CloudCommitMessagePrompt.jsonInstructions))
        XCTAssertTrue(prompt.contains("+save API key"))
        XCTAssertEqual(create["turns"]?.arrayValue?.count, 1)
        XCTAssertEqual(create["chatMode"], .string("Ask"))
        XCTAssertEqual(create["modelInfo"]?["id"], .string("auto"))
    }

    func testRepositoryChatStreamsDeltasInOrder() async throws {
        let server = FakeCopilotServer(replyDeltas: ["The change ", "", "adds a provider."])
        let provider = makeProvider(server: server)
        let received = DeltaRecorder()

        let answer = try await provider.streamRepositoryResponse(request: makeRepositoryRequest()) { delta in
            await received.append(delta)
        }

        XCTAssertEqual(answer.text, "The change adds a provider.")
        let deltas = await received.deltas
        XCTAssertEqual(deltas, ["The change ", "adds a provider."])
        let create = try await server.lastRequest("conversation/create")
        let prompt = try XCTUnwrap(create["turns"]?.arrayValue?.first?["request"]?.stringValue)
        XCTAssertTrue(prompt.contains("Review the current changes"))
    }

    func testConflictResolutionUsesRepositoryPrompt() async throws {
        let reply = #"{"decisions":[{"sectionIndex":0,"action":"incoming","replacementText":"","reason":"Newer call","question":"","options":[]}],"summary":"Took incoming."}"#
        let server = FakeCopilotServer(replyDeltas: [reply])
        let provider = makeProvider(server: server)

        let response = try await provider.generateConflictResolution(request: makeConflictRequest())

        XCTAssertEqual(response.decisions.first?.action, .incoming)
        let methods = await server.methods
        XCTAssertEqual(methods.filter { $0 == "conversation/create" }.count, 1)
    }

    func testCopilotDoesNotSupportRepositoryAgent() {
        let provider = makeProvider(server: FakeCopilotServer())

        XCTAssertFalse(provider.supportsRepositoryAgent)
        XCTAssertFalse(provider.descriptor.requiresProToConfigureAPIKey)
        XCTAssertEqual(provider.descriptor.billing, .connectedAccount)
    }

    // MARK: Models

    func testModelListOffersOnlyChatModelsWithAccountDefaultFirst() async throws {
        let server = FakeCopilotServer(models: [
            Self.model("gpt-41-copilot", scopes: ["completion"]),
            Self.model("claude-x", scopes: ["chat-panel"]),
            Self.model("gpt-5", scopes: ["chat-panel", "edit-panel"], isChatDefault: true),
        ])
        let provider = makeProvider(server: server)

        let models = try await provider.availableModels()

        XCTAssertEqual(models.map(\.id), ["gpt-5", "claude-x"])
    }

    func testSavedModelThatDisappearedFallsBackToAccountDefault() async throws {
        let server = FakeCopilotServer(models: [
            Self.model("claude-x", scopes: ["chat-panel"]),
            Self.model("gpt-5", scopes: ["chat-panel"], isChatDefault: true),
        ])
        let missing = makeProvider(server: server, models: [.githubCopilot: "retired-model"])
        _ = try await missing.generateRepositoryResponse(request: makeRepositoryRequest())
        let fallback = try await server.lastRequest("conversation/create")
        XCTAssertEqual(fallback["modelInfo"]?["id"], .string("gpt-5"))

        let kept = makeProvider(server: server, models: [.githubCopilot: "claude-x"])
        _ = try await kept.generateRepositoryResponse(request: makeRepositoryRequest())
        let saved = try await server.lastRequest("conversation/create")
        XCTAssertEqual(saved["modelInfo"]?["id"], .string("claude-x"))
    }

    func testNoTokenReachesAnyRequestContent() async throws {
        let server = FakeCopilotServer(replyDeltas: ["Done."])
        let provider = makeProvider(server: server)

        _ = try await provider.generateRepositoryResponse(request: makeRepositoryRequest())

        let encoded = String(decoding: try JSONEncoder().encode(await server.requests.map(\.params)), as: UTF8.self)
        for marker in ["gho_", "ghu_", "access_token", "Bearer", "oauth"] {
            XCTAssertFalse(encoded.contains(marker), "Request content contains \(marker)")
        }
    }

    // MARK: Sign-in

    func testDeviceCodeSignInStoresOnlyTheLogin() async throws {
        let defaults = makeDefaults()
        let server = FakeCopilotServer(status: "NotSignedIn")
        let session = GitHubCopilotAccountSession(client: server, defaults: defaults)

        let start = try await session.beginSignIn()
        guard case .deviceCode(let authorization) = start else {
            return XCTFail("Expected a device code, got \(start)")
        }
        XCTAssertEqual(authorization.userCode, "ABCD-1234")
        XCTAssertEqual(authorization.verificationURI.absoluteString, "https://github.com/login/device")
        XCTAssertEqual(authorization.provider, .github)

        await server.setStatus("OK")
        let account = try await session.completeSignIn()

        XCTAssertEqual(account.username, "octocat")
        let execute = try await server.lastRequest("workspace/executeCommand")
        XCTAssertEqual(execute["command"], .string("github.copilot.finishDeviceFlow"))
        XCTAssertEqual(defaults.string(forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey), "octocat")
        let connected = await session.connectedAccount()
        XCTAssertEqual(connected?.username, "octocat")
    }

    func testAccountWithoutCopilotAccessIsSignedOutAndNotStored() async throws {
        let defaults = makeDefaults()
        let server = FakeCopilotServer(status: "NotSignedIn")
        let session = GitHubCopilotAccountSession(client: server, defaults: defaults)
        _ = try await session.beginSignIn()
        await server.setStatus("NotAuthorized")

        do {
            _ = try await session.completeSignIn()
            XCTFail("Expected no-access error")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(error, .copilotNoAccess)
        }

        let methods = await server.methods
        XCTAssertEqual(methods.last, "signOut")
        XCTAssertNil(defaults.string(forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey))
        let connected = await session.connectedAccount()
        XCTAssertNil(connected)
    }

    func testCancelledSignInSignsOutAnApprovedButUnsavedSession() async throws {
        let server = FakeCopilotServer(status: "NotSignedIn")
        let session = GitHubCopilotAccountSession(client: server, defaults: makeDefaults())
        _ = try await session.beginSignIn()
        await server.setStatus("OK")

        await session.cancelSignIn()

        let methods = await server.methods
        XCTAssertEqual(methods.last, "signOut")
        do {
            _ = try await session.completeSignIn()
            XCTFail("Expected no pending sign-in")
        } catch {}
    }

    func testSignOutForgetsLoginAndStopsServer() async throws {
        let defaults = makeDefaults()
        defaults.set("octocat", forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey)
        let server = FakeCopilotServer()
        let session = GitHubCopilotAccountSession(client: server, defaults: defaults)

        await session.signOut()

        let methods = await server.methods
        XCTAssertEqual(methods, ["signOut"])
        let terminated = await server.terminateCount
        XCTAssertEqual(terminated, 1)
        XCTAssertNil(defaults.string(forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey))
    }

    // MARK: Error mapping

    func testFailureCodesMapToCopilotErrors() {
        typealias Session = GitHubCopilotAccountSession
        XCTAssertEqual(Session.failure(code: 1000, message: "Not authenticated: NotSignedIn"), .copilotSignInRequired)
        XCTAssertEqual(Session.failure(code: 402, message: "Payment required"), .copilotQuotaExhausted)
        XCTAssertEqual(Session.failure(code: nil, message: "You have exceeded your monthly chat quota"), .copilotQuotaExhausted)
        XCTAssertEqual(Session.failure(code: 429, message: "Too many requests"), .copilotRateLimited)
        XCTAssertEqual(Session.failure(code: 403, message: "Forbidden"), .copilotNoAccess)
        XCTAssertEqual(Session.failure(code: 500, message: "Boom"), .providerRequestFailed("Boom"))
        XCTAssertEqual(Session.failure(code: nil, message: ""), .providerRequestFailed("GitHub Copilot request failed."))
    }

    func testServerAndRuntimeFailuresBecomeRetryableUnavailability() {
        let runtime = GitHubCopilotAccountSession.mapped(CopilotLanguageServerRuntimeError.downloadFailed("Offline."))
        let exited = GitHubCopilotAccountSession.mapped(CopilotLanguageServerError.serverExited)
        let unavailable = GitHubCopilotAccountSession.mapped(CopilotLanguageServerError.serverUnavailable("It could not start."))

        for error in [runtime, exited, unavailable] {
            guard case .copilotServerUnavailable(let message)? = error as? CommitMessageGenerationError else {
                return XCTFail("Unexpected mapping \(error)")
            }
            XCTAssertTrue(message.hasSuffix("Try again."), message)
        }
    }

    func testQuotaFailureOnTurnMakesProviderUnavailable() async throws {
        let defaults = makeDefaults()
        defaults.set("octocat", forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey)
        let server = FakeCopilotServer(
            replyDeltas: [],
            turnError: .object(["message": .string("Quota exceeded"), "code": .number(402)])
        )
        let session = GitHubCopilotAccountSession(client: server, defaults: defaults)
        let provider = GitHubCopilotProvider(session: session, modelStore: InMemoryAIProviderModelStore())

        do {
            _ = try await provider.generateCommitMessage(request: makeCommitRequest())
            XCTFail("Expected quota error")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(error, .copilotQuotaExhausted)
            XCTAssertTrue(error.localizedDescription.contains("quota is used up"))
        }
        let availability = await provider.availability()
        XCTAssertEqual(availability, .unavailable(CommitMessageGenerationError.copilotQuotaExhausted.localizedDescription))
    }

    func testExhaustedQuotaNotificationMakesProviderUnavailableAndRecordsPlan() async throws {
        let defaults = makeDefaults()
        defaults.set("octocat", forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey)
        let session = GitHubCopilotAccountSession(client: FakeCopilotServer(), defaults: defaults)

        await session.handleNotification("copilot/quotaChange", params: .object([
            "copilotPlan": .string("free"),
            "chat": .object(["percentRemaining": .number(0), "unlimited": .bool(false)]),
        ]))

        let availability = await session.availability()
        XCTAssertFalse(availability.isAvailable)
        let account = await session.connectedAccount()
        XCTAssertEqual(account?.planType, "free")
    }

    func testExpiredSignInReportsSignInRequired() async throws {
        let defaults = makeDefaults()
        defaults.set("octocat", forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey)
        let session = GitHubCopilotAccountSession(client: FakeCopilotServer(status: "NotSignedIn"), defaults: defaults)

        let availability = await session.availability()

        XCTAssertEqual(availability, .unavailable(CommitMessageGenerationError.copilotSignInRequired.localizedDescription))
        let account = await session.connectedAccount()
        XCTAssertEqual(account?.requiresSignIn, true)
    }

    func testUnconnectedProviderDoesNotStartServer() async throws {
        let server = FakeCopilotServer()
        let session = GitHubCopilotAccountSession(client: server, defaults: makeDefaults())

        let availability = await session.availability()

        XCTAssertFalse(availability.isAvailable)
        let methods = await server.methods
        XCTAssertTrue(methods.isEmpty)
    }

    // MARK: Helpers

    static func model(_ id: String, scopes: [String], isChatDefault: Bool = false) -> CopilotJSON {
        .object([
            "id": .string(id),
            "modelName": .string(id.uppercased()),
            "scopes": .array(scopes.map(CopilotJSON.string)),
            "isChatDefault": .bool(isChatDefault),
        ])
    }

    private func makeProvider(
        server: FakeCopilotServer,
        models: [AIProviderID: String] = [:]
    ) -> GitHubCopilotProvider {
        let defaults = makeDefaults()
        defaults.set("octocat", forKey: GitHubCopilotAccountSession.connectedLoginDefaultsKey)
        return GitHubCopilotProvider(
            session: GitHubCopilotAccountSession(client: server, defaults: defaults),
            modelStore: InMemoryAIProviderModelStore(models: models)
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "GitHubCopilotProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeCommitRequest() -> CommitMessageGenerationRequest {
        CommitMessageGenerationRequest(
            repositoryName: "macgit",
            branchName: "codex/github-copilot-provider",
            changeSource: .staged,
            changes: CommitChangeSnapshot(
                fingerprint: "tree-1",
                context: "M\tmacgit/App/AIProviderController.swift\n+save API key",
                isTruncated: false
            ),
            recentCommitSubjects: []
        )
    }

    private func makeRepositoryRequest() -> RepositoryAIRequest {
        RepositoryAIRequest(
            repositoryName: "macgit",
            branchName: "main",
            question: "Review the current changes",
            toolResult: RepositoryAIToolResult(
                toolName: "working_tree_changes",
                title: "Working changes",
                fingerprint: "tree-1",
                content: "M\tmacgit/App/AIProviderController.swift",
                isTruncated: false
            )
        )
    }

    private func makeConflictRequest() -> ConflictAIResolutionRequest {
        ConflictAIResolutionRequest(snapshot: ConflictAIFileSnapshot(
            repositoryName: "macgit",
            branchName: "main",
            filePath: "Example.swift",
            fingerprint: "conflict-1",
            baseContent: "func value() { old() }\n",
            currentContent: "func value() { current() }\n",
            incomingContent: "func value() { incoming() }\n",
            sections: [ConflictAISectionSnapshot(
                sectionIndex: 0,
                contextBefore: "",
                currentText: "current()\n",
                incomingText: "incoming()\n",
                contextAfter: ""
            )],
            isTruncated: false
        ))
    }
}

private actor DeltaRecorder {
    var deltas: [String] = []

    func append(_ delta: String) {
        deltas.append(delta)
    }
}

/// Answers Copilot language server requests with the shapes recorded in the design.
actor FakeCopilotServer: CopilotLanguageServerRequesting {
    struct Request {
        let method: String
        let params: CopilotJSON
    }

    private(set) var requests: [Request] = []
    private(set) var terminateCount = 0
    private(set) var isRunning = false
    private var status: String
    private let models: [CopilotJSON]
    private let replyDeltas: [String]
    private let turnError: CopilotJSON?

    init(
        status: String = "OK",
        models: [CopilotJSON] = [GitHubCopilotProviderTests.model("auto", scopes: ["chat-panel"])],
        replyDeltas: [String] = ["{}"],
        turnError: CopilotJSON? = nil
    ) {
        self.status = status
        self.models = models
        self.replyDeltas = replyDeltas
        self.turnError = turnError
    }

    var methods: [String] {
        requests.map(\.method)
    }

    func setStatus(_ status: String) {
        self.status = status
    }

    func lastRequest(_ method: String) throws -> CopilotJSON {
        try XCTUnwrap(requests.last { $0.method == method }?.params)
    }

    func request(
        _ method: String,
        params: CopilotJSON,
        progressToken: String?,
        onProgress: CopilotLanguageServerClient.ProgressHandler?
    ) async throws -> CopilotJSON {
        isRunning = true
        requests.append(Request(method: method, params: params))
        switch method {
        case "checkStatus":
            return status == "OK" || status == "NotAuthorized"
                ? .object(["status": .string(status), "user": .string("octocat")])
                : .object(["status": .string(status)])
        case "signInInitiate":
            return .object([
                "status": .string("PromptUserDeviceFlow"),
                "userCode": .string("ABCD-1234"),
                "verificationUri": .string("https://github.com/login/device"),
                "expiresIn": .number(899),
                "interval": .number(5),
                "command": .object([
                    "command": .string("github.copilot.finishDeviceFlow"),
                    "title": .string("Sign in"),
                    "arguments": .array([]),
                ]),
            ])
        case "workspace/executeCommand":
            // Approving the device code on GitHub signs the server in.
            if status == "NotSignedIn" { status = "OK" }
            return .object(["status": .string(status), "user": .string("octocat")])
        case "signOut":
            status = "NotSignedIn"
            return .object(["status": .string("NotSignedIn")])
        case "copilot/models":
            return .array(models)
        case "conversation/create":
            onProgress?(.object(["kind": .string("begin")]))
            for delta in replyDeltas {
                onProgress?(.object([
                    "kind": .string("report"),
                    "editAgentRounds": .array([.object(["roundId": .number(1), "reply": .string(delta)])]),
                ]))
            }
            var end: [String: CopilotJSON] = ["kind": .string("end")]
            if let turnError { end["error"] = turnError }
            onProgress?(.object(end))
            return .object(["conversationId": .string("c1"), "turnId": .string("t1")])
        default:
            return .null
        }
    }

    func setNotificationHandler(_ handler: CopilotLanguageServerClient.NotificationHandler?) {}

    func setTelemetryEnabled(_ enabled: Bool) {}

    func resetAfterFailure() {}

    func terminate() {
        terminateCount += 1
        isRunning = false
    }
}