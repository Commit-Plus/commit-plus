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

struct AppSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appState: AppState
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var featureAccessController: FeatureAccessController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @ObservedObject var aiProviderController: AIProviderController
    @ObservedObject var appUpdateController: AppUpdateController
    @ObservedObject var customActionStore: CustomActionStore
    @Binding private var selectedSection: AppSettingsSection
    @State private var aiProviderDrafts: [AIProviderConfigurationDraft]
    @State private var diffAppearanceDraft: DiffAppearanceSettingsDraft
    @State private var diffSyntaxHighlightingDraft: Bool
    @State private var windowReference = AppSettingsWindowReference()

    init(
        appState: AppState,
        accountController: AccountSessionController,
        featureAccessController: FeatureAccessController,
        providerAccountController: GitProviderAccountController,
        aiProviderController: AIProviderController,
        appUpdateController: AppUpdateController,
        customActionStore: CustomActionStore,
        selectedSection: Binding<AppSettingsSection>
    ) {
        self.appState = appState
        self.accountController = accountController
        self.featureAccessController = featureAccessController
        self.providerAccountController = providerAccountController
        self.aiProviderController = aiProviderController
        self.appUpdateController = appUpdateController
        self.customActionStore = customActionStore
        _selectedSection = selectedSection
        _aiProviderDrafts = State(initialValue: aiProviderController.configurationDrafts())
        _diffAppearanceDraft = State(initialValue: DiffAppearanceSettingsStore.shared.draft)
        _diffSyntaxHighlightingDraft = State(
            initialValue: AdvancedSettingsStore.shared.diffSyntaxHighlighting
        )
    }

    var body: some View {
        AppSettingsDetailView(
            section: selectedSection,
            appState: appState,
            accountController: accountController,
            providerAccountController: providerAccountController,
            aiProviderController: aiProviderController,
            appUpdateController: appUpdateController,
            customActionStore: customActionStore,
            restrictedAIProviderAccess: restrictedAIProviderAccess,
            aiProviderDrafts: $aiProviderDrafts,
            diffAppearanceDraft: $diffAppearanceDraft,
            diffSyntaxHighlightingDraft: $diffSyntaxHighlightingDraft
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 900, idealWidth: 920, minHeight: 540, idealHeight: 640)
        .navigationTitle(selectedSection.title)
        .background(AppSettingsWindowControls(windowReference: windowReference))
        .background(AppSettingsToolbar(selection: $selectedSection))
        // Account flows started here (sync conflict, sign-in) pick the key window as their owner.
        .replacingSheet(item: accountSheetPresentation) { sheet in
            Group {
                switch sheet {
                case .authentication(let mode):
                    AuthenticationSheet(controller: accountController, mode: mode, presentedByController: true)
                case .settingsConflict:
                    SettingsSyncConflictSheet(controller: accountController)
                case .deviceLimit:
                    DeviceLimitSheet(controller: accountController)
                }
            }
            .disabled(accountController.isOpeningAccountOnWeb)
            .interactiveDismissDisabled(accountController.isOpeningAccountOnWeb)
        }
        .sheetPresentationScope()
        .onReceive(NotificationCenter.default.publisher(for: .showAppSettings)) { notification in
            guard let rawSection = notification.userInfo?["section"] as? String,
                  let section = AppSettingsSection(rawValue: rawSection) else { return }
            selectedSection = section
            openWindow(id: "settings")
        }
        // Settings apply as they change; reload drafts so a pane never re-applies stale values.
        .onChange(of: selectedSection, initial: true) { _, section in
            switch section {
            case .diff:
                diffAppearanceDraft = DiffAppearanceSettingsStore.shared.draft
                diffSyntaxHighlightingDraft = AdvancedSettingsStore.shared.diffSyntaxHighlighting
            case .aiProviders:
                aiProviderDrafts = aiProviderController.configurationDrafts()
            default:
                break
            }
        }
        .onChange(of: diffAppearanceDraft) { _, _ in applyDiffSettings() }
        .onChange(of: diffSyntaxHighlightingDraft) { _, _ in applyDiffSettings() }
    }

    private func applyDiffSettings() {
        guard diffAppearanceDraft != DiffAppearanceSettingsStore.shared.draft
                || diffSyntaxHighlightingDraft != AdvancedSettingsStore.shared.diffSyntaxHighlighting
        else { return }
        appState.applyLocalDiffSettings(
            appearance: diffAppearanceDraft,
            syntaxHighlighting: diffSyntaxHighlightingDraft
        )
    }

    private var accountSheetPresentation: Binding<AccountSheet?> {
        Binding(
            get: {
                guard let window = windowReference.window,
                      accountController.sheetPresentationWindow === window else { return nil }
                return accountController.presentedSheet
            },
            set: { sheet in
                guard let window = windowReference.window,
                      accountController.sheetPresentationWindow === window else { return }
                accountController.presentedSheet = sheet
            }
        )
    }

    private var restrictedAIProviderAccess: FeatureAccessDecision {
        featureAccessController.decision(
            for: .aiBringYourOwnKey,
            entitlement: accountController.entitlement
        )
    }
}
