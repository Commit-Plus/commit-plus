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

actor CommitPlusAIClient: CommitPlusAIRequestSending {
    private let tokens: any CommitPlusAITokenProviding
    private let baseURL: URL?
    private let session: URLSession
    private let onAllowance: @MainActor @Sendable (CommitPlusAIAllowance, CommitPlusAISession) -> Void

    init(baseURL: URL?, tokens: any CommitPlusAITokenProviding, session: URLSession = .shared,
         onAllowance: @escaping @MainActor @Sendable (CommitPlusAIAllowance, CommitPlusAISession) -> Void = { _, _ in }) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session
        self.onAllowance = onAllowance
    }
    nonisolated static func configuredURL(bundle: Bundle = .main) -> URL? {
        guard let value = bundle.object(forInfoDictionaryKey: "CommitPlusAIBaseURL") as? String else { return nil }
        return validatedURL(value)
    }
    nonisolated static func validatedURL(_ value: String, allowLocalhost: Bool = false) -> URL? {
        guard let url = URL(string: value), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (allowLocalhost && url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)) else { return nil }
        return url
    }
    func allowance() async throws -> CommitPlusAIAllowance {
        guard let identity = await tokens.currentSession() else { throw CommitPlusAIError.signedOut }
        let data = try await get(path: "v1/allowance", identity: identity)
        let allowance = try JSONDecoder().decode(CommitPlusAIAllowance.self, from: data)
        try await check(identity)
        return allowance
    }
    func send(operation: CommitPlusAIOperation, messages: [CommitPlusAIWireMessage], toolsData: Data = Data("[]".utf8),
               structured: Bool, onTextDelta: (@Sendable (String) async -> Void)? = nil) async throws -> CommitPlusAIResult {
        guard let baseURL else { throw CommitPlusAIError.unavailable }
        guard let identity = await tokens.currentSession() else { throw CommitPlusAIError.signedOut }
        let id = UUID().uuidString.lowercased()
        let encodedMessages = try JSONSerialization.jsonObject(with: JSONEncoder().encode(messages))
        let tools = try JSONSerialization.jsonObject(with: toolsData)
        let body = try JSONSerialization.data(withJSONObject: ["version": 1, "requestID": id, "operation": operation.rawValue,
            "responseFormat": structured ? "json_object" : "text", "messages": encodedMessages, "tools": tools, "stream": onTextDelta != nil])
        guard body.count <= 262144 else { throw CommitPlusAIError.server(code: "payload_too_large") }
        var request = URLRequest(url: baseURL.appending(path: "v1/inference"))
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for attempt in 0...1 {
            request.setValue("Bearer \(try await tokens.token(for: identity, forceRefresh: attempt == 1))", forHTTPHeaderField: "Authorization")
            try await check(identity)
            do {
                let (bytes, response) = try await session.bytes(for: request)
                defer { bytes.task.cancel() }
                return try await withTaskCancellationHandler {
                    guard let http = response as? HTTPURLResponse else { throw CommitPlusAIError.invalidResponse }
                    if http.statusCode == 401 && attempt == 0 { throw RetryToken.refresh }
                    if !(200..<300).contains(http.statusCode) {
                        var data = Data()
                        for try await byte in bytes { guard data.count < 262144 else { throw CommitPlusAIError.invalidResponse }; data.append(byte) }
                        try await check(identity)
                        throw Self.serverError(data)
                    }
                    var result: CommitPlusAIResult?
                    if onTextDelta != nil {
                        var decoder = CommitPlusAIEventDecoder()
                        var accumulator = CommitPlusAIStreamAccumulator()
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            guard let event = try decoder.append(byte) else { continue }
                            try await check(identity)
                            if ["text_delta", "tool_call_delta"].contains(event.name) {
                                if let delta = try accumulator.append(event) { await onTextDelta?(delta) }
                            } else if ["completed", "accounting_pending"].contains(event.name) {
                                result = try JSONDecoder().decode(CommitPlusAIResult.self, from: event.data)
                                if let result { try accumulator.validate(result) }
                                guard (event.name == "completed") == (result?.settlement == "settled") else { throw CommitPlusAIError.invalidResponse }
                                break
                            } else if event.name == "error" {
                                throw CommitPlusAIError.server(code: try JSONDecoder().decode(ErrorBody.self, from: event.data).code)
                            } else { throw CommitPlusAIError.invalidResponse }
                        }
                    } else {
                        var data = Data()
                        for try await byte in bytes { try Task.checkCancellation(); guard data.count < 2097152 else { throw CommitPlusAIError.invalidResponse }; data.append(byte) }
                        result = try JSONDecoder().decode(CommitPlusAIResult.self, from: data)
                    }
                    guard let result else { throw CommitPlusAIError.invalidResponse }
                    try result.validate(requestID: id)
                    try await check(identity)
                    await onAllowance(result.allowance, identity)
                    return result
                } onCancel: { bytes.task.cancel() }
            } catch RetryToken.refresh { continue }
            catch {
                try await check(identity)
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if case CommitPlusAIError.server = error { throw error }
                // Query only. Never issue a second inference for an ambiguous transport outcome.
                if let statusData = try? await get(path: "v1/requests/\(id)", identity: identity),
                   let status = try? JSONDecoder().decode(RequestStatus.self, from: statusData),
                   status.requestID.lowercased() == id,
                   ["reserved", "invoking", "settled", "released", "reconciling"].contains(status.state) {
                    try await check(identity)
                    await onAllowance(status.allowance, identity)
                    if status.state == "settled" { throw CommitPlusAIError.outputLost }
                    if status.state == "released" { throw CommitPlusAIError.unavailable }
                    throw CommitPlusAIError.server(code: "accounting_pending")
                }
                throw CommitPlusAIError.outcomeUnknown
            }
        }
        throw CommitPlusAIError.signedOut
    }
    private func get(path: String, identity: CommitPlusAISession) async throws -> Data {
        guard let baseURL else { throw CommitPlusAIError.unavailable }
        for attempt in 0...1 {
            var request = URLRequest(url: baseURL.appending(path: path))
            request.timeoutInterval = 30
            request.setValue("Bearer \(try await tokens.token(for: identity, forceRefresh: attempt == 1))", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            try await check(identity)
            guard let response = response as? HTTPURLResponse, data.count <= 2097152 else { throw CommitPlusAIError.invalidResponse }
            if response.statusCode == 401 && attempt == 0 { continue }
            guard (200..<300).contains(response.statusCode) else { throw Self.serverError(data) }
            return data
        }
        throw CommitPlusAIError.signedOut
    }
    private func check(_ identity: CommitPlusAISession) async throws {
        try Task.checkCancellation()
        guard await tokens.currentSession() == identity else { throw CommitPlusAIError.sessionChanged }
    }
    private static func serverError(_ data: Data) -> CommitPlusAIError {
        (try? JSONDecoder().decode(ErrorEnvelope.self, from: data)).map { .server(code: $0.error.code) } ?? .invalidResponse
    }
    private enum RetryToken: Error { case refresh }
    private struct ErrorBody: Decodable { let code: String }
    private struct ErrorEnvelope: Decodable { let error: ErrorBody }
    private struct TextDelta: Decodable { let text: String }
    private struct RequestStatus: Decodable { let requestID: String; let state: String; let allowance: CommitPlusAIAllowance }
}
