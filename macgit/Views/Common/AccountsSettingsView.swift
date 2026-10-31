// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Git provider accounts, kept in their own pane like other Git clients.
struct AccountsSettingsView: View {
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @State private var providerPresentation = GitProviderSettingsPresentation()

    var body: some View {
        Form {
            GitProviderSettingsSection(
                accountController: accountController,
                providerAccountController: providerAccountController,
                presentation: $providerPresentation
            )
        }
        .formStyle(.grouped)
        .navigationTitle("Accounts")
        .gitProviderSettingsPresentations(
            accountController: accountController,
            providerAccountController: providerAccountController,
            presentation: $providerPresentation
        )
    }
}
