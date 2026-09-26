// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Shared plan boundary for LFS management and explicit preview downloads.
struct GitLFSAccessView<Content: View>: View {
    let repositoryURL: URL
    @ViewBuilder let content: (@escaping @MainActor () async -> Bool) -> Content
    @EnvironmentObject private var accountController: AccountSessionController
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @EnvironmentObject private var repositoryVisibilityController: RepositoryVisibilityController
    @EnvironmentObject private var providerAccountController: GitProviderAccountController
    @State private var decision: FeatureAccessDecision?
    @State private var resolvedTaskID: String?
    @State private var showUpgrade = false

    var body: some View {
        Group {
            if resolvedTaskID != taskID {
                ProgressView("Checking Git LFS access…")
            } else {
                switch decision {
                case .allowed:
                    content { await authorize() }
                case .denied(let denial):
                    FeatureAccessUnavailableView(
                        notice: FeatureAccessNotice(feature: .gitLFS, denial: denial),
                        isSignedIn: accountController.account != nil,
                        onAccountAction: {
                            if accountController.account == nil {
                                accountController.presentAuthentication(.signIn)
                            } else {
                                showUpgrade = true
                            }
                        },
                        onRetry: { Task { _ = await authorize(forceRefresh: true) } }
                    )
                case nil:
                    ProgressView("Checking Git LFS access…")
                }
            }
        }
        .task(id: taskID) { _ = await authorize() }
        .sheet(isPresented: $showUpgrade) {
            ProUpgradeSheet(
                feature: .gitLFS,
                isSignedIn: accountController.account != nil,
                isOpening: accountController.openingWebDestination == .pricing,
                errorMessage: accountController.errorMessage,
                onCancel: { showUpgrade = false },
                onPrimaryAction: { Task { await accountController.openPricingOnWeb() } }
            )
        }
    }

    private var taskID: String {
        [repositoryURL.absoluteString,
         String(describing: featureAccessController.policy.rule(for: .gitLFS)),
         String(describing: accountController.entitlement),
         String(describing: providerAccountController.accounts)].joined(separator: "|")
    }

    @MainActor
    private func authorize(forceRefresh: Bool = false) async -> Bool {
        let requestID = taskID
        let visibility = await repositoryVisibilityController.resolve(
            repositoryURL: repositoryURL,
            accounts: providerAccountController.accounts,
            forceRefresh: forceRefresh
        )
        guard !Task.isCancelled, requestID == taskID else { return false }
        let result = featureAccessController.decision(
            for: .gitLFS,
            entitlement: accountController.entitlement,
            repositoryVisibility: visibility
        )
        decision = result
        resolvedTaskID = requestID
        return result.isAllowed
    }
}
