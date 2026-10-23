// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Adds or edits one personal AI provider: its API key (or ChatGPT sign-in) and model.
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
    @State private var isUsingCustomModel: Bool
    @State private var isConfirmingDisconnect = false
    @State private var didCopySignInLink = false

    private static let customModelTag = "\u{0}custom"

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
        let model = controller.model(for: descriptor) ?? ""
        _draft = State(initialValue: AIProviderConfigurationDraft(id: descriptor.id, model: model))
        let suggestions = AIProviderModelCatalog.suggestions(for: descriptor.id)
        _isUsingCustomModel = State(initialValue: !suggestions.contains { $0.id == model })
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { isUsingCustomModel ? Self.customModelTag : normalizedModel },
            set: { tag in
                if tag == Self.customModelTag {
                    isUsingCustomModel = true
                } else {
                    isUsingCustomModel = false
                    draft.model = tag
                }
            }
        )
    }

    private var isConfigured: Bool {
        controller.isAPIKeyConfigured(for: descriptor.id)
    }

    private var isConnectedAccount: Bool {
        descriptor.billing == .connectedAccount
    }

    private var modelGroups: [(group: String, options: [AIProviderModelOption])] {
        if isConnectedAccount, !controller.chatGPTModels.isEmpty {
            return [("Available Models", controller.chatGPTModels)]
        }
        return AIProviderModelCatalog.groupedSuggestions(for: descriptor.id)
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
        if isConnectedAccount { return isConfigured }
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
                    if isConnectedAccount {
                        connectedAccountContent
                    } else if canConfigureKey {
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

                    if !isConnectedAccount || !canConfigureKey {
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
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text(accountFooterText)
                }

                Section {
                    let groups = modelGroups
                    if !groups.isEmpty {
                        Picker("Model", selection: modelSelection) {
                            ForEach(groups, id: \.group) { group in
                                Section(group.group) {
                                    ForEach(group.options) { option in
                                        Text(option.name).tag(option.id)
                                    }
                                }
                            }
                            Divider()
                            Text("Other…").tag(Self.customModelTag)
                        }
                        .disabled(!canConfigureModel)
                    }

                    if groups.isEmpty || isUsingCustomModel {
                        LabeledContent("Model ID") {
                            TextField("", text: $draft.model, prompt: Text(descriptor.defaultModel ?? ""))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 300)
                                .disabled(!canConfigureModel)
                                .accessibilityLabel("\(descriptor.displayName) model ID")
                        }
                    } else {
                        LabeledContent("Model ID") {
                            Text(normalizedModel)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    if canConfigureModel, !isUsingDefaultModel {
                        Button("Reset to Default Model") {
                            draft.model = descriptor.defaultModel ?? ""
                            isUsingCustomModel = !modelGroups.flatMap(\.options)
                                .contains { $0.id == draft.model }
                        }
                        .buttonStyle(.link)
                    }
                } header: {
                    Text("Model")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose a suggested model, or choose Other… to enter any model ID this provider’s API supports.")

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
        .task(id: controller.chatGPTAccount) {
            guard isConnectedAccount else { return }
            guard isConfigured else {
                await controller.refreshChatGPTReturningAccount()
                return
            }
            await controller.refreshChatGPTModels()
            isUsingCustomModel = !modelGroups.flatMap(\.options).contains { $0.id == normalizedModel }
        }
        .onDisappear {
            if isConnectedAccount { controller.cancelChatGPTSignIn() }
        }
        .confirmationDialog(
            "Disconnect \(descriptor.displayName)?",
            isPresented: $isConfirmingDisconnect
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await controller.disconnectChatGPT() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be signed out of \(descriptor.displayName), and its sign-in will be deleted from this Mac’s Keychain.")
        }
    }

    @ViewBuilder
    private var connectedAccountContent: some View {
        if isConfigured {
            LabeledContent("Account") {
                Text(controller.chatGPTAccount?.email ?? "Connected")
                    .textSelection(.enabled)
            }
            HStack {
                Label("Uses your ChatGPT plan", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Disconnect…") { isConfirmingDisconnect = true }
            }
        } else if canConfigureKey {
            if controller.chatGPTSignInState == .waitingForBrowser {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finish signing in in your browser…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { controller.cancelChatGPTSignIn() }
                }
                if let url = controller.chatGPTAuthorizationURL {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wrong browser profile? Copy this link and open it in the right one.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(url.absoluteString)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer()
                            Button(didCopySignInLink ? "Copied" : "Copy Link", systemImage: didCopySignInLink ? "checkmark" : "doc.on.doc") {
                                controller.copyChatGPTAuthorizationURL()
                                didCopySignInLink = true
                            }
                        }
                    }
                    .task(id: didCopySignInLink) {
                        guard didCopySignInLink else { return }
                        try? await Task.sleep(for: .seconds(2))
                        didCopySignInLink = false
                    }
                }
            } else {
                HStack {
                    Text("Sign in to use your ChatGPT Plus or Pro plan instead of an API key.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Continue with ChatGPT") {
                        controller.signInToChatGPT(restrictedProviderAccess: restrictedProviderAccess)
                    }
                }
                if let returning = controller.chatGPTReturningAccount {
                    HStack {
                        Text(returning.email.map { "Continues as \($0)." } ?? "Continues with the previously registered account.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Use Another Account") {
                            controller.signInToChatGPT(
                                restrictedProviderAccess: restrictedProviderAccess,
                                newAccount: true
                            )
                        }
                    }
                }
            }
        }
        if let message = controller.chatGPTSignInErrorMessage, !isConfigured {
            Text(message)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        if hasPendingKey {
            isConfigured ? "Replacement ready to save" : "Ready to save"
        } else if !canConfigureKey {
            if isConfigured {
                isConnectedAccount ? "Connected" : "Existing key in Keychain"
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
        if isConnectedAccount {
            if !canConfigureKey, isConfigured {
                return "This ChatGPT connection requires Commit+ Pro to use. You can still disconnect it."
            }
            return "Uses your ChatGPT plan allowance, never API billing. Sign-in tokens are stored in this Mac’s Keychain and are never synced."
        }
        if !canConfigureKey, isConfigured {
            return "This existing key remains available for AI generation. You can change its model or remove it, but replacing it requires Commit+ Pro."
        }
        if !canConfigureKey {
            return "OpenAI and Gemini keys are available on the Free plan. Commit+ Pro unlocks ChatGPT sign-in, Claude, DeepSeek, OpenRouter, Groq, and additional AI providers."
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
