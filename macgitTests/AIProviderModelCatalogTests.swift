// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class AIProviderModelCatalogTests: XCTestCase {
    func testEveryPersonalKeyProviderSuggestsItsDefaultModel() {
        let registry = AIProviderRegistry.live(credentialStore: InMemoryAIProviderCredentialStore())
        for descriptor in registry.descriptors where descriptor.billing == .bringYourOwnKey {
            let defaultModel = descriptor.defaultModel ?? ""
            let ids = AIProviderModelCatalog.suggestions(for: descriptor.id).map(\.id)
            XCTAssertTrue(
                ids.contains(defaultModel),
                "\(descriptor.displayName) should suggest its default model \(defaultModel)"
            )
            XCTAssertEqual(Set(ids).count, ids.count, "\(descriptor.displayName) has duplicate model IDs")
        }
    }

    func testDisplayNameFallsBackToModelID() {
        XCTAssertEqual(AIProviderModelCatalog.displayName(for: "claude-haiku-5-5", provider: .anthropic), "Claude Haiku 5.5")
        XCTAssertEqual(AIProviderModelCatalog.displayName(for: "custom-model", provider: .anthropic), "custom-model")
    }

    func testGroupsKeepFirstAppearanceOrder() {
        let groups = AIProviderModelCatalog.groupedSuggestions(for: .openRouter).map(\.group)
        XCTAssertEqual(groups, ["Popular", "Low Cost"])
    }
}
