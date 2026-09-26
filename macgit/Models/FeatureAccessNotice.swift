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

struct FeatureAccessNotice: Identifiable, Equatable {
    let feature: PlanFeature
    let denial: FeatureAccessDenial

    var id: String {
        "\(feature.rawValue)-\(String(describing: denial))"
    }

    var title: String {
        switch denial {
        case .requiresPro:
            "Commit+ Pro Required"
        case .repositoryVisibilityUnavailable:
            "Repository Access Unavailable"
        case .featureDisabled:
            "Feature Unavailable"
        case .repositoryScopeNotAllowed:
            "Repository Not Supported"
        }
    }

    var message: String {
        switch denial {
        case .requiresPro:
            "\(feature.displayName) is not available for this repository on the Free plan. Upgrade to Commit+ Pro to continue."
        case .repositoryVisibilityUnavailable:
            "Commit+ could not verify whether this repository is public or private. Check the network and provider connection, then try again."
        case .featureDisabled:
            "\(feature.displayName) is currently disabled by the release policy."
        case .repositoryScopeNotAllowed:
            "\(feature.displayName) is not enabled for this repository type."
        }
    }

    func title(isSignedIn: Bool) -> String {
        if denial == .requiresPro, !isSignedIn {
            return "Sign In Required"
        }
        return title
    }

    func message(isSignedIn: Bool) -> String {
        guard denial == .requiresPro else { return message }
        guard isSignedIn else {
            return "Sign in to Commit+ to use \(feature.displayName.lowercased())."
        }
        guard feature == .privateRepositories else { return message }
        return "Upgrade to Commit+ Pro from $3.25/month (billed annually) to use private repositories."
    }
}

extension PlanFeature {
    var displayName: String {
        switch self {
        case .privateRepositories:
            "Private repositories"
        case .pullRequests:
            "Pull Requests"
        case .gitLFS:
            "Git LFS"
        case .gitFlow:
            "Git Flow"
        case .aiCommitMessage:
            "AI commit messages"
        case .repositoryChat:
            "Repository chat"
        case .repositoryAIActions:
            "Repository AI workflows"
        case .aiConflictResolution:
            "AI conflict resolution"
        case .aiBringYourOwnKey:
            "Additional AI providers"
        case .multipleProviderAccounts:
            "Multiple Git provider accounts"
        }
    }
}
