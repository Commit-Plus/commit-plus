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

enum GitProviderAccountCreationDenial: Equatable {
    case requiresPro(freeLimit: Int)
    case featureDisabled
}

enum GitProviderAccountCreationDecision: Equatable {
    case allowed
    case denied(GitProviderAccountCreationDenial)

    var isAllowed: Bool {
        self == .allowed
    }
}

struct GitProviderAccountAccessPolicy {
    static let freeAccountLimit = 1

    func creationDecision(
        existingAccountCount: Int,
        multipleAccountAccess: FeatureAccessDecision
    ) -> GitProviderAccountCreationDecision {
        guard existingAccountCount >= Self.freeAccountLimit else {
            return .allowed
        }

        switch multipleAccountAccess {
        case .allowed:
            return .allowed
        case .denied(.featureDisabled):
            return .denied(.featureDisabled)
        case .denied:
            return .denied(.requiresPro(freeLimit: Self.freeAccountLimit))
        }
    }
}

enum GitProviderAccountAccessError: LocalizedError, Equatable {
    case selfHostedRequiresPro
    case freeAccountLimitReached(limit: Int)
    case featureDisabled

    var errorDescription: String? {
        switch self {
        case .selfHostedRequiresPro:
            "Connecting self-managed Git servers requires an active Pro plan."
        case .freeAccountLimitReached(let limit):
            "Free plan includes \(limit) Git provider account. Upgrade to Pro to add more."
        case .featureDisabled:
            "Adding Git provider accounts is currently unavailable."
        }
    }
}
