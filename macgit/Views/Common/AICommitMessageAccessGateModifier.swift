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

struct AICommitMessageAccessGateModifier: ViewModifier {
    @EnvironmentObject private var accountController: AccountSessionController
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @Binding var isRequested: Bool
    let feature: PlanFeature
    let requiresProAccess: Bool
    let onAuthorized: () -> Void

    @State private var showingLoginRequired = false
    @State private var proUpgradePresentation: ProUpgradePresentation?
    @State private var proUpgradeErrorMessage: String?
    @State private var featureAccessNotice: FeatureAccessNotice?

    func body(content: Content) -> some View {
        content
            .onChange(of: isRequested) { _, requested in
                guard requested else { return }
                isRequested = false
                authorizeRequest()
            }
            .replacingSheet(isPresented: $showingLoginRequired) {
                AICommitMessageLoginRequiredSheet(controller: accountController, feature: feature)
            }
            .replacingSheet(item: $proUpgradePresentation) { presentation in
                ProUpgradeSheet(
                    feature: presentation.feature,
                    isSignedIn: accountController.account != nil,
                    isOpening: accountController.openingWebDestination == .pricing,
                    errorMessage: proUpgradeErrorMessage,
                    onCancel: dismissProUpgradeSheet,
                    onPrimaryAction: performProUpgradePrimaryAction
                )
            }
            .alert(item: $featureAccessNotice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
    }

    private func authorizeRequest() {
        guard requiresProAccess else {
            onAuthorized()
            return
        }

        guard accountController.account != nil else {
            showingLoginRequired = true
            return
        }

        switch featureAccessController.decision(
            for: feature,
            entitlement: accountController.entitlement
        ) {
        case .allowed:
            onAuthorized()
        case .denied(.requiresPro):
            proUpgradeErrorMessage = nil
            proUpgradePresentation = ProUpgradePresentation(feature: feature)
        case .denied(let denial):
            featureAccessNotice = FeatureAccessNotice(feature: feature, denial: denial)
        }
    }

    private func dismissProUpgradeSheet() {
        guard accountController.openingWebDestination != .pricing else { return }
        proUpgradePresentation = nil
        proUpgradeErrorMessage = nil
    }

    private func performProUpgradePrimaryAction() {
        guard accountController.openingWebDestination != .pricing else { return }
        proUpgradeErrorMessage = nil

        guard accountController.account != nil else {
            proUpgradePresentation = nil
            showingLoginRequired = true
            return
        }

        Task {
            await accountController.openPricingOnWeb()
            if let errorMessage = accountController.errorMessage {
                proUpgradeErrorMessage = errorMessage
            } else {
                proUpgradePresentation = nil
            }
        }
    }
}

extension View {
    func aiCommitMessageAccessGate(
        isRequested: Binding<Bool>,
        requiresProAccess: Bool,
        onAuthorized: @escaping () -> Void
    ) -> some View {
        modifier(AICommitMessageAccessGateModifier(
            isRequested: isRequested,
            feature: .aiCommitMessage,
            requiresProAccess: requiresProAccess,
            onAuthorized: onAuthorized
        ))
    }

    func aiConflictResolutionAccessGate(
        isRequested: Binding<Bool>,
        onAuthorized: @escaping () -> Void
    ) -> some View {
        modifier(AICommitMessageAccessGateModifier(
            isRequested: isRequested,
            feature: .aiConflictResolution,
            requiresProAccess: true,
            onAuthorized: onAuthorized
        ))
    }
}
