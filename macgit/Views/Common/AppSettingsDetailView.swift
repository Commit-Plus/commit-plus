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

struct AppSettingsDetailView: View {
    let section: AppSettingsSection
    @ObservedObject var appState: AppState
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @ObservedObject var aiProviderController: AIProviderController
    @ObservedObject var appUpdateController: AppUpdateController
    @ObservedObject var customActionStore: CustomActionStore
    let restrictedAIProviderAccess: FeatureAccessDecision
    @Binding var aiProviderDrafts: [AIProviderConfigurationDraft]

    var body: some View {
        switch section {
        case .general:
            GeneralSettingsView(appState: appState)
        case .appearance:
            AppearanceSettingsView(appState: appState)
        case .git:
            GitSettingsView()
        case .accounts:
            AccountSettingsView(accountController: accountController)
        case .connections:
            ConnectionsSettingsView(
                accountController: accountController,
                providerAccountController: providerAccountController
            )
        case .integrations:
            IntegrationsSettingsView(appState: appState)
        case .customActions:
            CustomActionsSettingsView(store: customActionStore)
        case .aiProviders:
            AIProvidersSettingsView(
                controller: aiProviderController,
                accountController: accountController,
                restrictedProviderAccess: restrictedAIProviderAccess,
                drafts: $aiProviderDrafts
            )
        case .update:
            UpdateSettingsView(updateController: appUpdateController)
        case .advanced:
            AdvancedSettingsView(
                appState: appState,
                accountController: accountController,
                providerAccountController: providerAccountController
            )
        }
    }
}
