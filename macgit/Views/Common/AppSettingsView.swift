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
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject var appState: AppState
    @ObservedObject var accountController: AccountSessionController
    @ObservedObject var featureAccessController: FeatureAccessController
    @ObservedObject var providerAccountController: GitProviderAccountController
    @ObservedObject var aiProviderController: AIProviderController
    @ObservedObject var appUpdateController: AppUpdateController
    @ObservedObject var customActionStore: CustomActionStore
    @Binding private var selectedSection: AppSettingsSection
    @State private var aiProviderDrafts: [AIProviderConfigurationDraft]
    @State private var saveErrorMessage: String?
    @State private var isShowingSaveError = false

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
    }

    var body: some View {
        NavigationSplitView {
            List(AppSettingsSection.allCases, selection: $selectedSection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(section.iconColor)
                }
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                AppSettingsDetailView(
                    section: selectedSection,
                    appState: appState,
                    accountController: accountController,
                    providerAccountController: providerAccountController,
                    aiProviderController: aiProviderController,
                    appUpdateController: appUpdateController,
                    customActionStore: customActionStore,
                    restrictedAIProviderAccess: restrictedAIProviderAccess,
                    aiProviderDrafts: $aiProviderDrafts
                )

                Divider()

                HStack {
                    Spacer()

                    Button("Cancel", action: close)
                        .keyboardShortcut(.cancelAction)

                    Button("Done", action: saveChangesAndDismiss)
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, idealWidth: 920, minHeight: 540, idealHeight: 640)
        .navigationTitle("Settings")
        .background(AppSettingsWindowControls())
        .onReceive(NotificationCenter.default.publisher(for: .showAppSettings)) { notification in
            guard let rawSection = notification.userInfo?["section"] as? String,
                  let section = AppSettingsSection(rawValue: rawSection) else { return }
            selectedSection = section
            openWindow(id: "settings")
        }
        .alert("Couldn’t Save Settings", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func saveChangesAndDismiss() {
        do {
            try aiProviderController.applyProviderChanges(
                aiProviderDrafts,
                restrictedProviderAccess: restrictedAIProviderAccess
            )
            close()
            Task { await aiProviderController.refreshAvailability() }
        } catch {
            saveErrorMessage = error.localizedDescription
            isShowingSaveError = true
        }
    }

    private func close() {
        dismissWindow(id: "settings")
    }

    private var restrictedAIProviderAccess: FeatureAccessDecision {
        featureAccessController.decision(
            for: .aiBringYourOwnKey,
            entitlement: accountController.entitlement
        )
    }
}
