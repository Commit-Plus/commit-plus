// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Adds or edits one personal-key AI provider: its API key and model.
struct AIProviderConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let descriptor: AIProviderDescriptor
    @ObservedObject var controller: AIProviderController
    @ObservedObject var accountController: AccountSessionController
    let restrictedProviderAccess: FeatureAccessDecision
    let isOpeningAccess: Bool
    let onAccessAction: () -> Void
    @State private var draft: AIProviderConfigurationDraft
    @State private var saveErrorMessage: String?

    init(
        descriptor: AIProviderDescriptor,
        controller: AIProviderController,
        accountController: AccountSessionController,
        restrictedProviderAccess: FeatureAccessDecision,
        isOpeningAccess: Bool,
        onAccessAction: @escaping () -> Void
    ) {
        self.descriptor = descriptor
        self.controller = controller
        self.accountController = accountController
        self.restrictedProviderAccess = restrictedProviderAccess
        self.isOpeningAccess = isOpeningAccess
        self.onAccessAction = onAccessAction
        _draft = State(initialValue: AIProviderConfigurationDraft(
            id: descriptor.id,
            model: controller.model(for: descriptor) ?? ""
        ))
    }

    private var isConfigured: Bool {
        controller.isAPIKeyConfigured(for: descriptor.id)
    }

    private var hasPendingKey: Bool {
        !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canConfigureKey: Bool {
        !descriptor.requiresProToConfigureAPIKey || restrictedProviderAccess.isAllowed
    }

    private var canConfigureModel: Bool {
        canConfigureKey || isConfigured
    }

    private var normalizedModel: String {
        draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUsingDefaultModel: Bool {
        normalizedModel == descriptor.defaultModel
    }

    private var hasModelChange: Bool {
        normalizedModel != (controller.model(for: descriptor) ?? "")
    }

    private var canSave: Bool {
        guard canConfigureModel else { return false }
        if !isConfigured { return hasPendingKey }
        return hasPendingKey || hasModelChange
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AIProviderLogo(descriptor: descriptor, size: 22)
                Text(isConfigured ? "Edit \(descriptor.displayName)" : "Add \(descriptor.displayName)")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Form {
                Section {
                    if canConfigureKey {
                        LabeledContent("API Key") {
                            SecureField(
                                "",
                                text: $draft.apiKey,
                                prompt: Text(isConfigured ? "Enter a replacement API key" : "Enter API key")
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                            .accessibilityLabel("\(descriptor.displayName) API key")
                        }
                    }

                    HStack {
                        Label(statusText, systemImage: statusImage)
                            .foregroundStyle(statusStyle)

                        Spacer()

                        if !canConfigureKey, restrictedProviderAccess == .denied(.requiresPro) {
                            Button(accessActionTitle, action: onAccessAction)
                                .disabled(
                                    isOpeningAccess
                                        || accountController.openingWebDestination == .pricing
                                )
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text(accountFooterText)
                }

                Section {
                    LabeledContent("Model ID") {
                        TextField("", text: $draft.model, prompt: Text(descriptor.defaultModel ?? ""))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                            .disabled(!canConfigureModel)
                            .accessibilityLabel("\(descriptor.displayName) model ID")
                    }

                    if canConfigureModel, !isUsingDefaultModel {
                        Button("Reset to Default Model") {
                            draft.model = descriptor.defaultModel ?? ""
                        }
                        .buttonStyle(.link)
                    }
                } header: {
                    Text("Model")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enter a model ID supported by this provider’s API.")

                        if descriptor.id == .openRouter {
                            Text("Do not use openrouter/free.")
                                .bold()
                            + Text(" The Free Models Router can select different models that return incompatible responses.")
                        }
                    }
                }

                if let saveErrorMessage {
                    Text(saveErrorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 540, height: 460)
    }

    private var statusText: String {
        if hasPendingKey {
            isConfigured ? "Replacement ready to save" : "Ready to save"
        } else if !canConfigureKey {
            if isConfigured {
                "Existing key in Keychain"
            } else {
                restrictedProviderAccess == .denied(.requiresPro)
                    ? "Commit+ Pro required to add this provider"
                    : "Provider configuration is currently unavailable"
            }
        } else {
            isConfigured ? "Configured in Keychain" : "API key required"
        }
    }

    private var statusImage: String {
        hasPendingKey || isConfigured ? "checkmark.circle.fill" : "key"
    }

    private var statusStyle: Color {
        hasPendingKey || isConfigured ? .green : .secondary
    }

    private var accountFooterText: String {
        if !canConfigureKey, isConfigured {
            return "This existing key remains available for AI generation. You can change its model or remove it, but replacing it requires Commit+ Pro."
        }
        if !canConfigureKey {
            return "OpenAI and Gemini keys are available on the Free plan. Commit+ Pro unlocks Claude, DeepSeek, OpenRouter, and additional AI providers."
        }
        return "API keys are stored in this Mac’s Keychain and are never synced."
    }

    private var accessActionTitle: String {
        if isOpeningAccess || accountController.openingWebDestination == .pricing {
            return "Opening…"
        }
        return accountController.account == nil ? "Sign In" : "View Pro"
    }

    private func save() {
        do {
            try controller.applyProviderChanges([draft], restrictedProviderAccess: restrictedProviderAccess)
            Task { await controller.refreshAvailability() }
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

struct AIProviderLogo: View {
    let descriptor: AIProviderDescriptor
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let logoAssetName = descriptor.logoAssetName {
                Image(logoAssetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: descriptor.systemImage)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
