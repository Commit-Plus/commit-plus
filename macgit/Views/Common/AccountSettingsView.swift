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

import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController

    @State private var authenticationMode: AuthenticationMode?
    @State private var confirmsAccountDeletion = false

    var body: some View {
        Form {
            Section {
                if let account = accountController.account {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayLabel)
                                .font(.headline)

                            if let email = account.email,
                               email != account.displayLabel {
                                Text(email)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Label(
                            accountController.entitlement.planDisplayName,
                            systemImage: accountController.entitlement.plan == .pro
                                ? "star.fill"
                                : "person"
                        )
                        .foregroundStyle(accountController.entitlement.plan == .pro ? .yellow : .secondary)
                    }
                    .padding(.vertical, 4)

                    LabeledContent("Sign-in methods", value: providerSummary(for: account))

                    if accountController.entitlement.plan == .pro {
                        LabeledContent(
                            "Billing status",
                            value: accountController.entitlement.billingStatusDisplayName
                        )
                        if let currentPeriodEnd = accountController.entitlement.currentPeriodEnd {
                            LabeledContent(
                                accountController.entitlement.cancelAtPeriodEnd ? "Access until" : "Renews",
                                value: currentPeriodEnd.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                    }

                    if accountController.isUsingCachedEntitlement,
                       let updatedAt = accountController.entitlementLastUpdatedAt {
                        LabeledContent(
                            "Plan status",
                            value: "Saved locally · Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))"
                        )
                    }

                    Toggle("Sync app settings with Commit+ Cloud", isOn: syncSettingsBinding)
                        .disabled(!accountController.cloudFeaturesAvailable)

                    LabeledContent("Cloud sync status") {
                        Text(accountController.settingsSyncDisplayText)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", action: signOut)

                        if accountController.requiresRecentAuthentication {
                            Button("Sign In Again…", action: presentSignIn)
                        }

                        Spacer()

                        Button("Delete Account…", systemImage: "trash", role: .destructive) {
                            confirmsAccountDeletion = true
                        }
                        .disabled(accountController.isDeletingAccount)
                    }

                    if accountController.isDeletingAccount {
                        ProgressView("Deleting Commit+ account…")
                            .controlSize(.small)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Not signed in")
                                    .font(.headline)
                                Text(accountController.cloudFeaturesAvailable
                                     ? "Sign in to sync app settings and connect Git provider accounts."
                                     : "Cloud accounts are unavailable in this build.")
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.title2)
                        }

                        HStack {
                            Button("Sign In…", action: presentSignIn)
                                .keyboardShortcut(.defaultAction)
                            Button("Create Account…", action: presentCreateAccount)
                        }
                        .disabled(!accountController.cloudFeaturesAvailable)
                    }
                    .padding(.vertical, 4)
                }

                if let message = (accountController.isUsingCachedEntitlement ? nil : accountController.entitlementError)
                    ?? accountController.settingsSyncError
                    ?? accountController.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Account error: \(message)")
                }
            } header: {
                Label("Commit+ Account", systemImage: "person.crop.circle")
            } footer: {
                Text("Your Commit+ account is used for cloud settings, plan access, and securely associating provider connections.")
            }

            Section {
                GitProviderAccountsSection(
                    controller: providerAccountController,
                    isSignedIn: accountController.account != nil,
                    onSignIn: presentSignIn,
                    onUpgrade: {
                        Task { await accountController.openPricingOnWeb() }
                    },
                    multipleAccountAccess: featureAccessController.decision(
                        for: .multipleProviderAccounts,
                        entitlement: accountController.entitlement
                    ),
                    showsTitle: false
                )
            } header: {
                Label("Git Provider Accounts", systemImage: "network")
            } footer: {
                Text("GitHub and GitLab use OAuth. Bitbucket Cloud uses an API token. All providers support HTTPS or SSH Git operations.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Account")
        .replacingSheet(item: $authenticationMode) { mode in
            AuthenticationSheet(controller: accountController, mode: mode)
        }
        .confirmationDialog(
            "Delete Commit+ Account?",
            isPresented: $confirmsAccountDeletion
        ) {
            Button("Delete Account", role: .destructive, action: deleteAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your Commit+ cloud settings, entitlement record, and account. Local repositories and Git data will not be changed.")
        }
    }

    private var syncSettingsBinding: Binding<Bool> {
        Binding(
            get: { accountController.settingsSyncEnabled },
            set: accountController.setSettingsSyncEnabled
        )
    }

    private func providerSummary(for account: AccountSnapshot) -> String {
        let names = account.providerIDs.map { providerID in
            switch providerID {
            case "password": "Email & Password"
            case "google.com": "Google"
            default: providerID
            }
        }
        return names.isEmpty ? "Unknown" : names.joined(separator: ", ")
    }

    private func presentSignIn() {
        accountController.errorMessage = nil
        authenticationMode = .signIn
    }

    private func presentCreateAccount() {
        accountController.errorMessage = nil
        authenticationMode = .createAccount
    }

    private func signOut() {
        accountController.signOut()
    }

    private func deleteAccount() {
        Task {
            await accountController.deleteAccount()
        }
    }
}
