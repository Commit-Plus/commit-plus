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
final class CommitPlusAISelectionPolicyTests: XCTestCase {
    func testManagedSelectionNeedsProButNoKeyAndSurvivesLogout() async throws {
        let usage = CommitPlusAIUsageController()
        let tokens = ManagedSelectionTokens()
        var pro = true
        let provider = CommitPlusAIProvider(client: CommitPlusAIClient(baseURL: nil, tokens: tokens), usage: usage, canAccess: { true })
        let credentials = InMemoryAIProviderCredentialStore()
        let suite = "CommitPlusAISelectionPolicyTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = AIProviderController(registry: .live(credentialStore: credentials, managedProvider: provider),
            snapshotLoader: ManagedSelectionSnapshotLoader(), defaults: defaults, credentialStore: credentials,
            managedProviderAccess: { pro }, managedUsageController: usage)
        XCTAssertTrue(controller.canSelect(provider.descriptor, restrictedProviderAccess: .denied(.requiresPro)))
        controller.selectProvider(.commitPlusAI)
        XCTAssertEqual(controller.selectedProviderID, .commitPlusAI)
        XCTAssertNil(controller.model(for: provider.descriptor))
        XCTAssertFalse(controller.configurationDrafts().contains { $0.id == .commitPlusAI })
        XCTAssertThrowsError(try controller.saveAPIKey("must-not-save", for: .commitPlusAI))
        XCTAssertThrowsError(try controller.removeAPIKey(for: .commitPlusAI))
        XCTAssertNil(try credentials.apiKey(for: .commitPlusAI))
        usage.setSession(uid: "a")
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/CommitPlusAI/allowance.json")
        var exhausted = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        exhausted["consumedUnits"] = 500_000_000
        exhausted["availableUnits"] = 0
        usage.accept(try JSONDecoder().decode(CommitPlusAIAllowance.self, from: JSONSerialization.data(withJSONObject: exhausted)), uid: "a")
        XCTAssertTrue(controller.canSelect(provider.descriptor, restrictedProviderAccess: .denied(.requiresPro)))
        XCTAssertFalse(controller.selectedProviderAvailability.isAvailable)
        XCTAssertEqual(controller.selectedProviderID, .commitPlusAI)
        pro = false
        XCTAssertFalse(controller.canSelect(provider.descriptor, restrictedProviderAccess: .allowed))
        XCTAssertFalse(controller.selectedProviderAvailability.isAvailable)
        XCTAssertEqual(controller.selectedProviderID, .commitPlusAI)
        do {
            _ = try await controller.generateCommitMessage(repositoryURL: URL(fileURLWithPath: "/tmp/unused"),
                branchName: "main", changeSource: .staged, recentCommitSubjects: [])
            XCTFail("Logged-out selection must not authorize generation")
        } catch { }
    }
}

@MainActor
private final class ManagedSelectionTokens: CommitPlusAITokenProviding {
    func currentSession() -> CommitPlusAISession? { nil }
    func token(for session: CommitPlusAISession, forceRefresh: Bool) async throws -> String { throw CommitPlusAIError.signedOut }
}

private actor ManagedSelectionSnapshotLoader: CommitChangeSnapshotLoading {
    func commitChangeSnapshot(in repositoryURL: URL, source: CommitChangeSource, characterBudget: Int) async throws -> CommitChangeSnapshot {
        XCTFail("Access must be checked before loading Git context")
        throw CommitPlusAIError.signedOut
    }
    func changesFingerprint(in repositoryURL: URL, source: CommitChangeSource) async throws -> String { "unused" }
}
