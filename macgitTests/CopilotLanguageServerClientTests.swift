// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

final class CopilotLanguageServerClientTests: XCTestCase {
    // MARK: Framing

    func testFramerSplitsBatchedAndPartialMessages() throws {
        var framer = CopilotJSONRPCFramer()
        let first = Data(#"{"a":1}"#.utf8)
        let second = Data(#"{"b":"é"}"#.utf8)
        let stream = CopilotJSONRPCFramer.frame(first) + CopilotJSONRPCFramer.frame(second)
        let splitIndex = stream.count - 3

        let early = try framer.append(stream.prefix(splitIndex))
        let late = try framer.append(stream.suffix(from: splitIndex))

        XCTAssertEqual(early, [first])
        XCTAssertEqual(late, [second])
    }

    func testFramerAcceptsLowercaseHeaderAndExtraHeaders() throws {
        var framer = CopilotJSONRPCFramer()
        let body = Data("{}".utf8)
        let raw = Data("content-length: 2\r\nContent-Type: application/vscode-jsonrpc\r\n\r\n".utf8) + body

        XCTAssertEqual(try framer.append(raw), [body])
    }

    func testFramerRejectsMissingLength() {
        var framer = CopilotJSONRPCFramer()

        XCTAssertThrowsError(try framer.append(Data("X-Other: 1\r\n\r\n{}".utf8)))
    }

    // MARK: Session

    func testServerStartsLazilyWithInitializeHandshake() async throws {
        let launcher = FakeCopilotLauncher()
        let client = CopilotLanguageServerClient(launcher: launcher, clientVersion: "9.9")

        let launchesBeforeUse = launcher.launchCount
        _ = try await client.request("checkStatus")
        _ = try await client.request("checkStatus")

        XCTAssertEqual(launchesBeforeUse, 0)
        XCTAssertEqual(launcher.launchCount, 1)
        let methods = launcher.transports[0].receivedMethods
        XCTAssertEqual(Array(methods.prefix(3)), ["initialize", "initialized", "workspace/didChangeConfiguration"])
        XCTAssertEqual(methods.filter { $0 == "checkStatus" }.count, 2)
        let initialize = try XCTUnwrap(launcher.transports[0].received.first)
        XCTAssertEqual(initialize["params"]?["clientInfo"]?["version"], .string("9.9"))
    }

    func testConcurrentCallsWaitForTheHandshakeToFinish() async throws {
        let launcher = FakeCopilotLauncher { method, _ in
            method == "initialize" ? .hold : .result(.object([:]))
        }
        let client = CopilotLanguageServerClient(launcher: launcher)

        let first = Task { try await client.request("checkStatus") }
        try await waitUntil { launcher.launchCount == 1 }
        let transport = launcher.transports[0]
        try await transport.waitForHeld(count: 1)
        let second = Task { try await client.request("copilot/models") }
        await client.setTelemetryEnabled(false)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(transport.receivedMethods, ["initialize"])
        transport.reply(to: "initialize", with: .object([:]))
        _ = try await (first.value, second.value)

        let methods = transport.receivedMethods
        XCTAssertEqual(Array(methods.prefix(3)), ["initialize", "initialized", "workspace/didChangeConfiguration"])
        XCTAssertEqual(methods.filter { $0 == "workspace/didChangeConfiguration" }.count, 1)
        let configuration = try XCTUnwrap(transport.received.first { $0["method"]?.stringValue == "workspace/didChangeConfiguration" })
        XCTAssertEqual(configuration["params"]?["settings"]?["telemetry"]?["telemetryLevel"], .string("off"))
    }

    func testTelemetryChangeAfterStartupIsSent() async throws {
        let launcher = FakeCopilotLauncher()
        let client = CopilotLanguageServerClient(launcher: launcher)
        _ = try await client.request("checkStatus")

        await client.setTelemetryEnabled(false)

        let configurations = launcher.transports[0].received.filter {
            $0["method"]?.stringValue == "workspace/didChangeConfiguration"
        }
        XCTAssertEqual(configurations.count, 2)
        XCTAssertEqual(configurations.last?["params"]?["settings"]?["telemetry"]?["telemetryLevel"], .string("off"))
    }

    func testResponsesAreMatchedToRequestsOutOfOrder() async throws {
        let launcher = FakeCopilotLauncher { method, _ in
            method == "slow" || method == "fast" ? .hold : .result(.object([:]))
        }
        let client = CopilotLanguageServerClient(launcher: launcher)
        _ = try await client.request("warmUp")
        let transport = launcher.transports[0]

        async let slow = client.request("slow")
        async let fast = client.request("fast")
        try await transport.waitForHeld(count: 2)
        transport.reply(to: "fast", with: .string("fast-result"))
        transport.reply(to: "slow", with: .string("slow-result"))

        let results = try await (slow, fast)
        XCTAssertEqual(results.0, .string("slow-result"))
        XCTAssertEqual(results.1, .string("fast-result"))
    }

    func testErrorResponseBecomesResponseError() async throws {
        let launcher = FakeCopilotLauncher { method, _ in
            method == "copilot/models"
                ? .error(code: 1000, message: "Not authenticated: NotSignedIn")
                : .result(.object([:]))
        }
        let client = CopilotLanguageServerClient(launcher: launcher)

        do {
            _ = try await client.request("copilot/models")
            XCTFail("Expected a response error.")
        } catch let error as CopilotLanguageServerError {
            XCTAssertEqual(error, .responseError(code: 1000, message: "Not authenticated: NotSignedIn"))
        }
    }

    func testProgressNotificationsReachTheRequestUntilItCompletes() async throws {
        let launcher = FakeCopilotLauncher { method, params in
            guard method == "conversation/create", let token = params["workDoneToken"]?.stringValue else {
                return .result(.object([:]))
            }
            return .progressThenResult(
                token: token,
                values: [.object(["kind": .string("report"), "reply": .string("po")]),
                         .object(["kind": .string("report"), "reply": .string("ng")])],
                result: .object(["turnId": .string("t1")])
            )
        }
        let client = CopilotLanguageServerClient(launcher: launcher)
        let collected = ProgressCollector()

        let result = try await client.request(
            "conversation/create",
            params: .object(["workDoneToken": .string("token-1")]),
            progressToken: "token-1"
        ) { value in collected.append(value["reply"]?.stringValue ?? "") }

        XCTAssertEqual(result["turnId"], .string("t1"))
        XCTAssertEqual(collected.text, "pong")
    }

    func testServerRequestsAreAnswered() async throws {
        let launcher = FakeCopilotLauncher()
        let client = CopilotLanguageServerClient(launcher: launcher)
        _ = try await client.request("checkStatus")
        let transport = launcher.transports[0]

        transport.sendServerRequest(id: 77, method: "workspace/configuration", params: .object([
            "items": .array([.object(["section": .string("a")]), .object(["section": .string("b")])])
        ]))
        let response = try await transport.waitForResponse(id: 77)

        XCTAssertEqual(response["result"], .array([.object([:]), .object([:])]))
    }

    func testOtherNotificationsReachTheHandler() async throws {
        let launcher = FakeCopilotLauncher()
        let client = CopilotLanguageServerClient(launcher: launcher)
        let received = ProgressCollector()
        await client.setNotificationHandler { method, _ in received.append(method) }
        _ = try await client.request("checkStatus")

        launcher.transports[0].sendNotification("copilot/quotaChange", params: .object([:]))
        try await waitUntil { received.text == "copilot/quotaChange" }
    }

    func testCancelledRequestSendsCancelRequest() async throws {
        let launcher = FakeCopilotLauncher { method, _ in
            method == "workspace/executeCommand" ? .hold : .result(.object([:]))
        }
        let client = CopilotLanguageServerClient(launcher: launcher)
        _ = try await client.request("checkStatus")
        let transport = launcher.transports[0]

        let task = Task { try await client.request("workspace/executeCommand") }
        try await transport.waitForHeld(count: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {}
        try await waitUntil { transport.receivedMethods.contains("$/cancelRequest") }
    }

    // MARK: Restart

    func testServerRestartsOnceAfterUnexpectedExit() async throws {
        let launcher = FakeCopilotLauncher { method, _ in
            method == "hang" ? .hold : .result(.object([:]))
        }
        let client = CopilotLanguageServerClient(launcher: launcher)
        _ = try await client.request("checkStatus")

        let pending = Task { try await client.request("hang") }
        try await launcher.transports[0].waitForHeld(count: 1)
        launcher.transports[0].exitUnexpectedly()
        do {
            _ = try await pending.value
            XCTFail("Expected the pending request to fail.")
        } catch let error as CopilotLanguageServerError {
            XCTAssertEqual(error, .serverExited)
        }

        _ = try await client.request("checkStatus")
        XCTAssertEqual(launcher.launchCount, 2)
    }

    func testServerIsNotRestartedAgainAfterSecondExitWithoutSuccess() async throws {
        let launcher = FakeCopilotLauncher { method, _ in
            method == "hang" ? .hold : .result(.object([:]))
        }
        let client = CopilotLanguageServerClient(launcher: launcher)
        _ = try await client.request("checkStatus")

        launcher.transports[0].exitUnexpectedly()
        try await waitUntil { await !client.isRunning }
        let retry = Task { try await client.request("hang") }
        try await waitUntil { launcher.launchCount == 2 }
        try await launcher.transports[1].waitForHeld(count: 1)
        launcher.transports[1].exitUnexpectedly()
        _ = try? await retry.value

        do {
            _ = try await client.request("checkStatus")
            XCTFail("Expected the server to stay stopped.")
        } catch let error as CopilotLanguageServerError {
            guard case .serverUnavailable = error else { return XCTFail("Unexpected \(error)") }
        }
        XCTAssertEqual(launcher.launchCount, 2)

        await client.resetAfterFailure()
        _ = try await client.request("checkStatus")
        XCTAssertEqual(launcher.launchCount, 3)
    }

    func testTerminateStopsTheProcessAndFailsPendingRequests() async throws {
        let launcher = FakeCopilotLauncher { method, _ in
            method == "hang" ? .hold : .result(.object([:]))
        }
        let client = CopilotLanguageServerClient(launcher: launcher)
        _ = try await client.request("checkStatus")

        let pending = Task { try await client.request("hang") }
        try await launcher.transports[0].waitForHeld(count: 1)
        await client.terminate()

        do {
            _ = try await pending.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {}
        XCTAssertTrue(launcher.transports[0].wasTerminated)
        let running = await client.isRunning
        XCTAssertFalse(running)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                return XCTFail("Timed out waiting for condition.")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

// MARK: - Fakes

private nonisolated enum FakeReply: Sendable {
    case result(CopilotJSON)
    case error(code: Int, message: String)
    case progressThenResult(token: String, values: [CopilotJSON], result: CopilotJSON)
    case hold
}

private nonisolated final class FakeCopilotLauncher: CopilotLanguageServerLaunching, @unchecked Sendable {
    typealias Responder = @Sendable (String, CopilotJSON) -> FakeReply

    private let lock = NSLock()
    private let responder: Responder
    private var launched: [FakeCopilotTransport] = []

    init(responder: @escaping Responder = { _, _ in .result(.object([:])) }) {
        self.responder = responder
    }

    var launchCount: Int { lock.withLock { launched.count } }
    var transports: [FakeCopilotTransport] { lock.withLock { launched } }

    func launch() async throws -> any CopilotLanguageServerTransport {
        let transport = FakeCopilotTransport(responder: responder)
        lock.withLock { launched.append(transport) }
        return transport
    }
}

private nonisolated final class FakeCopilotTransport: CopilotLanguageServerTransport, @unchecked Sendable {
    let output: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let responder: FakeCopilotLauncher.Responder
    private let lock = NSLock()
    private var messages: [CopilotJSON] = []
    private var held: [String: CopilotJSON] = [:]
    private var terminated = false

    init(responder: @escaping FakeCopilotLauncher.Responder) {
        self.responder = responder
        (output, continuation) = AsyncStream<Data>.makeStream()
    }

    var received: [CopilotJSON] { lock.withLock { messages } }
    var receivedMethods: [String] { received.compactMap { $0["method"]?.stringValue } }
    var wasTerminated: Bool { lock.withLock { terminated } }

    func write(_ data: Data) throws {
        var framer = CopilotJSONRPCFramer()
        for body in try framer.append(data) {
            let message = try JSONDecoder().decode(CopilotJSON.self, from: body)
            lock.withLock { messages.append(message) }
            guard let id = message["id"], let method = message["method"]?.stringValue else { continue }
            switch responder(method, message["params"] ?? .null) {
            case .result(let result):
                push(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
            case .error(let code, let text):
                push(.object(["jsonrpc": .string("2.0"), "id": id, "error": .object([
                    "code": .number(Double(code)), "message": .string(text)
                ])]))
            case .progressThenResult(let token, let values, let result):
                for value in values {
                    sendNotification("$/progress", params: .object(["token": .string(token), "value": value]))
                }
                push(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
            case .hold:
                lock.withLock { held[method] = id }
            }
        }
    }

    func terminate() {
        lock.withLock { terminated = true }
        continuation.finish()
    }

    func exitUnexpectedly() {
        continuation.finish()
    }

    func reply(to method: String, with result: CopilotJSON) {
        guard let id = lock.withLock({ held.removeValue(forKey: method) }) else { return }
        push(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
    }

    func sendNotification(_ method: String, params: CopilotJSON) {
        push(.object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params]))
    }

    func sendServerRequest(id: Int, method: String, params: CopilotJSON) {
        push(.object(["jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method), "params": params]))
    }

    func waitForHeld(count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while lock.withLock({ held.count }) < count {
            guard ContinuousClock.now < deadline else { throw CopilotLanguageServerError.invalidResponse }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func waitForResponse(id: Int) async throws -> CopilotJSON {
        let deadline = ContinuousClock.now + .seconds(2)
        while true {
            if let response = received.first(where: { $0["id"] == .number(Double(id)) && $0["method"] == nil }) {
                return response
            }
            guard ContinuousClock.now < deadline else { throw CopilotLanguageServerError.invalidResponse }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func push(_ message: CopilotJSON) {
        guard let body = try? JSONEncoder().encode(message) else { return }
        continuation.yield(CopilotJSONRPCFramer.frame(body))
    }
}

private nonisolated final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var parts: [String] = []

    func append(_ part: String) {
        lock.withLock { parts.append(part) }
    }

    var text: String { lock.withLock { parts.joined() } }
}
