// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

extension MainWindowView {
    /// Hosted issues follow the repository's visibility, like pull requests.
    func authorizeHostedIssueAccess(
        forceRefresh: Bool = false,
        presentNotice: Bool = true
    ) async -> Bool {
        let decision = await repositoryVisibilityController.accessDecision(
            for: .hostedIssues,
            repositoryURL: repositoryURL,
            accounts: providerAccountController.accounts,
            entitlement: accountController.entitlement,
            policy: featureAccessController.policy,
            forceRefresh: forceRefresh
        )
        guard !Task.isCancelled else { return false }
        hostedIssueAccessDecision = decision
        if case .denied(let denial) = decision, presentNotice {
            if denial == .requiresPro {
                proUpgradeErrorMessage = nil
                proUpgradePresentation = ProUpgradePresentation(feature: .hostedIssues)
            } else {
                featureAccessNotice = FeatureAccessNotice(feature: .hostedIssues, denial: denial)
            }
        }
        return decision.isAllowed
    }
}
