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

final class CommitPlusAIContractTests: XCTestCase {
    func testSelectionTruthTable() {
        XCTAssertFalse(CommitPlusAISelectionPolicy.canSelect(isSignedIn: false, hasProAccess: false))
        XCTAssertFalse(CommitPlusAISelectionPolicy.canSelect(isSignedIn: false, hasProAccess: true))
        XCTAssertFalse(CommitPlusAISelectionPolicy.canSelect(isSignedIn: true, hasProAccess: false))
        XCTAssertTrue(CommitPlusAISelectionPolicy.canSelect(isSignedIn: true, hasProAccess: true))
    }

    func testAllowanceRejectsMalformedAccounting() throws {
        let fixture = try fixture("allowance.json")
        let allowance = try JSONDecoder().decode(CommitPlusAIAllowance.self, from: fixture)
        XCTAssertEqual(allowance.availableUnits, 499_900_000)
        XCTAssertEqual(allowance.credits, Decimal(string: "499.9"))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        for (key, value) in [("unitsPerCredit", 1000), ("availableUnits", -1), ("reservedUnits", 1), ("consumedUnits", 500_000_001)] {
            var changed = original
            changed[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(CommitPlusAIAllowance.self, from: JSONSerialization.data(withJSONObject: changed)))
        }
    }

    func testFractionalAndExhaustedAllowance() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("allowance.json")) as? [String: Any])
        object["availableUnits"] = 1
        object["consumedUnits"] = 499_999_999
        let fractional = try JSONDecoder().decode(CommitPlusAIAllowance.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(fractional.creditLabel, "<0.01")
        object["availableUnits"] = 0
        object["consumedUnits"] = 500_000_000
        object["resetsAt"] = NSNull()
        let exhausted = try JSONDecoder().decode(CommitPlusAIAllowance.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(exhausted.availability.isAvailable)
        XCTAssertTrue(exhausted.availability.detail.contains("No further"))
    }

    func testAssistantToolMessageEncodesRequiredNull() throws {
        let message = CommitPlusAIWireMessage(role: "assistant", content: nil,
            toolCalls: [CommitPlusAIToolCall(id: "one", name: "read_status", arguments: "{}")])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
        XCTAssertTrue(object["content"] is NSNull)
        XCTAssertNil(object["toolCallID"])
    }

    func testBytewiseSSEPreservesUnicodeAndCompletedTools() throws {
        var decoder = CommitPlusAIEventDecoder()
        var accumulator = CommitPlusAIStreamAccumulator()
        var result: CommitPlusAIResult?
        var streamed = ""
        for byte in try fixture("agent-response.sse") {
            guard let event = try decoder.append(byte) else { continue }
            if event.name == "completed" {
                let terminal = try JSONDecoder().decode(CommitPlusAIResult.self, from: event.data)
                try terminal.validate(requestID: "f019f2fc-6a66-460e-a377-0c53f194c950")
                try accumulator.validate(terminal)
                result = terminal
            } else {
                XCTAssertNil(result)
                streamed += try accumulator.append(event) ?? ""
            }
        }
        try decoder.finish()
        XCTAssertEqual(streamed, "Checking status…")
        XCTAssertEqual(result?.text, streamed)
        XCTAssertEqual(result?.toolCalls, [CommitPlusAIToolCall(id: "call-1", name: "read_status", arguments: "{}")])
    }

    func testPartialSSEAndInvalidUTF8FailClosed() throws {
        var decoder = CommitPlusAIEventDecoder()
        for byte in Data("event: completed\ndata: {".utf8) { XCTAssertNil(try decoder.append(byte)) }
        XCTAssertThrowsError(try decoder.finish())
        var invalid = CommitPlusAIEventDecoder()
        XCTAssertNil(try invalid.append(255))
        XCTAssertThrowsError(try invalid.append(10))
    }

    func testBaseURLRejectsUnsafeConfiguration() {
        for value in ["", "http://api.example.com", "https://key@api.example.com", "https://api.example.com?key=x", "$(COMMIT_PLUS_AI_BASE_URL)"] {
            XCTAssertNil(CommitPlusAIClient.validatedURL(value))
        }
        XCTAssertNotNil(CommitPlusAIClient.validatedURL("https://api.example.com/managedAI"))
        XCTAssertNil(CommitPlusAIClient.validatedURL("http://localhost:5001"))
        XCTAssertNotNil(CommitPlusAIClient.validatedURL("http://localhost:5001", allowLocalhost: true))
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/CommitPlusAI").appending(path: name))
    }
}
