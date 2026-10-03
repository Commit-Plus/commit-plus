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

struct ConnectionsSheet: View {
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @State private var showingAddAccountSheet = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connections")
                .font(.title2)
                .bold()

            ScrollView {
                GitProviderAccountsSection(
                    controller: providerAccountController,
                    isSignedIn: accountController.account != nil,
                    onSignIn: { accountController.presentAuthentication(.signIn) },
                    onUpgrade: {
                        Task { await accountController.openPricingOnWeb() }
                    },
                    multipleAccountAccess: multipleAccountAccess,
                    showsAddButton: false,
                    addAccountPresentation: $showingAddAccountSheet
                )
                .padding(.trailing, 8)
            }

            HStack {
                Button("Add", systemImage: "plus", action: presentAddAccount)
                    .disabled(
                        providerAccountController.isLoading || !accountCreationDecision.isAllowed
                    )

                Spacer()

                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(
            minWidth: 480,
            minHeight: 420,
            idealHeight: 560,
            maxHeight: 640
        )
    }

    private func dismiss() {
        accountController.presentedSheet = nil
    }

    private func presentAddAccount() {
        showingAddAccountSheet = true
    }
}
