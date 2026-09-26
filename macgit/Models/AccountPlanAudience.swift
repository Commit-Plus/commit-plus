// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// A set of stable plan identifiers; no ordering assumptions between subscription tiers.
/// New plans only need to expose their identifier through AccountPlan.
struct AccountPlanAudience {
    private let planIDs: Set<String>?

    init?(configuration: Any?) {
        guard let configuration else {
            planIDs = nil // Compatibility with campaigns created before audience targeting.
            return
        }
        if let value = configuration as? String, !value.isEmpty {
            planIDs = value == "everyone" ? nil : [value]
        } else if let values = configuration as? [String],
                  !values.isEmpty, values.allSatisfy({ !$0.isEmpty && $0 != "everyone" }) {
            planIDs = Set(values)
        } else {
            return nil
        }
    }

    func contains(_ plan: AccountPlan) -> Bool {
        planIDs?.contains(plan.rawValue) ?? true
    }
}

extension AccountEntitlement {
    /// Marketing audiences follow effective access, including expired subscriptions.
    var effectivePlan: AccountPlan {
        access == .active ? plan : .free
    }
}
