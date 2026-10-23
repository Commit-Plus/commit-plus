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

struct GitProviderAccountsSection: View {
    @ObservedObject var controller: GitProviderAccountController
    let isSignedIn: Bool
    let onSignIn: () -> Void
    let onUpgrade: () -> Void
    let multipleAccountAccess: FeatureAccessDecision
    @State private var connectionTask: Task<Void, Never>?
    @State private var showingAddAccountSheet = false
    @State private var selectedAccountID: GitProviderAccount.ID?
    @State private var removingAccount: GitProviderAccount?
    @State private var saveAction: GitProviderAccountSaveAction?

    private var accountCreationDecision: GitProviderAccountCreationDecision {
        GitProviderAccountAccessPolicy().creationDecision(
            existingAccountCount: controller.accounts.count,
            multipleAccountAccess: multipleAccountAccess
        )
    }

    private var selectedAccount: GitProviderAccount? {
        controller.accounts.first { $0.id == selectedAccountID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Git provider accounts to use private repositories and pull request workflows. GitHub and GitLab use OAuth or a personal access token, Bitbucket Cloud uses an API token, and every provider supports HTTPS or SSH.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                accountList
                    .frame(width: Self.listWidth)

                detailPanel
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 16) {
                ControlGroup {
                    Button("Add Account", systemImage: "plus") {
                        showingAddAccountSheet = true
                    }
                    .disabled(controller.isLoading || !accountCreationDecision.isAllowed)
                    .help("Add a Git provider account")

                    Button("Remove Account", systemImage: "minus") {
                        removingAccount = selectedAccount
                    }
                    .disabled(selectedAccount == nil || controller.isLoading)
                    .help("Remove the selected account")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
                .frame(width: Self.listWidth, alignment: .leading)

                if let selectedAccount, let saveAction {
                    Button("Need help logging into your account?", action: saveAction.openHelp)
                        .buttonStyle(.link)

                    Spacer()

                    Button("Save", action: saveAction.save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!saveAction.canSave || controller.isLoading)
                        .help("Save connection settings for \(selectedAccount.username)")
                } else {
                    Spacer()
                }
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear(perform: cancelConnection)
        .onChange(of: controller.accounts.map(\.id), initial: true) { _, ids in
            if let selectedAccountID, ids.contains(selectedAccountID) { return }
            selectedAccountID = ids.first
        }
        // The sheet's connection error is about the account being added; once the sheet
        // closes, do not leave it under the selected account's editor.
        .onChange(of: showingAddAccountSheet) { _, isShowing in
            if !isShowing { controller.errorMessage = nil }
        }
        .replacingSheet(isPresented: $showingAddAccountSheet) {
            GitProviderAddAccountSheet(
                controller: controller,
                accountCreationDecision: accountCreationDecision
            )
        }
        .alert(
            "Remove Git Provider Account?",
            isPresented: Binding(
                get: { removingAccount != nil },
                set: { if !$0 { removingAccount = nil } }
            ),
            presenting: removingAccount
        ) { account in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await controller.disconnect(account) }
            }
        } message: { account in
            Text("This disconnects \(account.provider.displayName) account \(account.username) from Commit+. Local repositories and Git data will not be changed.")
        }
    }

    private static let listWidth: CGFloat = 240

    private var accountList: some View {
        List(controller.accounts, selection: $selectedAccountID) { account in
            GitProviderAccountRow(account: account)
                .tag(account.id)
        }
        .settingsTableStyle()
        .contextMenu(forSelectionType: GitProviderAccount.ID.self) { ids in
            if let account = account(for: ids) {
                Button("Remove…", role: .destructive) { removingAccount = account }
                    .disabled(controller.isLoading)
            }
        }
        .onDeleteCommand {
            guard !controller.isLoading else { return }
            removingAccount = selectedAccount
        }
        .overlay {
            if controller.accounts.isEmpty {
                Text("No Accounts")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var detailPanel: some View {
        Group {
            if let selectedAccount {
                GitProviderAddAccountSheet(
                    controller: controller,
                    editingAccount: selectedAccount,
                    accountCreationDecision: .allowed,
                    presentation: .inline(saveAction: $saveAction),
                    showsControllerActivity: !showingAddAccountSheet
                )
                // Reset the editor's draft whenever a different account is selected.
                .id(selectedAccount.id)
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Select an account to edit its connection, or add a new one.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailPanelStyle()
    }

    @ViewBuilder
    private var footer: some View {
        if let message = GitProviderAccountsPresentationPolicy.accountCreationMessage(
            for: accountCreationDecision
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message)
                    .foregroundStyle(.secondary)

                if let actionTitle = GitProviderAccountsPresentationPolicy.accountCreationActionTitle(
                    for: accountCreationDecision,
                    isSignedIn: isSignedIn
                ) {
                    Spacer(minLength: 0)
                    Button(actionTitle, action: isSignedIn ? onUpgrade : onSignIn)
                        .buttonStyle(.link)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }

        if !isSignedIn, accountCreationDecision.isAllowed {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Connections are stored on this Mac.")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button("Sign in to sync", action: onSignIn)
                    .buttonStyle(.link)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }

        // The inline editor shows progress and errors for the selected account.
        if selectedAccount == nil {
            if controller.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Updating Git provider accounts...")
                        .controlSize(.small)
                    Spacer()
                }
            }

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func account(for ids: Set<GitProviderAccount.ID>) -> GitProviderAccount? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return controller.accounts.first { $0.id == id }
    }

    private func startConnection(_ operation: @escaping @MainActor () async -> Void) {
        connectionTask?.cancel()
        connectionTask = Task { @MainActor in
            await operation()
            connectionTask = nil
        }
    }

    private func cancelConnection() {
        connectionTask?.cancel()
        connectionTask = nil
    }
}
