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

import AppKit
import SwiftUI

struct GitProviderAccountsSection: View {
    @ObservedObject var controller: GitProviderAccountController
    let isSignedIn: Bool
    let onSignIn: () -> Void
    let onUpgrade: () -> Void
    let multipleAccountAccess: FeatureAccessDecision
    var showsTitle = true
    @State private var connectionTask: Task<Void, Never>?
    @State private var showingAddAccountSheet = false
    @State private var editingAccount: GitProviderAccount?

    private var accountCreationDecision: GitProviderAccountCreationDecision {
        GitProviderAccountAccessPolicy().creationDecision(
            existingAccountCount: controller.accounts.count,
            multipleAccountAccess: multipleAccountAccess
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text("Git Provider Accounts")
                    .font(.headline)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if controller.accounts.isEmpty {
                Text("Connect a Git provider account to use private repositories and pull request workflows.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    ForEach(controller.accounts) { account in
                        GitProviderAccountRow(
                            account: account,
                            edit: { editingAccount = account },
                            delete: { Task { await controller.disconnect(account) } }
                        )
                    }
                }
            }

            Button("Add", systemImage: "plus") {
                showingAddAccountSheet = true
            }
            .disabled(controller.isLoading || !accountCreationDecision.isAllowed)

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
                        Button(actionTitle, action: isSignedIn ? onUpgrade : onSignIn)
                            .buttonStyle(.link)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if !isSignedIn, accountCreationDecision.isAllowed {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Connections are stored on this Mac.")
                        .foregroundStyle(.secondary)

                    Button("Sign in to sync", action: onSignIn)
                        .buttonStyle(.link)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if let authorization = controller.pendingDeviceAuthorization {
                GitProviderDeviceAuthorizationView(
                    authorization: authorization,
                    openVerification: controller.openPendingDeviceVerification,
                    copyToPasteboard: copyToPasteboard,
                    cancel: cancelConnection
                )
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear(perform: cancelConnection)
        .replacingSheet(isPresented: $showingAddAccountSheet) {
            GitProviderAddAccountSheet(
                controller: controller,
                accountCreationDecision: accountCreationDecision
            )
        }
        .replacingSheet(item: $editingAccount) { account in
            GitProviderAddAccountSheet(
                controller: controller,
                editingAccount: account,
                accountCreationDecision: .allowed
            )
        }
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

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
