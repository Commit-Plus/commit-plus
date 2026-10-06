// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct ConnectionsSettingsView: View {
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @State private var showingAddAccountSheet = false
    @State private var authenticationMode: AuthenticationMode?

    var body: some View {
        Form {
            Section {
                GitProviderAccountsSection(
                    controller: providerAccountController,
                    isSignedIn: accountController.account != nil,
                    onSignIn: presentSignIn,
                    onUpgrade: {
                        Task { await accountController.openPricingOnWeb() }
                    },
                    multipleAccountAccess: multipleAccountAccess,
                    showsTitle: false,
                    alignsActionsToTrailingEdge: true,
                    showsAddButton: false,
                    addAccountPresentation: $showingAddAccountSheet
                )
            } header: {
                Label("Git Provider Accounts", systemImage: "network")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                Text("GitHub and GitLab use OAuth. Bitbucket Cloud uses an API token. All providers support HTTPS or SSH Git operations.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Add", systemImage: "plus") {
                    showingAddAccountSheet = true
                }
                .disabled(providerAccountController.isLoading || !accountCreationDecision.isAllowed)
                .fixedSize()
            }
            .padding()
        }
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

    private var accountCreationDecision: GitProviderAccountCreationDecision {
        GitProviderAccountAccessPolicy().creationDecision(
            existingAccountCount: providerAccountController.accounts.count,
            multipleAccountAccess: multipleAccountAccess
        )
    }

    private func presentSignIn() {
        accountController.errorMessage = nil
        authenticationMode = .signIn
    }
}
