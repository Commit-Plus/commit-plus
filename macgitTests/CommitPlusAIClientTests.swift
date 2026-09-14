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
import XCTest
@testable import macgit

@MainActor
final class CommitPlusAIClientTests: XCTestCase {
    func testDefinitive401RefreshesOnceWithSameRequestID() async throws {
        let fixture = try allowanceObject()
        let recorder = ManagedRequestRecorder()
        let (session, url) = ManagedURLProtocol.makeSession { request in
            let requests = recorder.append(request)
            if requests.count == 1 { return (401, Data(#"{"error":{"code":"unauthenticated"}}"#.utf8)) }
            let body = try Self.body(request)
            return (200, try JSONSerialization.data(withJSONObject: ["requestID": body["requestID"]!, "text": "Done", "toolCalls": [], "allowance": fixture, "settlement": "settled"]))
        }
        defer { session.invalidateAndCancel(); ManagedURLProtocol.remove(url) }
        let tokens = ManagedClientTokens()
        let client = CommitPlusAIClient(baseURL: url, tokens: tokens, session: session)
        let result = try await client.infer(operation: .repositoryResponse, messages: [.init(role: "user", content: "Hi")], structured: false)
        XCTAssertEqual(result.text, "Done")
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(try Self.body(requests[0])["requestID"] as? String, try Self.body(requests[1])["requestID"] as? String)
        XCTAssertEqual(tokens.refreshes, [false, true])
        _ = try await client.infer(operation: .repositoryResponse, messages: [.init(role: "user", content: "Next")], structured: false)
        XCTAssertNotEqual(try Self.body(recorder.requests[1])["requestID"] as? String, try Self.body(recorder.requests[2])["requestID"] as? String)
    }

    func testAccountSwitchRejectsAllowanceBeforeDelivery() async throws {
        let fixture = try JSONSerialization.data(withJSONObject: allowanceObject())
        let (session, url) = ManagedURLProtocol.makeSession { _ in (200, fixture) }
        defer { session.invalidateAndCancel(); ManagedURLProtocol.remove(url) }
        let tokens = ManagedClientTokens()
        tokens.switchAfterFirstRead = true
        let client = CommitPlusAIClient(baseURL: url, tokens: tokens, session: session)
        do {
            _ = try await client.allowance()
            XCTFail("A stale account response must not be delivered")
        } catch { guard case CommitPlusAIError.sessionChanged = error else { return XCTFail("Unexpected error: \(error)") } }
    }

    func testConflictDoesNotResendInference() async throws {
        let recorder = ManagedRequestRecorder()
        let (session, url) = ManagedURLProtocol.makeSession { request in
            _ = recorder.append(request)
            return (409, Data(#"{"error":{"code":"request_in_progress"}}"#.utf8))
        }
        defer { session.invalidateAndCancel(); ManagedURLProtocol.remove(url) }
        let client = CommitPlusAIClient(baseURL: url, tokens: ManagedClientTokens(), session: session)
        do {
            _ = try await client.infer(operation: .repositoryResponse, messages: [.init(role: "user", content: "Hi")], structured: false)
            XCTFail("Expected in-progress error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("reserved")) }
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testAmbiguousResponseQueriesOriginalRequestWithoutSecondPOST() async throws {
        let fixture = try allowanceObject()
        let recorder = ManagedRequestRecorder()
        let (session, url) = ManagedURLProtocol.makeSession { request in
            _ = recorder.append(request)
            if request.httpMethod == "POST" { return (200, Data("incomplete".utf8)) }
            return (200, try JSONSerialization.data(withJSONObject: ["requestID": request.url!.lastPathComponent,
                "state": "settled", "allowance": fixture]))
        }
        defer { session.invalidateAndCancel(); ManagedURLProtocol.remove(url) }
        let client = CommitPlusAIClient(baseURL: url, tokens: ManagedClientTokens(), session: session)
        do {
            _ = try await client.infer(operation: .repositoryResponse, messages: [.init(role: "user", content: "Hi")], structured: false)
            XCTFail("Expected explicit lost-output recovery")
        } catch { guard case CommitPlusAIError.outputLost = error else { return XCTFail("Unexpected error: \(error)") } }
        let requests = recorder.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertEqual(try Self.body(requests[0])["requestID"] as? String, requests[1].url?.lastPathComponent)
    }

    nonisolated fileprivate static func body(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw CommitPlusAIError.invalidResponse }
                if count == 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            data = bytes
        } else { throw CommitPlusAIError.invalidResponse }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func allowanceObject() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/CommitPlusAI/allowance.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}

@MainActor
private final class ManagedClientTokens: CommitPlusAITokenProviding {
    var refreshes: [Bool] = []
    var switchAfterFirstRead = false
    private var reads = 0
    func currentSession() -> CommitPlusAISession? {
        reads += 1
        return .init(uid: switchAfterFirstRead && reads > 1 ? "other-user" : "test-user", generation: "one")
    }
    func token(for session: CommitPlusAISession, forceRefresh: Bool) async throws -> String {
        refreshes.append(forceRefresh)
        return forceRefresh ? "refreshed-token" : "initial-token"
    }
}

nonisolated private final class ManagedRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { values } }
    func append(_ request: URLRequest) -> [URLRequest] { lock.withLock { values.append(request); return values } }
}

nonisolated private final class ManagedURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, Data)
    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]
    static func makeSession(_ handler: @escaping Handler) -> (URLSession, URL) {
        let host = UUID().uuidString.lowercased() + ".invalid"
        lock.withLock { handlers[host] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManagedURLProtocol.self]
        return (URLSession(configuration: configuration), URL(string: "https://" + host)!)
    }
    static func remove(_ url: URL) { _ = lock.withLock { handlers.removeValue(forKey: url.host!) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url, let handler = Self.lock.withLock({ Self.handlers[url.host ?? ""] }) else { throw CommitPlusAIError.unavailable }
            var normalized = request
            if request.httpBody == nil, request.httpBodyStream != nil {
                normalized.httpBody = try JSONSerialization.data(withJSONObject: CommitPlusAIClientTests.body(request))
            }
            let (status, data) = try handler(normalized)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
