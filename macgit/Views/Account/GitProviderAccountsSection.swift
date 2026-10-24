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

/// Sheet and dialog state for `GitProviderAccountsSection`. The presentations are attached to the
/// enclosing Form with `gitProviderAccountsPresentations`, because presentation modifiers on a Section
/// in a Form are attached to its lazily hosted rows.
struct GitProviderAccountsPresentation {
    var showingAddAccountSheet = false
    var editingAccount: GitProviderAccount?
    var removingAccount: GitProviderAccount?
}

/// Git provider accounts as a grouped settings section: one row per account with Edit and Remove,
/// matching the AI provider list.
struct GitProviderAccountsSection: View {
    @ObservedObject var controller: GitProviderAccountController
    let isSignedIn: Bool
    let onSignIn: () -> Void
    let onUpgrade: () -> Void
    let multipleAccountAccess: FeatureAccessDecision
    @Binding var presentation: GitProviderAccountsPresentation

    private var accountCreationDecision: GitProviderAccountCreationDecision {
        controller.accountCreationDecision(multipleAccountAccess: multipleAccountAccess)
    }

    var body: some View {
        Section {
            if controller.accounts.isEmpty {
                Text("No accounts connected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } else {
                ForEach(controller.accounts) { account in
                    accountRow(account)
                }
            }

            Button {
                presentation.showingAddAccountSheet = true
            } label: {
                Label("Add Account…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .disabled(controller.isLoading || !accountCreationDecision.isAllowed)
        } header: {
            Text("Providers")
        } footer: {
            footer
        }
    }

    private func accountRow(_ account: GitProviderAccount) -> some View {
        HStack(spacing: 10) {
            GitProviderAccountRow(account: account)

            Button("Edit…") {
                presentation.editingAccount = account
            }

            Button("Remove", systemImage: "minus.circle") {
                presentation.removingAccount = account
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove \(account.username)")
        }
        .contextMenu {
            Button("Edit…") { presentation.editingAccount = account }
            Button("Remove…", role: .destructive) { presentation.removingAccount = account }
        }
        .disabled(controller.isLoading)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect Git provider accounts to use private repositories and pull request workflows. GitHub and GitLab use OAuth or a personal access token, Bitbucket Cloud uses an API token, Azure Repos uses a personal access token per organization, and every provider supports HTTPS or SSH.")

            if let message = GitProviderAccountsPresentationPolicy.accountCreationMessage(
                for: accountCreationDecision
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message)

                    if let actionTitle = GitProviderAccountsPresentationPolicy.accountCreationActionTitle(
                        for: accountCreationDecision,
                        isSignedIn: isSignedIn
                    ) {
                        Button(actionTitle, action: isSignedIn ? onUpgrade : onSignIn)
                            .buttonStyle(.link)
                    }
                }
            }

            if !isSignedIn, accountCreationDecision.isAllowed {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Connections are stored on this Mac.")
                    Button("Sign in to sync", action: onSignIn)
                        .buttonStyle(.link)
                }
            }

            if controller.isLoading, !presentation.showingAddAccountSheet, presentation.editingAccount == nil {
                ProgressView("Updating Git provider accounts...")
                    .controlSize(.small)
            }

            if let errorMessage = controller.errorMessage, !presentation.showingAddAccountSheet, presentation.editingAccount == nil {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension GitProviderAccountController {
    func accountCreationDecision(
        multipleAccountAccess: FeatureAccessDecision
    ) -> GitProviderAccountCreationDecision {
        GitProviderAccountAccessPolicy().creationDecision(
            existingAccountCount: accounts.count,
            multipleAccountAccess: multipleAccountAccess
        )
    }
}

extension View {
    func gitProviderAccountsPresentations(
        controller: GitProviderAccountController,
        multipleAccountAccess: FeatureAccessDecision,
        presentation: Binding<GitProviderAccountsPresentation>
    ) -> some View {
        modifier(GitProviderAccountsPresentationModifier(
            controller: controller,
            multipleAccountAccess: multipleAccountAccess,
            presentation: presentation
        ))
    }
}

private struct GitProviderAccountsPresentationModifier: ViewModifier {
    @ObservedObject var controller: GitProviderAccountController
    let multipleAccountAccess: FeatureAccessDecision
    @Binding var presentation: GitProviderAccountsPresentation

    func body(content: Content) -> some View {
        content
            // A sheet's connection error is about the account it edited or added; once the sheet
            // closes, do not leave it under the list.
            .onChange(of: presentation.showingAddAccountSheet) { _, isShowing in
                if !isShowing { controller.errorMessage = nil }
            }
            .replacingSheet(isPresented: $presentation.showingAddAccountSheet) {
                GitProviderAddAccountSheet(
                    controller: controller,
                    accountCreationDecision: controller.accountCreationDecision(
                        multipleAccountAccess: multipleAccountAccess
                    )
                )
            }
            .replacingSheet(
                item: $presentation.editingAccount,
                onDismiss: { controller.errorMessage = nil }
            ) { account in
                GitProviderAddAccountSheet(controller: controller, editingAccount: account)
            }
            .confirmationDialog(
                "Remove \(presentation.removingAccount?.provider.displayName ?? "Git Provider") Account?",
                isPresented: Binding(
                    get: { presentation.removingAccount != nil },
                    set: { if !$0 { presentation.removingAccount = nil } }
                ),
                presenting: presentation.removingAccount
            ) { account in
                Button("Remove", role: .destructive) {
                    Task { await controller.disconnect(account) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { account in
                Text("This disconnects \(account.provider.displayName) account \(account.username) from Commit+. Local repositories and Git data will not be changed.")
            }
    }
}
