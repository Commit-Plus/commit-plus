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
final class FeatureAccessControllerTests: XCTestCase {
    func testCachePersistsAndReloadsPolicy() {
        let suiteName = "FeatureAccessControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = UserDefaultsFeaturePolicyCache(userDefaults: defaults)
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cached = CachedFeatureAccessPolicy(policy: .bundled, updatedAt: updatedAt)

        cache.save(cached)

        XCTAssertEqual(cache.load(), cached)
    }

    func testControllerHydratesCacheAndKeepsItOnListenerFailure() {
        let provider = FakeFeaturePolicyProvider()
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = FakeFeaturePolicyCache(
            value: CachedFeatureAccessPolicy(policy: .bundled, updatedAt: updatedAt)
        )
        let controller = FeatureAccessController(provider: provider, cache: cache)

        XCTAssertEqual(controller.policy, .bundled)
        XCTAssertEqual(controller.policyLastUpdatedAt, updatedAt)
        XCTAssertTrue(controller.isUsingCachedPolicy)

        controller.start()
        provider.fail("Firestore unavailable")

        XCTAssertEqual(controller.policy, .bundled)
        XCTAssertEqual(controller.policyError, "Firestore unavailable")
        XCTAssertTrue(controller.isUsingCachedPolicy)
    }

    func testValidRemotePolicyReplacesAndPersistsCache() {
        let provider = FakeFeaturePolicyProvider()
        let cache = FakeFeaturePolicyCache()
        let controller = FeatureAccessController(provider: provider, cache: cache)
        let remote = FeatureAccessPolicy(
            schemaVersion: 1,
            revision: 2,
            features: FeatureAccessPolicy.bundled.features
        )

        controller.start()
        provider.send(remote)

        XCTAssertEqual(controller.policy, remote)
        XCTAssertEqual(cache.value?.policy, remote)
        XCTAssertNil(controller.policyError)
        XCTAssertFalse(controller.isUsingCachedPolicy)
    }

    func testLiveObservationIsDeferredAndStartsOnlyOnce() {
        let provider = FakeFeaturePolicyProvider()
        let controller = FeatureAccessController(provider: provider, cache: FakeFeaturePolicyCache())

        XCTAssertEqual(provider.observeCount, 0)
        controller.start()
        controller.start()

        XCTAssertEqual(provider.observeCount, 1)
    }
}

@MainActor
private final class FakeFeaturePolicyProvider: FeaturePolicyProviding {
    private(set) var observeCount = 0
    private var onChange: ((FeatureAccessPolicy) -> Void)?
    private var onError: ((String) -> Void)?

    func observe(
        onChange: @escaping (FeatureAccessPolicy) -> Void,
        onError: @escaping (String) -> Void
    ) -> ObservationToken {
        observeCount += 1
        self.onChange = onChange
        self.onError = onError
        return FakeFeaturePolicyObservationToken()
    }

    func send(_ policy: FeatureAccessPolicy) {
        onChange?(policy)
    }

    func fail(_ message: String) {
        onError?(message)
    }
}

private final class FakeFeaturePolicyObservationToken: ObservationToken {
    func cancel() {}
}

@MainActor
private final class FakeFeaturePolicyCache: FeaturePolicyCaching {
    var value: CachedFeatureAccessPolicy?

    init(value: CachedFeatureAccessPolicy? = nil) {
        self.value = value
    }

    func load() -> CachedFeatureAccessPolicy? {
        value
    }

    func save(_ cachedPolicy: CachedFeatureAccessPolicy) {
        value = cachedPolicy
    }
}
