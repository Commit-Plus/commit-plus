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
final class CommitPlusAIUsageControllerTests: XCTestCase {
    func testLoadAndFailureDoNotInventBalance() async throws {
        let value = try allowance()
        let controller = CommitPlusAIUsageController()
        controller.setSession(uid: "a")
        controller.loader = { value }
        await controller.refresh()
        XCTAssertEqual(controller.state, .loaded(value))
        controller.loader = { throw CommitPlusAIError.unavailable }
        await controller.refresh(force: true)
        guard case .unavailable = controller.state else { return XCTFail("Expected unavailable, not a default balance") }
    }

    func testConcurrentRefreshesShareOneLoad() async throws {
        let value = try allowance()
        let gate = ManagedAllowanceGate()
        let controller = CommitPlusAIUsageController()
        controller.setSession(uid: "a")
        controller.loader = { await gate.load() }
        let first = Task { await controller.refresh(force: true) }
        await gate.waitForLoad()
        let entered = expectation(description: "Second refresh entered")
        let second = Task { entered.fulfill(); await controller.refresh(force: true) }
        await fulfillment(of: [entered], timeout: 2)
        await gate.resolve(value)
        await first.value
        await second.value
        let count = await gate.loadCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(controller.state, .loaded(value))
    }

    func testAccountSwitchDiscardsDelayedAllowance() async throws {
        let value = try allowance()
        let gate = ManagedAllowanceGate()
        let controller = CommitPlusAIUsageController()
        controller.setSession(uid: "a")
        controller.loader = { await gate.load() }
        let refresh = Task { await controller.refresh() }
        await gate.waitForLoad()
        controller.setSession(uid: "b")
        await gate.resolve(value)
        await refresh.value
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.uid, "b")
    }

    func testTerminalAllowanceSupersedesEarlierRead() async throws {
        let old = try allowance()
        let fresh = try allowance(consumed: 500_000_000)
        let gate = ManagedAllowanceGate()
        let controller = CommitPlusAIUsageController()
        controller.setSession(uid: "a")
        controller.loader = { await gate.load() }
        let refresh = Task { await controller.refresh() }
        await gate.waitForLoad()
        controller.accept(fresh, uid: "a")
        await gate.resolve(old)
        await refresh.value
        XCTAssertEqual(controller.state, .loaded(fresh))
        XCTAssertFalse(controller.availability.isAvailable)
    }

    private func allowance(consumed: Int = 100_000) throws -> CommitPlusAIAllowance {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/CommitPlusAI/allowance.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["consumedUnits"] = consumed
        object["availableUnits"] = 500_000_000 - consumed
        return try JSONDecoder().decode(CommitPlusAIAllowance.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

private actor ManagedAllowanceGate {
    private(set) var loadCount = 0
    private var continuations: [CheckedContinuation<CommitPlusAIAllowance, Never>] = []
    private var waiting: CheckedContinuation<Void, Never>?
    func load() async -> CommitPlusAIAllowance {
        loadCount += 1
        return await withCheckedContinuation { continuation in
            self.continuations.append(continuation)
            waiting?.resume()
            waiting = nil
        }
    }
    func waitForLoad() async {
        if !continuations.isEmpty { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func resolve(_ value: CommitPlusAIAllowance) {
        continuations.forEach { $0.resume(returning: value) }
        continuations = []
    }
}
