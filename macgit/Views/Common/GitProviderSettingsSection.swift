// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Sheet and dialog state for `GitProviderSettingsSection`, presented from the enclosing Form
/// with `gitProviderSettingsPresentations`.
struct GitProviderSettingsPresentation {
    var accounts = GitProviderAccountsPresentation()
    var authenticationMode: AuthenticationMode?
}

/// Git provider connections, shown as a section of the Git settings pane.
struct GitProviderSettingsSection: View {
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @Binding var presentation: GitProviderSettingsPresentation

    var body: some View {
        GitProviderAccountsSection(
            controller: providerAccountController,
            isSignedIn: accountController.account != nil,
            onSignIn: presentSignIn,
            onUpgrade: {
                Task { await accountController.openPricingOnWeb() }
            },
            multipleAccountAccess: featureAccessController.multipleProviderAccountsDecision(
                entitlement: accountController.entitlement
            ),
            presentation: $presentation.accounts
        )
    }

    private func presentSignIn() {
        accountController.errorMessage = nil
        presentation.authenticationMode = .signIn
    }
}

extension View {
    func gitProviderSettingsPresentations(
        accountController: AccountSessionController,
        providerAccountController: GitProviderAccountController,
        presentation: Binding<GitProviderSettingsPresentation>
    ) -> some View {
        modifier(GitProviderSettingsPresentationModifier(
            accountController: accountController,
            providerAccountController: providerAccountController,
            presentation: presentation
        ))
    }
}

private struct GitProviderSettingsPresentationModifier: ViewModifier {
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @Binding var presentation: GitProviderSettingsPresentation

    func body(content: Content) -> some View {
        content
            .gitProviderAccountsPresentations(
                controller: providerAccountController,
                multipleAccountAccess: featureAccessController.multipleProviderAccountsDecision(
                    entitlement: accountController.entitlement
                ),
                presentation: $presentation.accounts
            )
            .replacingSheet(item: $presentation.authenticationMode) { mode in
                AuthenticationSheet(controller: accountController, mode: mode)
            }
    }
}

private extension FeatureAccessController {
    func multipleProviderAccountsDecision(entitlement: AccountEntitlement) -> FeatureAccessDecision {
        decision(for: .multipleProviderAccounts, entitlement: entitlement)
    }
}
