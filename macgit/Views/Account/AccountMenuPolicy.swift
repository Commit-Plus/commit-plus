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

enum AccountMenuAction: Hashable {
    case signIn
    case createAccount
    case manageAccount
    case manageAccountAndSubscription
    case accounts
    case syncLocked
    case syncStatus
    case upgrade
    case signOut
}

enum AccountMenuPolicy {
    static func actions(
        account: AccountSnapshot?,
        entitlement: AccountEntitlement
    ) -> [AccountMenuAction] {
        guard account != nil else {
            return [.signIn, .createAccount, .accounts, .syncLocked, .upgrade]
        }

        return [
            .manageAccount,
            .manageAccountAndSubscription,
            .accounts,
            .syncStatus,
            .signOut,
        ]
    }
}

enum AccountMenuPresentation {
    static func summary(
        account: AccountSnapshot?,
        entitlement: AccountEntitlement,
        cloudFeaturesAvailable: Bool
    ) -> String {
        guard let account else {
            return cloudFeaturesAvailable
                ? "Not signed in"
                : "Cloud accounts unavailable in this build"
        }

        let plan = entitlement.hasProAccess ? "Pro plan" : "Free plan"
        return "\(account.displayLabel) · \(plan)"
    }
}
