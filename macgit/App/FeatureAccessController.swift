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

import Combine
import Foundation

@MainActor
final class FeatureAccessController: ObservableObject {
    @Published private(set) var policy: FeatureAccessPolicy
    @Published private(set) var policyError: String?
    @Published private(set) var policyLastUpdatedAt: Date?
    @Published private(set) var isUsingCachedPolicy = false

    private let provider: FeaturePolicyProviding?
    private let cache: FeaturePolicyCaching
    private var observation: ObservationToken?
    private var didStart = false

    init(
        provider: FeaturePolicyProviding?,
        cache: FeaturePolicyCaching
    ) {
        self.provider = provider
        self.cache = cache

        if let cached = cache.load() {
            policy = cached.policy
            policyLastUpdatedAt = cached.updatedAt
            isUsingCachedPolicy = true
        } else {
            policy = .bundled
        }

    }

    /// The cached or bundled policy is immediately available. Live policy
    /// updates begin once the first app window has finished initial setup.
    func start() {
        guard !didStart else { return }
        didStart = true
        startObservation()
    }

    func decision(
        for feature: PlanFeature,
        entitlement: AccountEntitlement,
        repositoryVisibility: RepositoryVisibility? = nil
    ) -> FeatureAccessDecision {
        FeatureAccessResolver(policy: policy).decision(
            for: feature,
            entitlement: entitlement,
            repositoryVisibility: repositoryVisibility
        )
    }

    private func startObservation() {
        guard let provider else { return }
        observation = provider.observe(
            onChange: { [weak self] policy in
                guard let self else { return }
                let updatedAt = Date.now
                self.policy = policy
                policyError = nil
                policyLastUpdatedAt = updatedAt
                isUsingCachedPolicy = false
                cache.save(CachedFeatureAccessPolicy(policy: policy, updatedAt: updatedAt))
            },
            onError: { [weak self] message in
                self?.policyError = message
                self?.isUsingCachedPolicy = self?.policyLastUpdatedAt != nil
            }
        )
    }

    deinit {
        observation?.cancel()
    }
}
