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

import FirebaseFirestore
import Foundation

enum FeaturePolicyDocumentDecoder {
    static func decode(
        _ data: [String: Any]?,
        onDiagnostic: ((String) -> Void)? = nil
    ) -> FeatureAccessPolicy? {
        guard let data else {
            onDiagnostic?("The release feature policy does not exist.")
            return nil
        }
        guard integer(data["schemaVersion"]) == FeatureAccessPolicy.supportedSchemaVersion,
              let revision = integer(data["revision"]),
              revision > 0,
              let rawFeatures = data["features"] as? [String: Any] else {
            onDiagnostic?("The release feature policy header is malformed.")
            return nil
        }

        var decodedFeatures: [PlanFeature: FeaturePolicyRule] = [:]
        for feature in PlanFeature.allCases {
            guard let rawRule = rawFeatures[feature.rawValue] as? [String: Any],
                  let rule = decodeRule(rawRule, feature: feature) else {
                onDiagnostic?("Feature policy entry '\(feature.rawValue)' is missing or malformed; using the bundled entry.")
                continue
            }
            decodedFeatures[feature] = rule
        }

        return FeatureAccessPolicy(
            schemaVersion: FeatureAccessPolicy.supportedSchemaVersion,
            revision: revision,
            features: decodedFeatures
        )
    }

    private static func decodeRule(
        _ data: [String: Any],
        feature: PlanFeature
    ) -> FeaturePolicyRule? {
        guard let enabled = data["enabled"] as? Bool,
              let plans = data["plans"] as? [String: Any],
              let freeData = plans[AccountPlan.free.rawValue] as? [String: Any],
              let proData = plans[AccountPlan.pro.rawValue] as? [String: Any],
              let free = decodePlanRule(freeData),
              let pro = decodePlanRule(proData) else {
            return nil
        }

        if feature.requiresRepositoryScope,
           (free.repositoryScope == nil || pro.repositoryScope == nil) {
            return nil
        }

        return FeaturePolicyRule(enabled: enabled, free: free, pro: pro)
    }

    private static func decodePlanRule(_ data: [String: Any]) -> PlanFeatureRule? {
        guard let enabled = data["enabled"] as? Bool else { return nil }
        let scope: FeatureRepositoryScope?
        if let rawScope = data["repositoryScope"] as? String {
            guard let decodedScope = FeatureRepositoryScope(rawValue: rawScope) else { return nil }
            scope = decodedScope
        } else {
            scope = nil
        }
        return PlanFeatureRule(enabled: enabled, repositoryScope: scope)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard !(value is Bool) else { return nil }
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }
}

private extension PlanFeature {
    var requiresRepositoryScope: Bool {
        switch self {
        case .privateRepositories, .pullRequests, .gitFlow, .gitLFS:
            true
        case .aiCommitMessage, .repositoryChat, .repositoryAIActions, .aiConflictResolution, .aiBringYourOwnKey,
             .multipleProviderAccounts:
            false
        }
    }
}

@MainActor
protocol FeaturePolicyProviding {
    func observe(
        onChange: @escaping (FeatureAccessPolicy) -> Void,
        onError: @escaping (String) -> Void
    ) -> ObservationToken
}

@MainActor
final class FirestoreFeaturePolicyStore: FeaturePolicyProviding {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func observe(
        onChange: @escaping (FeatureAccessPolicy) -> Void,
        onError: @escaping (String) -> Void
    ) -> ObservationToken {
        let registration = firestore.collection("featurePolicies").document("release")
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error.localizedDescription)
                    return
                }

                var diagnostic: String?
                guard let policy = FeaturePolicyDocumentDecoder.decode(
                    snapshot?.data(),
                    onDiagnostic: { diagnostic = $0 }
                ) else {
                    onError(diagnostic ?? "The release feature policy is unavailable.")
                    return
                }
                if let diagnostic {
                    NSLog("Commit+ feature policy: %@", diagnostic)
                }
                onChange(policy)
            }
        return FeaturePolicyObservationToken(registration: registration)
    }
}

private final class FeaturePolicyObservationToken: ObservationToken {
    private var registration: ListenerRegistration?

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit {
        registration?.remove()
    }
}
