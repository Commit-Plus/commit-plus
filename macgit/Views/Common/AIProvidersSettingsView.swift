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

struct AIProvidersSettingsView: View {
    @ObservedObject var controller: AIProviderController
    @ObservedObject var accountController: AccountSessionController
    let restrictedProviderAccess: FeatureAccessDecision
    @Binding var drafts: [AIProviderConfigurationDraft]
    @State private var authenticationMode: AuthenticationMode?
    @State private var isOpeningRestrictedProviderAccess = false
    @State private var saveErrorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Provider") {
                    AIProviderMenu(
                        controller: controller,
                        restrictedProviderAccess: restrictedProviderAccess,
                        showsConfigureAction: false
                    )
                }

                if controller.selectedDescriptor.billing != .commitPlus {
                    LabeledContent("Model") {
                        Text(controller.model(for: controller.selectedDescriptor) ?? "On-device")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Default AI Provider", systemImage: "sparkles")
            } footer: {
                Text("This provider is used for AI features throughout Commit+. It powers commit-message generation, repository chat, AI actions, and conflict resolution.")
            }

            if controller.selectedDescriptor.billing == .commitPlus,
               let usage = controller.managedUsageController {
                CommitPlusAIUsageView(controller: usage)
            }

            ForEach($drafts) { $draft in
                let descriptor = controller.descriptors.first { $0.id == draft.id }
                if let descriptor {
                    CloudAIProviderSettingsSection(
                        descriptor: descriptor,
                        showsConfigurationHeading: draft.id == drafts.first?.id,
                        controller: controller,
                        accountController: accountController,
                        draft: $draft,
                        restrictedProviderAccess: restrictedProviderAccess,
                        isOpeningAccess: isOpeningRestrictedProviderAccess,
                        onAccessAction: presentRestrictedProviderAccess
                    )
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !drafts.isEmpty {
                HStack {
                    Spacer()
                    Button("Revert", action: revert)
                        .disabled(!hasUnsavedChanges)
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!hasUnsavedChanges)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .alert(
            "Couldn’t Save AI Provider Settings",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .navigationTitle("AI Providers")
        .replacingSheet(item: $authenticationMode) { mode in
            AuthenticationSheet(controller: accountController, mode: mode)
        }
        .task(id: controller.availabilityRevision) {
            await controller.refreshAvailability()
        }
    }

    private func presentRestrictedProviderAccess() {
        if accountController.account == nil {
            accountController.errorMessage = nil
            authenticationMode = .signIn
        } else {
            guard !isOpeningRestrictedProviderAccess,
                  accountController.openingWebDestination != .pricing else { return }
            isOpeningRestrictedProviderAccess = true
            Task {
                await accountController.openPricingOnWeb()
                isOpeningRestrictedProviderAccess = false
            }
        }
    }


    private var hasUnsavedChanges: Bool {
        let savedModels = Dictionary(
            controller.configurationDrafts().map { ($0.id, $0.model) },
            uniquingKeysWith: { first, _ in first }
        )
        return drafts.contains { draft in
            !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || draft.shouldRemoveAPIKey
                || draft.model.trimmingCharacters(in: .whitespacesAndNewlines) != savedModels[draft.id]
        }
    }

    private func save() {
        do {
            try controller.applyProviderChanges(drafts, restrictedProviderAccess: restrictedProviderAccess)
            drafts = controller.configurationDrafts()
            Task { await controller.refreshAvailability() }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func revert() {
        drafts = controller.configurationDrafts()
    }
}
