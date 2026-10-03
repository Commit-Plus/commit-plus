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

import Foundation

enum GitProviderAccountPresentationAction: Equatable {
    case signIn
    case add
    case edit
    case delete
}

enum GitProviderAddAccountHost: String, CaseIterable, Identifiable {
    case github
    case gitlab
    case bitbucket

    var id: Self { self }
}

enum GitProviderAddAccountAuthType: String, CaseIterable, Identifiable {
    case oauth
    case personalAccessToken

    var id: Self { self }
}

enum GitProviderAddAccountProtocol: String, CaseIterable, Identifiable {
    case https
    case ssh

    var id: Self { self }
}

struct GitProviderAddAccountOption<ID: Equatable>: Equatable {
    var id: ID
    var title: String
    var isEnabled: Bool
}

enum GitProviderAccountsPresentationPolicy {
    static func actions(
        isSignedIn: Bool,
        account: GitProviderAccount?
    ) -> [GitProviderAccountPresentationAction] {
        guard account != nil else {
            return isSignedIn ? [.add] : [.add, .signIn]
        }

        return isSignedIn ? [.edit, .delete] : [.edit, .delete, .signIn]
    }

    static func normalizedSelfHostedGitLabHost(from value: String) -> GitProviderHost? {
        guard let host = GitProviderHost.configured(kind: .gitlab, value: value), host.baseURL != GitProviderHost.gitlabDotCom.baseURL else { return nil }
        return host
    }

    static func accountCreationMessage(
        for decision: GitProviderAccountCreationDecision
    ) -> String? {
        switch decision {
        case .allowed:
            nil
        case .denied(.requiresPro(let freeLimit)):
            "Free includes \(freeLimit) Git provider account."
        case .denied(.featureDisabled):
            "Adding Git provider accounts is currently unavailable."
        }
    }

    static func accountCreationActionTitle(
        for decision: GitProviderAccountCreationDecision,
        isSignedIn: Bool
    ) -> String? {
        guard case .denied(.requiresPro) = decision else { return nil }
        return isSignedIn ? "Upgrade to Pro" : "Sign In to Use Pro"
    }
}

enum GitProviderAddAccountPresentationPolicy {
    static let hostOptions: [GitProviderAddAccountOption<GitProviderAddAccountHost>] = [
        GitProviderAddAccountOption(id: .github, title: "GitHub", isEnabled: true),
        GitProviderAddAccountOption(id: .gitlab, title: "GitLab", isEnabled: true),
        GitProviderAddAccountOption(id: .bitbucket, title: "Bitbucket", isEnabled: true)
    ]

    static func authTypeOptions(
        for host: GitProviderAddAccountHost
    ) -> [GitProviderAddAccountOption<GitProviderAddAccountAuthType>] {
        [
            GitProviderAddAccountOption(id: .oauth, title: "OAuth", isEnabled: host != .bitbucket),
            GitProviderAddAccountOption(
                id: .personalAccessToken,
                title: "API Token",
                isEnabled: host == .bitbucket
            )
        ]
    }

    static func canSelectAuthType(for host: GitProviderAddAccountHost) -> Bool {
        authTypeOptions(for: host).count { $0.isEnabled } > 1
    }

    static let protocolOptions: [GitProviderAddAccountOption<GitProviderAddAccountProtocol>] = [
        GitProviderAddAccountOption(id: .https, title: "HTTPS", isEnabled: true),
        GitProviderAddAccountOption(id: .ssh, title: "SSH", isEnabled: true)
    ]

    static func canConnect(
        host: GitProviderAddAccountHost,
        authType: GitProviderAddAccountAuthType,
        protocol selectedProtocol: GitProviderAddAccountProtocol
    ) -> Bool {
        if selectedProtocol == .ssh {
            return true
        }
        switch host {
        case .github, .gitlab:
            return authType == .oauth
        case .bitbucket:
            return authType == .personalAccessToken
        }
    }

    static func canSave(
        connectedUsername: String,
        protocol selectedProtocol: GitProviderAddAccountProtocol,
        sshKeyPath: String?
    ) -> Bool {
        guard !connectedUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard selectedProtocol == .ssh else {
            return true
        }
        return !(sshKeyPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func usernameDisplayText(for connectedUsername: String) -> String {
        connectedUsername.isEmpty ? "_" : connectedUsername
    }

    static func connectButtonTitle(connectedUsername: String) -> String {
        connectedUsername.isEmpty ? "Connect Account" : "Reconnect"
    }

    static func connectButtonTitle(
        connectedUsername: String,
        protocol selectedProtocol: GitProviderAddAccountProtocol
    ) -> String {
        guard selectedProtocol == .ssh else {
            return connectButtonTitle(connectedUsername: connectedUsername)
        }
        return connectedUsername.isEmpty ? "Test SSH Key" : "Test Again"
    }

    static func host(for account: GitProviderAccount) -> GitProviderAddAccountHost {
        switch account.provider {
        case .github: .github
        case .gitlab: .gitlab
        case .bitbucket: .bitbucket
        }
    }

    static func optionTitle<ID: Equatable>(
        for id: ID,
        in options: [GitProviderAddAccountOption<ID>]
    ) -> String {
        options.first { $0.id == id }?.title ?? ""
    }
}
