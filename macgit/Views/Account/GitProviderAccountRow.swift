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

struct GitProviderAccountRow: View {
    let account: GitProviderAccount
    let edit: () -> Void
    let delete: () -> Void
    @State private var confirmsDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(providerAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(providerName)
                        .font(.headline)
                        .fontWeight(.semibold)

                    Spacer()

                    HStack(spacing: 8) {
                        Button("Edit", systemImage: "pencil", action: edit)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Edit account")

                        Button("Delete", systemImage: "trash", role: .destructive) {
                            confirmsDelete = true
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Delete account")
                    }
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Account")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(account.username)
                    }

                    GridRow {
                        Text("Host")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(account.hostURL.host() ?? account.hostURL.absoluteString)
                    }

                    GridRow {
                        Text("Protocol")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(protocolDescription)
                    }

                    if let statusDescription {
                        GridRow {
                            Text("Status")
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Label(statusDescription, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .alert("Delete Git Provider Account?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("This disconnects \(providerName) account \(account.username) from Commit+. Local repositories and Git data will not be changed.")
        }
    }

    private var providerAssetName: String {
        account.provider.rawValue
    }

    private var providerName: String {
        account.provider.displayName
    }

    private var protocolDescription: String {
        switch account.transportProtocol {
        case .https:
            account.provider == .bitbucket ? "HTTPS (API Token)" : "HTTPS (OAuth)"
        case .ssh:
            "SSH"
        }
    }

    private var statusDescription: String? {
        switch account.tokenStatus {
        case .valid:
            nil
        case .expired, .revoked, .reauthorizationRequired:
            "Reconnect required"
        case .unavailableOnThisDevice:
            "Credentials unavailable on this Mac"
        }
    }

}
