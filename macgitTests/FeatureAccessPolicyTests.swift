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

import XCTest
@testable import macgit

final class FeatureAccessPolicyTests: XCTestCase {
    func testBundledPolicyMatchesReleasePlanMatrix() {
        let resolver = FeatureAccessResolver(policy: .bundled)

        XCTAssertEqual(
            resolver.decision(
                for: .privateRepositories,
                entitlement: .free,
                repositoryVisibility: .private
            ),
            .denied(.requiresPro)
        )
        XCTAssertEqual(
            resolver.decision(
                for: .pullRequests,
                entitlement: .free,
                repositoryVisibility: .public
            ),
            .allowed
        )
        XCTAssertEqual(
            resolver.decision(
                for: .pullRequests,
                entitlement: .free,
                repositoryVisibility: .private
            ),
            .denied(.requiresPro)
        )
        XCTAssertEqual(
            resolver.decision(
                for: .gitFlow,
                entitlement: .free,
                repositoryVisibility: .local
            ),
            .allowed
        )
        XCTAssertEqual(
            resolver.decision(for: .aiCommitMessage, entitlement: .free),
            .allowed
        )
        XCTAssertEqual(
            resolver.decision(for: .multipleProviderAccounts, entitlement: .free),
            .denied(.requiresPro)
        )
        XCTAssertEqual(
            resolver.decision(for: .multipleProviderAccounts, entitlement: activePro),
            .allowed
        )
    }

    func testGitLFSPlanAndRepositoryMatrix() {
        let resolver = FeatureAccessResolver(policy: .bundled)
        for entitlement in [AccountEntitlement.free, inactivePro] {
            XCTAssertEqual(resolver.decision(for: .gitLFS, entitlement: entitlement, repositoryVisibility: .public), .allowed)
            for visibility in [RepositoryVisibility.private, .local] {
                XCTAssertEqual(resolver.decision(for: .gitLFS, entitlement: entitlement, repositoryVisibility: visibility), .denied(.requiresPro))
            }
        }
        for visibility in [RepositoryVisibility.public, .private, .local] {
            XCTAssertEqual(resolver.decision(for: .gitLFS, entitlement: activePro, repositoryVisibility: visibility), .allowed)
        }
        for entitlement in [AccountEntitlement.free, activePro] {
            XCTAssertEqual(resolver.decision(for: .gitLFS, entitlement: entitlement, repositoryVisibility: .unknown), .denied(.repositoryVisibilityUnavailable))
        }
    }

    func testGitLFSLegacyAndMalformedPoliciesUseScopedFallback() {
        let legacy = FeatureAccessPolicy(schemaVersion: 1, revision: 5, features: [:])
        XCTAssertEqual(legacy.rule(for: .gitLFS), FeatureAccessPolicy.bundled.rule(for: .gitLFS))
        let malformed = FeaturePolicyDocumentDecoder.decode(document(overrides: ["gitLFS": proOnlyRule()]))
        XCTAssertEqual(malformed?.rule(for: .gitLFS), FeatureAccessPolicy.bundled.rule(for: .gitLFS))
    }

    func testGitLFSRemoteKillSwitchIsRespected() {
        let policy = FeaturePolicyDocumentDecoder.decode(document(overrides: ["gitLFS": [
            "enabled": false,
            "plans": [
                "free": ["enabled": true, "repositoryScope": "public"],
                "pro": ["enabled": true, "repositoryScope": "all"]
            ]
        ]]))!
        XCTAssertEqual(FeatureAccessResolver(policy: policy).decision(for: .gitLFS, entitlement: activePro, repositoryVisibility: .private), .denied(.featureDisabled))
    }

    func testFreeAIAllowsChatAndGenerationButRequiresProForWorkflowsAndConflicts() {
        let resolver = FeatureAccessResolver(policy: .bundled)
        for feature in [PlanFeature.aiCommitMessage, .repositoryChat] {
            XCTAssertEqual(resolver.decision(for: feature, entitlement: .free), .allowed)
        }
        for feature in [PlanFeature.repositoryAIActions, .aiConflictResolution, .aiBringYourOwnKey] {
            XCTAssertEqual(resolver.decision(for: feature, entitlement: .free), .denied(.requiresPro))
            XCTAssertEqual(resolver.decision(for: feature, entitlement: activePro), .allowed)
        }
    }

    func testLegacyPolicyUsesNewAIPlanSplit() {
        let oldProRule = FeaturePolicyRule(
            enabled: true,
            free: PlanFeatureRule(enabled: false, repositoryScope: nil),
            pro: PlanFeatureRule(enabled: true, repositoryScope: nil)
        )
        let policy = FeatureAccessPolicy(
            schemaVersion: 1,
            revision: 4,
            features: [.aiCommitMessage: oldProRule, .repositoryChat: oldProRule]
        )
        let resolver = FeatureAccessResolver(policy: policy)
        XCTAssertEqual(resolver.decision(for: .repositoryChat, entitlement: .free), .allowed)
        XCTAssertEqual(resolver.decision(for: .aiCommitMessage, entitlement: .free), .allowed)
        XCTAssertEqual(resolver.decision(for: .repositoryAIActions, entitlement: .free), .denied(.requiresPro))
    }

    func testOnlyActiveProEntitlementReceivesProRules() {
        let resolver = FeatureAccessResolver(policy: .bundled)

        XCTAssertEqual(
            resolver.decision(
                for: .privateRepositories,
                entitlement: activePro,
                repositoryVisibility: .private
            ),
            .allowed
        )
        XCTAssertEqual(
            resolver.decision(
                for: .privateRepositories,
                entitlement: inactivePro,
                repositoryVisibility: .private
            ),
            .denied(.requiresPro)
        )
    }

    func testUnknownVisibilityFailsClosedForScopedFreeFeature() {
        let resolver = FeatureAccessResolver(policy: .bundled)

        XCTAssertEqual(
            resolver.decision(
                for: .pullRequests,
                entitlement: .free,
                repositoryVisibility: .unknown
            ),
            .denied(.repositoryVisibilityUnavailable)
        )
    }

    func testUnknownVisibilityFailsClosedForScopedProFeature() {
        let resolver = FeatureAccessResolver(policy: .bundled)

        XCTAssertEqual(
            resolver.decision(
                for: .pullRequests,
                entitlement: activePro,
                repositoryVisibility: .unknown
            ),
            .denied(.repositoryVisibilityUnavailable)
        )
    }

    func testGitFlowReleaseMatrixUsesSharedRepositoryScopeBoundary() {
        let resolver = FeatureAccessResolver(policy: .bundled)

        XCTAssertEqual(
            resolver.decision(
                for: .gitFlow,
                entitlement: .free,
                repositoryVisibility: .public
            ),
            .allowed
        )
        XCTAssertEqual(
            resolver.decision(
                for: .gitFlow,
                entitlement: .free,
                repositoryVisibility: .local
            ),
            .allowed
        )
        XCTAssertEqual(
            resolver.decision(
                for: .gitFlow,
                entitlement: .free,
                repositoryVisibility: .private
            ),
            .denied(.requiresPro)
        )
        XCTAssertEqual(
            resolver.decision(
                for: .gitFlow,
                entitlement: activePro,
                repositoryVisibility: .private
            ),
            .allowed
        )
        XCTAssertEqual(
            resolver.decision(
                for: .gitFlow,
                entitlement: activePro,
                repositoryVisibility: .unknown
            ),
            .denied(.repositoryVisibilityUnavailable)
        )
    }

    func testGloballyDisabledFeatureStaysDisabledForPro() {
        let disabled = FeaturePolicyRule(
            enabled: false,
            free: PlanFeatureRule(enabled: true, repositoryScope: nil),
            pro: PlanFeatureRule(enabled: true, repositoryScope: nil)
        )
        let policy = FeatureAccessPolicy(
            schemaVersion: 1,
            revision: 5,
            features: [.aiCommitMessage: disabled]
        )

        XCTAssertEqual(
            FeatureAccessResolver(policy: policy).decision(
                for: .aiCommitMessage,
                entitlement: activePro
            ),
            .denied(.featureDisabled)
        )
    }

    func testDecoderAcceptsValidPolicyAndFallsBackPerMalformedEntry() {
        var diagnostics: [String] = []
        let policy = FeaturePolicyDocumentDecoder.decode(
            document(
                overrides: [
                    PlanFeature.pullRequests.rawValue: [
                        "enabled": true,
                        "plans": [
                            "free": ["enabled": true],
                            "pro": ["enabled": true, "repositoryScope": "all"]
                        ]
                    ]
                ]
            ),
            onDiagnostic: { diagnostics.append($0) }
        )

        XCTAssertEqual(policy?.revision, 7)
        XCTAssertEqual(
            policy?.rule(for: .pullRequests),
            FeatureAccessPolicy.bundled.rule(for: .pullRequests)
        )
        XCTAssertTrue(diagnostics.contains { $0.contains("pullRequests") })
        XCTAssertEqual(policy?.rule(for: .gitFlow).free.repositoryScope, .publicOrLocal)
    }

    func testDecoderRejectsMalformedHeader() {
        XCTAssertNil(FeaturePolicyDocumentDecoder.decode([
            "schemaVersion": 2,
            "revision": 1,
            "features": [:]
        ]))
        XCTAssertNil(FeaturePolicyDocumentDecoder.decode([
            "schemaVersion": true,
            "revision": 1,
            "features": [:]
        ]))
    }

    private var activePro: AccountEntitlement {
        AccountEntitlement(plan: .pro, access: .active, billingStatus: .active)
    }

    private var inactivePro: AccountEntitlement {
        AccountEntitlement(plan: .pro, access: .inactive, billingStatus: .canceled)
    }

    private func document(overrides: [String: Any] = [:]) -> [String: Any] {
        var features: [String: Any] = [
            "privateRepositories": scopedRule(freeEnabled: false, freeScope: "none"),
            "pullRequests": scopedRule(freeEnabled: true, freeScope: "public"),
            "gitFlow": scopedRule(freeEnabled: true, freeScope: "publicOrLocal"),
            "aiCommitMessage": proOnlyRule(),
            "repositoryChat": proOnlyRule(),
            "repositoryAIActions": proOnlyRule(),
            "aiConflictResolution": proOnlyRule(),
            "aiBringYourOwnKey": proOnlyRule(),
            "multipleProviderAccounts": proOnlyRule()
        ]
        features.merge(overrides) { _, replacement in replacement }
        return ["schemaVersion": 1, "revision": 7, "features": features]
    }

    private func scopedRule(freeEnabled: Bool, freeScope: String) -> [String: Any] {
        [
            "enabled": true,
            "plans": [
                "free": ["enabled": freeEnabled, "repositoryScope": freeScope],
                "pro": ["enabled": true, "repositoryScope": "all"]
            ]
        ]
    }

    private func proOnlyRule() -> [String: Any] {
        [
            "enabled": true,
            "plans": [
                "free": ["enabled": false],
                "pro": ["enabled": true]
            ]
        ]
    }
}
