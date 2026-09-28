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

struct ManageAccountSheet: View {
    @ObservedObject var controller: AccountSessionController

    var body: some View {
        VStack(alignment: .leading) {
            Text("Profile")
                .font(.title2)
                .bold()

            if let account = controller.account {
                Form {
                    LabeledContent("Account", value: account.displayLabel)
                    LabeledContent("Sign-in methods", value: providerSummary(for: account))
                    LabeledContent("Current plan") {
                        Label(
                            controller.entitlement.planDisplayName,
                            systemImage: controller.entitlement.plan == .pro ? "star.fill" : "person"
                        )
                    }
                    if controller.entitlement.plan == .pro {
                        LabeledContent(
                            "Billing status",
                            value: controller.entitlement.billingStatusDisplayName
                        )
                        if let currentPeriodEnd = controller.entitlement.currentPeriodEnd {
                            LabeledContent(
                                controller.entitlement.cancelAtPeriodEnd ? "Access until" : "Renews",
                                value: currentPeriodEnd.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                    }
                    LabeledContent("Sync Settings") {
                        syncSettingsControl
                    }
                    LabeledContent("Git Provider Accounts") {
                        Button("Manage Connections...", action: controller.presentConnections)
                    }
                    HStack {
                        Spacer()

                        if controller.isRefreshingProfile {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Refreshing profile")
                        }

                        Button("Refresh", systemImage: "arrow.clockwise", action: refreshProfile)
                            .disabled(controller.account == nil || controller.isRefreshingProfile)
                            .help("Reload profile and subscription information")

                        Button(
                            "Sign Out",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            role: .destructive,
                            action: controller.signOut
                        )
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    if controller.isUsingCachedEntitlement,
                       let updatedAt = controller.entitlementLastUpdatedAt {
                        LabeledContent("Cloud status") {
                            Text("Saved locally · Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                    } else if let entitlementError = controller.entitlementError {
                        LabeledContent("Cloud status", value: entitlementError)
                    }
                }
                .formStyle(.grouped)

                Button(action: openAccountOnWeb) {
                    Label {
                        Text("Manage Account & Subscription")
                            .underline()
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(controller.isOpeningAccountOnWeb)
                .padding(.horizontal, 20)

                if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let settingsSyncError = controller.settingsSyncError {
                    Text(settingsSyncError)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ContentUnavailableView(
                    "Not Signed In",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("Sign in to manage your Commit+ account.")
                )
            }

            Spacer(minLength: 20)

            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 440, minHeight: 360)
    }

    @ViewBuilder
    private var syncSettingsControl: some View {
        HStack(spacing: 8) {
            Toggle(
                "Sync Settings",
                isOn: Binding(
                    get: { controller.settingsSyncEnabled },
                    set: controller.setSettingsSyncEnabled
                )
            )
            .labelsHidden()

            Text(controller.settingsSyncDisplayText)
                .foregroundStyle(.secondary)
        }
    }

    private func providerSummary(for account: AccountSnapshot) -> String {
        let names = account.providerIDs.map { providerID in
            switch providerID {
            case "password": "Email & Password"
            case "google.com": "Google"
            default: providerID
            }
        }
        return names.isEmpty ? "Unknown" : names.joined(separator: ", ")
    }

    private func dismiss() {
        controller.presentedSheet = nil
    }

    private func refreshProfile() {
        Task { await controller.refreshProfile() }
    }

    private func openAccountOnWeb() {
        Task { await controller.openAccountOnWeb() }
    }

}
