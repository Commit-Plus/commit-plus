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

    var body: some View {
        HStack(spacing: 10) {
            Image(providerAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.username)
                    .lineLimit(1)
                Text(detailDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let statusDescription {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(statusDescription)
                    .accessibilityLabel(statusDescription)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var detailDescription: String {
        var host = account.hostURL.host() ?? account.hostURL.absoluteString
        if account.provider == .azureDevOps {
            // One Azure account per organization; show which one.
            host += account.hostURL.path
        }
        return "\(providerName) · \(host) · \(protocolDescription)"
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
            switch account.provider {
            case .bitbucket: "HTTPS (API Token)"
            case .azureDevOps: "HTTPS (Personal Access Token)"
            case .github, .gitlab: "HTTPS (OAuth)"
            }
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
