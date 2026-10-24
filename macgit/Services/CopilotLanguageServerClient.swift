// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Foundation
import os

/// A JSON value exchanged with the Copilot language server.
nonisolated enum CopilotJSON: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([CopilotJSON])
    case object([String: CopilotJSON])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([CopilotJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: CopilotJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> CopilotJSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [CopilotJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

nonisolated enum CopilotLanguageServerError: LocalizedError, Equatable {
    case serverExited
    case serverUnavailable(String)
    case responseError(code: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .serverExited:
            return "The GitHub Copilot language server stopped unexpectedly. Try again."
        case .serverUnavailable(let message):
            return message
        case .responseError(_, let message):
            return message
        case .invalidResponse:
            return "The GitHub Copilot language server returned an unexpected response."
        }
    }
}

/// Splits the server's stdout into `Content-Length` framed messages.
nonisolated struct CopilotJSONRPCFramer: Sendable {
    private var buffer = Data()
    private static let separator = Data("\r\n\r\n".utf8)

    static func frame(_ body: Data) -> Data {
        Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
    }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var messages: [Data] = []
        while let headerEnd = buffer.range(of: Self.separator) {
            let header = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
            guard let length = header
                .components(separatedBy: "\r\n")
                .first(where: { $0.lowercased().hasPrefix("content-length:") })
                .flatMap({ Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) })
            else {
                throw CopilotLanguageServerError.invalidResponse
            }
            guard buffer.distance(from: headerEnd.upperBound, to: buffer.endIndex) >= length else { break }
            let bodyEnd = buffer.index(headerEnd.upperBound, offsetBy: length)
            messages.append(Data(buffer[headerEnd.upperBound..<bodyEnd]))
            buffer = Data(buffer[bodyEnd...])
        }
        return messages
    }
}

/// A running server process seen as a byte stream.
nonisolated protocol CopilotLanguageServerTransport: AnyObject, Sendable {
    /// Raw stdout bytes. The stream finishes when the process exits.
    var output: AsyncStream<Data> { get }
    func write(_ data: Data) throws
    /// Safe to call from any thread, including while the app terminates.
    func terminate()
}

nonisolated protocol CopilotLanguageServerLaunching: Sendable {
    func launch() async throws -> any CopilotLanguageServerTransport
}

/// Owns the Copilot language server process and its JSON-RPC session. The server
/// starts on first use and restarts once after an unexpected exit.
actor CopilotLanguageServerClient {
    typealias NotificationHandler = @Sendable (_ method: String, _ params: CopilotJSON) -> Void
    typealias ProgressHandler = @Sendable (CopilotJSON) -> Void

    static let shared = CopilotLanguageServerClient(launcher: ProcessCopilotLanguageServerLauncher())

    private let launcher: any CopilotLanguageServerLaunching
    private let clientVersion: String
    private var transport: (any CopilotLanguageServerTransport)?
    private var startTask: Task<any CopilotLanguageServerTransport, Error>?
    /// Set in the same actor turn that sends the startup configuration.
    private var handshakeComplete = false
    private var readerTask: Task<Void, Never>?
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<CopilotJSON, Error>] = [:]
    private var progressHandlers: [String: ProgressHandler] = [:]
    private var notificationHandler: NotificationHandler?
    private var restartsRemaining = 1
    private var telemetryEnabled = true
    /// Lets app termination stop the process without waiting on the actor.
    private nonisolated let liveTransport = OSAllocatedUnfairLock<(any CopilotLanguageServerTransport)?>(initialState: nil)

    init(launcher: any CopilotLanguageServerLaunching, clientVersion: String = Bundle.main.shortVersionString) {
        self.launcher = launcher
        self.clientVersion = clientVersion
    }

    /// Stops the server when the app quits. Call once for a long-lived client.
    nonisolated func terminateOnAppQuit() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [liveTransport] _ in
            liveTransport.withLock { $0?.terminate() }
        }
    }

    func setNotificationHandler(_ handler: NotificationHandler?) {
        notificationHandler = handler
    }

    func setTelemetryEnabled(_ enabled: Bool) {
        telemetryEnabled = enabled
        // Until the handshake completes, `start()` sends the current setting itself.
        guard handshakeComplete, let transport else { return }
        try? send(Self.configurationNotification(telemetryEnabled: enabled), over: transport)
    }

    /// Clears a failure so the next request may start the server again.
    func resetAfterFailure() {
        restartsRemaining = 1
    }

    var isRunning: Bool {
        transport != nil
    }

    /// Sends a request and waits for its result. `progressToken` routes the
    /// matching `$/progress` notifications to `onProgress` until the result arrives.
    func request(
        _ method: String,
        params: CopilotJSON = .object([:]),
        progressToken: String? = nil,
        onProgress: ProgressHandler? = nil
    ) async throws -> CopilotJSON {
        let transport = try await startIfNeeded()
        let result = try await send(method, params: params, over: transport, progressToken: progressToken, onProgress: onProgress)
        restartsRemaining = 1
        return result
    }

    func terminate() {
        stop(error: CancellationError())
    }

    // MARK: - Lifecycle

    private func startIfNeeded() async throws -> any CopilotLanguageServerTransport {
        if let startTask { return try await startTask.value }
        if let transport { return transport }
        guard restartsRemaining >= 0 else {
            throw CopilotLanguageServerError.serverUnavailable(
                "The GitHub Copilot language server keeps stopping. Try again."
            )
        }
        let task = Task { try await start() }
        startTask = task
        defer { startTask = nil }
        return try await task.value
    }

    private func start() async throws -> any CopilotLanguageServerTransport {
        let transport = try await launcher.launch()
        self.transport = transport
        liveTransport.withLock { $0 = transport }
        readerTask = Task { [weak self] in
            var framer = CopilotJSONRPCFramer()
            for await chunk in transport.output {
                guard let messages = try? framer.append(chunk) else { break }
                for message in messages {
                    await self?.handle(message, from: transport)
                }
            }
            await self?.transportDidExit(transport)
        }
        do {
            _ = try await send("initialize", params: initializeParams, over: transport)
            try send(.object(["jsonrpc": .string("2.0"), "method": .string("initialized"), "params": .object([:])]), over: transport)
            try send(Self.configurationNotification(telemetryEnabled: telemetryEnabled), over: transport)
            handshakeComplete = true
        } catch {
            stop(error: error)
            throw error
        }
        return transport
    }

    private func transportDidExit(_ exited: any CopilotLanguageServerTransport) {
        guard let transport, transport === exited else { return }
        stop(error: CopilotLanguageServerError.serverExited)
        if restartsRemaining > 0 {
            restartsRemaining -= 1
        } else {
            restartsRemaining = -1
        }
    }

    private func stop(error: Error) {
        let current = transport
        transport = nil
        handshakeComplete = false
        liveTransport.withLock { $0 = nil }
        readerTask?.cancel()
        readerTask = nil
        progressHandlers = [:]
        let waiting = pending
        pending = [:]
        waiting.values.forEach { $0.resume(throwing: error) }
        current?.terminate()
    }

    private var initializeParams: CopilotJSON {
        let info: CopilotJSON = .object(["name": .string("Commit+"), "version": .string(clientVersion)])
        return .object([
            "processId": .number(Double(ProcessInfo.processInfo.processIdentifier)),
            "capabilities": .object([:]),
            "clientInfo": info,
            "initializationOptions": .object([
                "editorInfo": info,
                "editorPluginInfo": .object(["name": .string("commit-plus-copilot"), "version": .string(clientVersion)])
            ]),
            "workspaceFolders": .null
        ])
    }

    private static func configurationNotification(telemetryEnabled: Bool) -> CopilotJSON {
        .object([
            "jsonrpc": .string("2.0"),
            "method": .string("workspace/didChangeConfiguration"),
            "params": .object(["settings": .object([
                "telemetry": .object(["telemetryLevel": .string(telemetryEnabled ? "all" : "off")])
            ])])
        ])
    }

    // MARK: - Messages

    private func send(
        _ method: String,
        params: CopilotJSON,
        over transport: any CopilotLanguageServerTransport,
        progressToken: String? = nil,
        onProgress: ProgressHandler? = nil
    ) async throws -> CopilotJSON {
        nextID += 1
        let id = nextID
        if let progressToken, let onProgress {
            progressHandlers[progressToken] = onProgress
        }
        defer {
            if let progressToken { progressHandlers[progressToken] = nil }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                do {
                    try send(.object([
                        "jsonrpc": .string("2.0"),
                        "id": .number(Double(id)),
                        "method": .string(method),
                        "params": params
                    ]), over: transport)
                } catch {
                    pending[id] = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    private func cancel(id: Int) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
        if let transport {
            try? send(.object([
                "jsonrpc": .string("2.0"),
                "method": .string("$/cancelRequest"),
                "params": .object(["id": .number(Double(id))])
            ]), over: transport)
        }
    }

    private func send(_ message: CopilotJSON, over transport: any CopilotLanguageServerTransport) throws {
        try transport.write(CopilotJSONRPCFramer.frame(try JSONEncoder().encode(message)))
    }

    private func handle(_ data: Data, from source: any CopilotLanguageServerTransport) {
        guard let transport, transport === source,
              let message = try? JSONDecoder().decode(CopilotJSON.self, from: data) else { return }
        let method = message["method"]?.stringValue
        let params = message["params"] ?? .null

        switch (message["id"], method) {
        case (let id?, let method?):
            respond(to: id, method: method, params: params, over: transport)
        case (let id?, nil):
            guard let number = id.numberValue,
                  let continuation = pending.removeValue(forKey: Int(number)) else { return }
            if let error = message["error"] {
                continuation.resume(throwing: CopilotLanguageServerError.responseError(
                    code: Int(error["code"]?.numberValue ?? 0),
                    message: error["message"]?.stringValue ?? "The GitHub Copilot request failed."
                ))
            } else {
                continuation.resume(returning: message["result"] ?? .null)
            }
        case (nil, "$/progress"?):
            if let token = params["token"]?.stringValue, let handler = progressHandlers[token] {
                handler(params["value"] ?? .null)
            }
        case (nil, let method?):
            notificationHandler?(method, params)
        case (nil, nil):
            break
        }
    }

    /// Answers server-to-client requests. Commit+ has no workspace, so configuration
    /// requests get empty settings and everything else gets a null result.
    private func respond(to id: CopilotJSON, method: String, params: CopilotJSON, over transport: any CopilotLanguageServerTransport) {
        let result: CopilotJSON
        if method == "workspace/configuration" {
            let count = params["items"]?.arrayValue?.count ?? 0
            result = .array(Array(repeating: .object([:]), count: count))
        } else {
            result = .null
        }
        try? send(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]), over: transport)
    }
}

private extension Bundle {
    nonisolated var shortVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}

/// Launches the pinned server with its sign-in state isolated under Application Support.
nonisolated struct ProcessCopilotLanguageServerLauncher: CopilotLanguageServerLaunching {
    var runtime: CopilotLanguageServerRuntime = .shared
    var configHomeDirectory: URL = CopilotLanguageServerRuntime.configHomeDirectory

    func launch() async throws -> any CopilotLanguageServerTransport {
        let executableURL = try await runtime.executableURL()
        try FileManager.default.createDirectory(
            at: configHomeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return try ProcessCopilotLanguageServerTransport(
            executableURL: executableURL,
            environment: [
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "XDG_CONFIG_HOME": configHomeDirectory.path
            ]
        )
    }
}

nonisolated final class ProcessCopilotLanguageServerTransport: CopilotLanguageServerTransport, @unchecked Sendable {
    let output: AsyncStream<Data>
    private let process = Process()
    private let input = Pipe()
    private let writeLock = NSLock()

    init(executableURL: URL, environment: [String: String]) throws {
        let stdout = Pipe()
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        output = stream

        process.executableURL = executableURL
        process.arguments = ["--stdio"]
        process.environment = environment
        process.standardInput = input
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        // A write after the server exits must fail with EPIPE instead of killing the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        process.terminationHandler = { _ in continuation.finish() }

        do {
            try process.run()
        } catch {
            throw CopilotLanguageServerError.serverUnavailable(
                "The GitHub Copilot language server could not start: \(error.localizedDescription)"
            )
        }
    }

    func write(_ data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard process.isRunning else { throw CopilotLanguageServerError.serverExited }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
