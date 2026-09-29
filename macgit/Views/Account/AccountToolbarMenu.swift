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

struct AccountToolbarMenu: View {
    @ObservedObject var controller: AccountSessionController

    var body: some View {
        Menu {
            AccountMenuContent(controller: controller)
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
        .help("Commit+ Account")
    }
}

struct AccountMenuContent: View {
    @ObservedObject var controller: AccountSessionController

    private var actions: [AccountMenuAction] {
        AccountMenuPolicy.actions(
            account: controller.account,
            entitlement: controller.entitlement
        )
    }

    var body: some View {
        Text(summary)
        if let email = accountEmail {
            Text(email)
        }

        ForEach(actions, id: \.self) { action in
            if action == .upgrade || action == .signOut {
                Divider()
            }

            switch action {
            case .signIn:
                Button("Sign In...", action: presentSignIn)
                    .disabled(!controller.cloudFeaturesAvailable)
            case .createAccount:
                Button("Create Account...", action: presentCreateAccount)
                    .disabled(!controller.cloudFeaturesAvailable)
            case .manageAccount:
                Button("Profile...", action: controller.presentManageAccount)
            case .manageAccountAndSubscription:
                Button("Manage Account & Subscription") {
                    Task { await controller.openAccountOnWeb() }
                }
                .disabled(controller.isOpeningAccountOnWeb)
            case .connections:
                Button("Connections...", action: controller.presentConnections)
            case .syncLocked:
                Button("Sync Settings · Sign In Required") {}
                    .disabled(true)
            case .syncStatus:
                Toggle(
                    "Sync Settings · \(controller.settingsSyncDisplayText)",
                    isOn: Binding(
                        get: { controller.settingsSyncEnabled },
                        set: controller.setSettingsSyncEnabled
                    )
                )
            case .upgrade:
                if controller.account == nil {
                    Button("Upgrade to Pro...", action: presentSignIn)
                        .disabled(!controller.cloudFeaturesAvailable)
                } else {
                    Button("Upgrade to Pro · Coming later") {}
                        .disabled(true)
                }
            case .signOut:
                Button("Sign Out", action: controller.signOut)
            }
        }
    }

    private var summary: String {
        AccountMenuPresentation.summary(
            account: controller.account,
            entitlement: controller.entitlement,
            cloudFeaturesAvailable: controller.cloudFeaturesAvailable
        )
    }

    private var accountEmail: String? {
        guard let account = controller.account,
              let email = account.email,
              email != account.displayLabel else { return nil }
        return email
    }

    private func presentSignIn() {
        controller.presentAuthentication(.signIn)
    }

    private func presentCreateAccount() {
        controller.presentAuthentication(.createAccount)
    }
}
