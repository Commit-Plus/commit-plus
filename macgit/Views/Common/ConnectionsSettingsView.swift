// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct ConnectionsSettingsView: View {
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @State private var authenticationMode: AuthenticationMode?

    var body: some View {
        GitProviderAccountsSection(
            controller: providerAccountController,
            isSignedIn: accountController.account != nil,
            onSignIn: presentSignIn,
            onUpgrade: {
                Task { await accountController.openPricingOnWeb() }
            },
            multipleAccountAccess: multipleAccountAccess
        )
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Connections")
        .replacingSheet(item: $authenticationMode) { mode in
            AuthenticationSheet(controller: accountController, mode: mode)
        }
    }

    private var multipleAccountAccess: FeatureAccessDecision {
        featureAccessController.decision(
            for: .multipleProviderAccounts,
            entitlement: accountController.entitlement
        )
    }

    private func presentSignIn() {
        accountController.errorMessage = nil
        authenticationMode = .signIn
    }
}
