// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Adds or edits one personal AI provider: its API key (or ChatGPT/GitHub Copilot sign-in) and model.
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
    @State private var modelFallbackMessage: String?

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
        // Copilot offers only the models its account lists, so it has no custom model ID.
        _isUsingCustomModel = State(
            initialValue: !controller.usesDeviceCodeSignIn(descriptor.id) && !suggestions.contains { $0.id == model }
        )
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

    private var usesDeviceCode: Bool {
        controller.usesDeviceCodeSignIn(descriptor.id)
    }

    private var modelGroups: [(group: String, options: [AIProviderModelOption])] {
        let accountModels = controller.models(forConnectedAccount: descriptor.id)
        if isConnectedAccount, !accountModels.isEmpty {
            return [("Available Models", accountModels)]
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
                if descriptor.isUnofficial {
                    UnofficialProviderBadge()
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Form {
                Section {
                    if usesDeviceCode {
                        deviceCodeAccountContent
                    } else if isConnectedAccount {
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
                            if !usesDeviceCode {
                                Divider()
                                Text("Other…").tag(Self.customModelTag)
                            }
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

                    if let modelFallbackMessage {
                        Label(modelFallbackMessage, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if canConfigureModel, !isUsingDefaultModel, !usesDeviceCode {
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
                        if usesDeviceCode {
                            Text("Lists the chat models your Copilot plan includes. Auto lets GitHub choose the model.")
                        } else {
                            Text("Choose a suggested model, or choose Other… to enter any model ID this provider’s API supports.")
                        }

                        if descriptor.id == .openRouter {
                            Text("Do not use openrouter/free.")
                                .bold()
                            + Text(" The Free Models Router can select different models that return incompatible responses.")
                        }
                    }
                }

                if usesDeviceCode {
                    Section {
                        Toggle(
                            "Send usage telemetry to GitHub",
                            isOn: Binding(
                                get: { controller.isProviderTelemetryEnabled(for: descriptor.id) },
                                set: { controller.setProviderTelemetryEnabled($0, for: descriptor.id) }
                            )
                        )
                    } header: {
                        Text("Privacy")
                    } footer: {
                        Text("GitHub’s Copilot language server sends usage telemetry to GitHub unless you turn it off. This choice applies right away and stays on this Mac.")
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
        .task(id: controller.connectedAccount(for: descriptor.id)) {
            guard isConnectedAccount else { return }
            guard isConfigured else {
                await controller.refreshReturningAccount(for: descriptor.id)
                return
            }
            await controller.refreshConnectedAccountModels(for: descriptor.id)
            if usesDeviceCode {
                applyAccountModelFallback()
            } else {
                isUsingCustomModel = !modelGroups.flatMap(\.options).contains { $0.id == normalizedModel }
            }
        }
        .onDisappear {
            if isConnectedAccount { controller.cancelSignIn(to: descriptor.id) }
        }
        .confirmationDialog(
            "Disconnect \(descriptor.displayName)?",
            isPresented: $isConfirmingDisconnect
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await controller.disconnect(descriptor.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(disconnectMessage)
        }
    }

    private var disconnectMessage: String {
        usesDeviceCode
            ? "You will be signed out of \(descriptor.displayName) on this Mac."
            : "You will be signed out of \(descriptor.displayName), and its sign-in will be deleted from this Mac’s Keychain."
    }

    /// A saved model the account no longer offers falls back to the account's default model.
    private func applyAccountModelFallback() {
        let accountModels = controller.models(forConnectedAccount: descriptor.id)
        guard let defaultModel = accountModels.first,
              !accountModels.contains(where: { $0.id == normalizedModel }) else { return }
        if controller.customModelsByProviderID[descriptor.id] != nil {
            modelFallbackMessage = "\(normalizedModel) is no longer available to this account. Using \(defaultModel.name) instead."
        }
        draft.model = defaultModel.id
    }

    @ViewBuilder
    private var deviceCodeAccountContent: some View {
        let account = controller.connectedAccount(for: descriptor.id)
        let signInState = controller.signInState(for: descriptor.id)
        if isConfigured, signInState == .idle {
            LabeledContent("GitHub Account") {
                Text(account?.displayName ?? "Connected")
                    .textSelection(.enabled)
            }
            if let planType = account?.planType, !planType.isEmpty {
                LabeledContent("Copilot Plan") {
                    Text(planType.capitalized)
                }
            }
            if account?.requiresSignIn == true {
                HStack {
                    Label("Sign in required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Sign In with GitHub") {
                        controller.signIn(to: descriptor.id, restrictedProviderAccess: restrictedProviderAccess)
                    }
                }
            } else {
                HStack {
                    Label("Uses your GitHub Copilot plan", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Disconnect…") { isConfirmingDisconnect = true }
                }
                if case .unavailable(let reason) = controller.availability(for: descriptor.id) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(reason)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Retry") { controller.retryProvider(descriptor.id) }
                    }
                }
            }
        }
        switch signInState {
        case .preparingDeviceCode:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing GitHub sign-in…")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { controller.cancelSignIn(to: descriptor.id) }
            }
        case .waitingForDeviceCode(let authorization):
            VStack(spacing: 10) {
                GitProviderDeviceAuthorizationView(
                    authorization: authorization,
                    openVerification: { controller.openDeviceVerificationPage(for: descriptor.id) },
                    copyToPasteboard: { code in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    },
                    cancel: { controller.cancelSignIn(to: descriptor.id) }
                )
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Enter this code on GitHub, then return here.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        case .idle, .waitingForBrowser:
            if !isConfigured {
                HStack {
                    Text("Sign in with GitHub to use your Copilot plan, including Copilot Free.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sign In with GitHub") {
                        controller.signIn(to: descriptor.id, restrictedProviderAccess: restrictedProviderAccess)
                    }
                }
            }
        }
        if let message = controller.signInErrorMessage(for: descriptor.id) {
            Text(message)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var needsRiskAcknowledgment: Bool {
        descriptor.isUnofficial && !controller.isUnofficialProviderRiskAcknowledged
    }

    @ViewBuilder
    private var connectedAccountContent: some View {
        let account = controller.connectedAccount(for: descriptor.id)
        if isConfigured {
            LabeledContent("Account") {
                Text(account?.email ?? "Connected")
                    .textSelection(.enabled)
            }
            if let planType = account?.planType, !planType.isEmpty {
                LabeledContent("ChatGPT Plan") {
                    Text(planType.capitalized)
                }
            }
            HStack {
                Label(
                    descriptor.isUnofficial ? "Uses your ChatGPT Codex usage" : "Uses your ChatGPT plan",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                Spacer()
                Button("Disconnect…") { isConfirmingDisconnect = true }
            }
        } else if canConfigureKey {
            if needsRiskAcknowledgment {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This connection signs in through the Codex CLI’s client and identifies its requests as the Codex CLI. OpenAI does not support this interface: it may stop working at any time, and you use it at your own risk under OpenAI’s terms.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(
                        "I understand the risks",
                        isOn: Binding(
                            get: { controller.isUnofficialProviderRiskAcknowledged },
                            set: { if $0 { controller.acknowledgeUnofficialProviderRisk() } }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }
            if controller.signInState(for: descriptor.id) == .waitingForBrowser {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finish signing in in your browser…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { controller.cancelSignIn(to: descriptor.id) }
                }
                if let url = controller.authorizationURL(for: descriptor.id) {
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
                                controller.copyAuthorizationURL(for: descriptor.id)
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
                    Text(
                        descriptor.isUnofficial
                            ? "Sign in with any ChatGPT account, including Free, to use its Codex usage."
                            : "Sign in to use your ChatGPT Plus or Pro plan instead of an API key."
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Continue with ChatGPT") {
                        controller.signIn(to: descriptor.id, restrictedProviderAccess: restrictedProviderAccess)
                    }
                    .disabled(needsRiskAcknowledgment)
                }
                if let returning = controller.returningAccount(for: descriptor.id) {
                    HStack {
                        Text(returning.email.map { "Continues as \($0)." } ?? "Continues with the previously registered account.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Use Another Account") {
                            controller.signIn(
                                to: descriptor.id,
                                restrictedProviderAccess: restrictedProviderAccess,
                                newAccount: true
                            )
                        }
                    }
                }
            }
        }
        if let message = controller.signInErrorMessage(for: descriptor.id), !isConfigured {
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
        if usesDeviceCode {
            return "Uses your GitHub Copilot plan, never API billing, and counts toward its quota. GitHub’s Copilot language server handles sign-in, so Commit+ never sees or stores your token. The sign-in stays on this Mac and is never synced."
        }
        if isConnectedAccount {
            if !canConfigureKey, isConfigured {
                return "This ChatGPT connection requires Commit+ Pro to use. You can still disconnect it."
            }
            if descriptor.isUnofficial {
                return "Unofficial. Uses your ChatGPT account’s Codex usage, never API billing. OpenAI does not support this connection and may block it at any time. Sign-in tokens are stored in this Mac’s Keychain and are never synced."
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

/// Marks a provider that uses an interface its vendor does not support.
struct UnofficialProviderBadge: View {
    var body: some View {
        Text("Unofficial")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.15), in: Capsule())
            .help("OpenAI does not support this connection. It may stop working at any time.")
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
