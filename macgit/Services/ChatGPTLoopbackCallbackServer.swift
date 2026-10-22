// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network

/// A one-shot HTTP listener on 127.0.0.1 that receives the "Sign in with ChatGPT"
/// redirect. OpenAI accepts only loopback redirect URIs for this flow.
final class ChatGPTLoopbackCallbackServer: @unchecked Sendable {
    let redirectURI: URL
    let callbacks: AsyncStream<URL>

    private let listener: NWListener
    private let path: String
    private let continuation: AsyncStream<URL>.Continuation
    private let queue: DispatchQueue

    private init(listener: NWListener, port: UInt16, path: String, queue: DispatchQueue) {
        self.listener = listener
        self.path = path
        self.queue = queue
        redirectURI = URL(string: "http://127.0.0.1:\(port)\(path)")!
        (callbacks, continuation) = AsyncStream.makeStream(of: URL.self)
    }

    /// Starts listening on the preferred port, or any free port when it is taken.
    static func start(
        preferredPort: UInt16 = ChatGPTAuthConfiguration.live.preferredLoopbackPort,
        path: String = ChatGPTAuthConfiguration.live.callbackPath
    ) async throws -> ChatGPTLoopbackCallbackServer {
        do {
            return try await start(port: preferredPort, path: path)
        } catch {
            return try await start(port: 0, path: path)
        }
    }

    private static func start(port: UInt16, path: String) async throws -> ChatGPTLoopbackCallbackServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "com.commitplus.macgit.chatgpt-loopback")
        let boundPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = LockedFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumed.setOnce() else { return }
                    continuation.resume(returning: listener.port?.rawValue ?? port)
                case .failed(let error), .waiting(let error):
                    // `.waiting` means the port is unavailable; fall back instead of hanging.
                    guard resumed.setOnce() else { return }
                    listener.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard resumed.setOnce() else { return }
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.newConnectionHandler = { $0.cancel() }
            listener.start(queue: queue)
        }
        let server = ChatGPTLoopbackCallbackServer(listener: listener, port: boundPort, path: path, queue: queue)
        listener.newConnectionHandler = { [weak server] connection in
            guard let server else { return connection.cancel() }
            server.handle(connection)
        }
        listener.stateUpdateHandler = { [weak server] state in
            if case .failed = state { server?.stop() }
        }
        return server
    }

    func stop() {
        listener.cancel()
        continuation.finish()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data,
                  let request = String(data: data, encoding: .utf8),
                  let requestLine = request.split(separator: "\r\n", maxSplits: 1).first else {
                connection.cancel()
                return
            }
            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2, parts[0] == "GET",
                  let url = URL(string: "http://127.0.0.1:\(redirectURI.port ?? 0)\(parts[1])"),
                  url.path == path else {
                respond(on: connection, status: "404 Not Found", body: "Not found.")
                return
            }
            continuation.yield(url)
            respond(
                on: connection,
                status: "200 OK",
                body: "<!doctype html><meta charset=utf-8><title>Commit+</title><body style=\"font: 15px -apple-system; padding: 40px\">You can close this tab and return to Commit+.</body>"
            )
        }
    }

    private func respond(on connection: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + bodyData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    func setOnce() -> Bool {
        lock.withLock {
            guard !isSet else { return false }
            isSet = true
            return true
        }
    }
}
