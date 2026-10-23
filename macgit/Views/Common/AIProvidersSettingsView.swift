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
    @State private var authenticationMode: AuthenticationMode?
    @State private var isOpeningRestrictedProviderAccess = false
    @State private var configuringProviderID: AIProviderID?
    @State private var removingProviderID: AIProviderID?
    @State private var errorMessage: String?

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
                        Text(modelName(for: controller.selectedDescriptor) ?? "On-device")
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

            Section {
                Toggle(isOn: Binding(
                    get: { controller.isThinkingEnabled },
                    set: { controller.setThinkingEnabled($0) }
                )) {
                    Text("Thinking")
                    Text("Let models that support it reason before answering. Responses take longer and use more tokens.")
                }
            } footer: {
                Text("Applies to every provider you configure here. When off, thinking is turned off where the model allows it, or set to its lowest level on models that always think. Apple Intelligence and Commit+ AI are not affected.")
            }

            Section {
                if configuredProviders.isEmpty {
                    Text("No providers configured")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } else {
                    ForEach(configuredProviders) { descriptor in
                        providerRow(descriptor)
                    }
                }

                Menu {
                    ForEach(addableProviders) { descriptor in
                        Button(menuTitle(for: descriptor)) {
                            configuringProviderID = descriptor.id
                        }
                    }
                } label: {
                    Label("Add Provider…", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(addableProviders.isEmpty)
            } header: {
                Text("Providers")
            } footer: {
                Text("Use your own API key with a supported provider, or connect your ChatGPT plan. Credentials are stored in this Mac’s Keychain.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI")
        .replacingSheet(item: configuringDescriptor) { descriptor in
            AIProviderConfigurationSheet(
                descriptor: descriptor,
                controller: controller,
                accountController: accountController,
                restrictedProviderAccess: restrictedProviderAccess,
                isOpeningAccess: isOpeningRestrictedProviderAccess,
                onAccessAction: presentRestrictedProviderAccess
            )
        }
        .confirmationDialog(
            "Remove \(removingDescriptor?.displayName ?? "Provider")?",
            isPresented: Binding(
                get: { removingProviderID != nil },
                set: { if !$0 { removingProviderID = nil } }
            ),
            presenting: removingDescriptor
        ) { descriptor in
            Button("Remove", role: .destructive) { remove(descriptor) }
            Button("Cancel", role: .cancel) {}
        } message: { descriptor in
            if descriptor.billing == .connectedAccount {
                Text("You will be signed out of \(descriptor.displayName), and its sign-in will be deleted from this Mac’s Keychain.")
            } else {
                Text("The \(descriptor.displayName) API key will be deleted from this Mac’s Keychain.")
            }
        }
        .alert(
            "Couldn’t Update AI Provider",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .replacingSheet(item: $authenticationMode) { mode in
            AuthenticationSheet(controller: accountController, mode: mode)
        }
        .task(id: controller.availabilityRevision) {
            await controller.refreshAvailability()
        }
    }

    private func providerRow(_ descriptor: AIProviderDescriptor) -> some View {
        HStack(spacing: 10) {
            AIProviderLogo(descriptor: descriptor, size: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.displayName)
                Text(modelName(for: descriptor) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if case .unavailable(let reason) = controller.availability(for: descriptor.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(reason)
                    .accessibilityLabel(reason)
            }

            Button("Edit…") {
                configuringProviderID = descriptor.id
            }

            Button("Remove", systemImage: "minus.circle") {
                removingProviderID = descriptor.id
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove \(descriptor.displayName)")
        }
        .contextMenu {
            Button("Edit…") { configuringProviderID = descriptor.id }
            Button("Remove…", role: .destructive) { removingProviderID = descriptor.id }
        }
    }

    private func modelName(for descriptor: AIProviderDescriptor) -> String? {
        controller.model(for: descriptor).map {
            AIProviderModelCatalog.displayName(for: $0, provider: descriptor.id)
        }
    }

    /// Personal-key and connected-account providers that can be added or edited here.
    private var personalKeyProviders: [AIProviderDescriptor] {
        controller.descriptors.filter { $0.billing.usesPersonalCredential && $0.isImplemented }
    }

    private var configuredProviders: [AIProviderDescriptor] {
        personalKeyProviders.filter { controller.isAPIKeyConfigured(for: $0.id) }
    }

    private var addableProviders: [AIProviderDescriptor] {
        personalKeyProviders.filter { !controller.isAPIKeyConfigured(for: $0.id) }
    }

    private var removingDescriptor: AIProviderDescriptor? {
        controller.descriptors.first { $0.id == removingProviderID }
    }

    private var configuringDescriptor: Binding<AIProviderDescriptor?> {
        Binding(
            get: { controller.descriptors.first { $0.id == configuringProviderID } },
            set: { configuringProviderID = $0?.id }
        )
    }

    private func menuTitle(for descriptor: AIProviderDescriptor) -> String {
        descriptor.requiresProToConfigureAPIKey && !restrictedProviderAccess.isAllowed
            ? "\(descriptor.displayName) (Pro)"
            : descriptor.displayName
    }

    private func remove(_ descriptor: AIProviderDescriptor) {
        if descriptor.billing == .connectedAccount {
            Task { await controller.disconnectChatGPT() }
            return
        }
        do {
            try controller.removeAPIKey(for: descriptor.id)
            Task { await controller.refreshAvailability() }
        } catch {
            errorMessage = error.localizedDescription
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
}
