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

struct PendingGitProviderAccountSelection: Identifiable {
    let id = UUID()
    let remoteName: String
    let identity: GitRemoteIdentity
    let accounts: [GitProviderAccount]
}

struct GitProviderAccountSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selection: PendingGitProviderAccountSelection
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var selectedAccountID = ""
    @State private var didComplete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Git Provider Account")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose the account to use for \(selection.remoteName). Commit+ will remember this choice for \(selection.identity.canonicalHTTPSURL.absoluteString).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                Picker("Account", selection: $selectedAccountID) {
                    ForEach(selection.accounts) { account in
                        Text(accountDisplayName(account)).tag(account.id)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 80, maxHeight: 320)

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel", role: .cancel) {
                    complete(with: nil)
                }
                .keyboardShortcut(.cancelAction)

                Button("Use Account") {
                    complete(with: selectedAccountID)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(selectedAccountID.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 460, idealWidth: 500, maxWidth: 540)
        .frame(minHeight: 240, idealHeight: 360, maxHeight: 560)
        .onDisappear {
            if !didComplete {
                onCancel()
            }
        }
    }

    private func complete(with accountID: String?) {
        guard !didComplete else { return }
        didComplete = true
        dismiss()
        if let accountID, !accountID.isEmpty {
            onSelect(accountID)
        } else {
            onCancel()
        }
    }

    private func accountDisplayName(_ account: GitProviderAccount) -> String {
        let host = account.hostURL.host(percentEncoded: false) ?? account.hostURL.absoluteString
        return "\(account.provider.displayName) · \(account.username) · \(host)"
    }
}
