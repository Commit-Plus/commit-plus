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

enum PlanFeature: String, CaseIterable, Codable, Hashable {
    case privateRepositories
    case pullRequests
    case gitFlow
    case gitLFS
    case aiCommitMessage
    case repositoryChat
    case repositoryAIActions
    case aiConflictResolution
    case aiBringYourOwnKey
    case multipleProviderAccounts
}

enum FeatureRepositoryScope: String, Codable, Equatable {
    case none
    case `public`
    case publicOrLocal
    case all
}

enum RepositoryVisibility: String, Codable, Equatable {
    case local
    case `public`
    case `private`
    case unknown
}

struct PlanFeatureRule: Codable, Equatable {
    let enabled: Bool
    let repositoryScope: FeatureRepositoryScope?
}

struct FeaturePolicyRule: Codable, Equatable {
    let enabled: Bool
    let free: PlanFeatureRule
    let pro: PlanFeatureRule
}

struct FeatureAccessPolicy: Codable, Equatable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let revision: Int
    let features: [PlanFeature: FeaturePolicyRule]

    func rule(for feature: PlanFeature) -> FeaturePolicyRule {
        // Earlier policies bundled chat and guided workflows into one Pro gate.
        // Old cached/remote entries cannot express the split introduced in revision 5.
        if revision < 5,
           [.aiCommitMessage, .repositoryChat, .repositoryAIActions].contains(feature) {
            // Preserve an explicit global kill switch from the remote policy.
            if let rule = features[feature], !rule.enabled { return rule }
            return Self.bundled.features[feature] ?? Self.deniedByDefaultRule
        }
        return features[feature] ?? Self.bundled.features[feature] ?? Self.deniedByDefaultRule
    }

    static let bundled = FeatureAccessPolicy(
        schemaVersion: supportedSchemaVersion,
        revision: 6,
        features: [
            .privateRepositories: FeaturePolicyRule(
                enabled: true,
                free: PlanFeatureRule(enabled: false, repositoryScope: FeatureRepositoryScope.none),
                pro: PlanFeatureRule(enabled: true, repositoryScope: .all)
            ),
            .pullRequests: FeaturePolicyRule(
                enabled: true,
                free: PlanFeatureRule(enabled: true, repositoryScope: .public),
                pro: PlanFeatureRule(enabled: true, repositoryScope: .all)
            ),
            .gitLFS: FeaturePolicyRule(
                enabled: true,
                free: PlanFeatureRule(enabled: true, repositoryScope: .public),
                pro: PlanFeatureRule(enabled: true, repositoryScope: .all)
            ),
            .gitFlow: FeaturePolicyRule(
                enabled: true,
                free: PlanFeatureRule(enabled: true, repositoryScope: .publicOrLocal),
                pro: PlanFeatureRule(enabled: true, repositoryScope: .all)
            ),
            .aiCommitMessage: freeAndProRule,
            .repositoryChat: freeAndProRule,
            .repositoryAIActions: proOnlyRule,
            .aiConflictResolution: proOnlyRule,
            .aiBringYourOwnKey: proOnlyRule,
            .multipleProviderAccounts: proOnlyRule
        ]
    )

    private static let freeAndProRule = FeaturePolicyRule(
        enabled: true,
        free: PlanFeatureRule(enabled: true, repositoryScope: nil),
        pro: PlanFeatureRule(enabled: true, repositoryScope: nil)
    )

    private static let proOnlyRule = FeaturePolicyRule(
        enabled: true,
        free: PlanFeatureRule(enabled: false, repositoryScope: nil),
        pro: PlanFeatureRule(enabled: true, repositoryScope: nil)
    )

    private static let deniedByDefaultRule = FeaturePolicyRule(
        enabled: false,
        free: PlanFeatureRule(enabled: false, repositoryScope: FeatureRepositoryScope.none),
        pro: PlanFeatureRule(enabled: false, repositoryScope: FeatureRepositoryScope.none)
    )
}

enum FeatureAccessDenial: Equatable {
    case featureDisabled
    case requiresPro
    case repositoryVisibilityUnavailable
    case repositoryScopeNotAllowed
}

enum FeatureAccessDecision: Equatable {
    case allowed
    case denied(FeatureAccessDenial)

    var isAllowed: Bool {
        self == .allowed
    }
}
