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

enum AppSettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case diff
    case git
    case accounts
    case profile
    case integrations
    case notifications
    case customActions
    case aiProviders
    case update
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .diff: "Diff"
        case .git: "Git"
        case .accounts: "Accounts"
        case .profile: "Profile"
        case .integrations: "Integrations"
        case .notifications: "Notifications"
        case .customActions: "Custom Actions"
        case .aiProviders: "AI"
        case .update: "Update"
        case .advanced: "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .diff: "plusminus"
        case .git: "point.3.connected.trianglepath.dotted"
        case .accounts: "person.2.crop.square.stack"
        case .profile: "person.crop.circle"
        case .integrations: "puzzlepiece.extension"
        case .notifications: "bell"
        case .customActions: "terminal"
        case .aiProviders: "sparkles"
        case .update: "arrow.triangle.2.circlepath"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    var detail: String {
        switch self {
        case .general:
            "Configure the default behavior of Commit+."
        case .appearance:
            "Customize how Commit+ looks and presents repository information."
        case .diff:
            "Customize the font and colors used to display code changes."
        case .git:
            "Configure the Git runtime, credentials, SSH keys, and global Git behavior."
        case .accounts:
            "Connect GitHub, GitLab, Bitbucket, and other Git provider accounts."
        case .profile:
            "Manage your Commit+ profile, plan, and settings sync."
        case .integrations:
            "Connect Commit+ with external tools and services."
        case .notifications:
            "Choose which events show macOS notifications."
        case .customActions:
            "Configure reusable repository, file, and commit actions."
        case .aiProviders:
            "Configure AI providers for commit-message generation."
        case .update:
            "View version information and check for Commit+ updates."
        case .advanced:
            "Configure advanced options for troubleshooting and power users."
        }
    }
}

extension Notification.Name {
    static let showAppSettings = Notification.Name("showAppSettings")
}
