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
import AppKit
import Combine
import Foundation

enum AIProviderSignInState: Equatable {
    case idle
    case waitingForBrowser
    /// Preparing a device-code sign-in, which can include downloading the provider's runtime.
    case preparingDeviceCode
    case waitingForDeviceCode(GitProviderDeviceAuthorization)
}

@MainActor
final class AIProviderController: ObservableObject {
    @Published private(set) var availabilityByProviderID: [AIProviderID: AIProviderAvailability] = [:]
    @Published private(set) var configuredProviderIDs: Set<AIProviderID> = []
    @Published private(set) var customModelsByProviderID: [AIProviderID: String] = [:]
    private var commitMessageGenerationID: UUID?
    @Published private(set) var isGenerating = false
    @Published private(set) var selectedProviderID: AIProviderID
    @Published private(set) var isThinkingEnabled: Bool
    // Connected-account (ChatGPT sign-in) state, keyed by provider so each sign-in stays separate.
    @Published private(set) var connectedAccounts: [AIProviderID: ConnectedAIAccountSummary] = [:]
    @Published private(set) var signInStates: [AIProviderID: AIProviderSignInState] = [:]
    /// The browser link for a pending sign-in, shown so it can be opened in another browser profile.
    @Published private(set) var authorizationURLs: [AIProviderID: URL] = [:]
    /// The previously registered account a plain sign-in returns to; absent before the first registration.
    @Published private(set) var returningAccounts: [AIProviderID: ChatGPTReturningAccount] = [:]
    @Published private(set) var signInErrorMessages: [AIProviderID: String] = [:]
    @Published private(set) var connectedAccountModels: [AIProviderID: [AIProviderModelOption]] = [:]
    /// Local-only telemetry choices for providers that run a vendor process (GitHub Copilot).
    @Published private(set) var telemetryEnabledByProviderID: [AIProviderID: Bool] = [:]
    /// Whether the unofficial-provider notice was acknowledged on this Mac. Local only; never synced.
    @Published private(set) var isUnofficialProviderRiskAcknowledged: Bool
    private var signInTasks: [AIProviderID: Task<Void, Never>] = [:]
    /// How long the loopback listener waits for the browser before the sign-in is abandoned.
    var signInTimeout: Duration = .seconds(600)
    private let unofficialRiskDefaultsKey = "ai.chatgptCodex.riskAcknowledged"

    @Published private(set) var availabilityRevision = 0
    private var availabilityTasks: [AIProviderID: (id: UUID, task: Task<AIProviderAvailability, Never>)] = [:]
    private var requestedProviderIDs: Set<AIProviderID> = []

    let managedUsageController: CommitPlusAIUsageController?
    private var usageObservation: AnyCancellable?
    private let managedProviderAccess: () -> Bool
    private let restrictedProviderAccess: () -> FeatureAccessDecision
    private let registry: AIProviderRegistry
    private let snapshotLoader: any CommitChangeSnapshotLoading
    private let repositoryToolExecutor: any RepositoryAIToolExecuting
    private let repositoryFileContextService: any RepositoryAIFileContextServicing
    private let repositoryAgentHarness: RepositoryAIAgentHarness
    private let defaults: UserDefaults
    private let credentialStore: any AIProviderCredentialStore
    private let modelStore: any AIProviderModelStore
    private let openURL: @MainActor (URL) -> Void
    private let selectedProviderDefaultsKey = "ai.commitMessage.selectedProvider"

    convenience init(
        restrictedProviderAccess: @escaping () -> FeatureAccessDecision = { .denied(.requiresPro) },
        managedProviderAccess: @escaping () -> Bool = { false },
        managedProvider: CommitPlusAIProvider? = nil,
        managedUsageController: CommitPlusAIUsageController? = nil
    ) {
        let credentialStore = KeychainAIProviderCredentialStore()
        let modelStore = UserDefaultsAIProviderModelStore()
        self.init(
            registry: .live(credentialStore: credentialStore, modelStore: modelStore, managedProvider: managedProvider),
            snapshotLoader: GitStatusService.shared,
            repositoryToolExecutor: GitStatusService.shared,
            repositoryFileContextService: GitStatusService.shared,
            repositoryAgentHarness: RepositoryAIAgentHarness(),
            defaults: .standard,
            credentialStore: credentialStore,
            modelStore: modelStore,
            restrictedProviderAccess: restrictedProviderAccess,
            managedProviderAccess: managedProviderAccess,
            managedUsageController: managedUsageController
        )
    }

    init(
        registry: AIProviderRegistry,
        snapshotLoader: any CommitChangeSnapshotLoading,
        repositoryToolExecutor: any RepositoryAIToolExecuting = GitStatusService.shared,
        repositoryFileContextService: any RepositoryAIFileContextServicing = GitStatusService.shared,
        repositoryAgentHarness: RepositoryAIAgentHarness = RepositoryAIAgentHarness(),
        defaults: UserDefaults,
        credentialStore: any AIProviderCredentialStore = KeychainAIProviderCredentialStore(),
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore(),
        restrictedProviderAccess: @escaping () -> FeatureAccessDecision = { .denied(.requiresPro) },
        managedProviderAccess: @escaping () -> Bool = { false },
        managedUsageController: CommitPlusAIUsageController? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.managedUsageController = managedUsageController
        self.openURL = openURL
        self.managedProviderAccess = managedProviderAccess
        self.restrictedProviderAccess = restrictedProviderAccess
        self.registry = registry
        self.snapshotLoader = snapshotLoader
        self.repositoryToolExecutor = repositoryToolExecutor
        self.repositoryFileContextService = repositoryFileContextService
        self.repositoryAgentHarness = repositoryAgentHarness
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.modelStore = modelStore
        isThinkingEnabled = modelStore.isThinkingEnabled
        isUnofficialProviderRiskAcknowledged = defaults.bool(forKey: unofficialRiskDefaultsKey)
        let storedID = defaults.string(forKey: selectedProviderDefaultsKey).map(AIProviderID.init(rawValue:))
        if let storedID, registry.provider(for: storedID)?.descriptor.isImplemented == true {
            selectedProviderID = storedID
        } else {
            selectedProviderID = .appleIntelligence
        }

        for descriptor in registry.descriptors {
            availabilityByProviderID[descriptor.id] = descriptor.isImplemented ? .checking : .comingSoon
            if descriptor.billing.usesPersonalCredential,
               let customModel = modelStore.customModel(for: descriptor.id) {
                customModelsByProviderID[descriptor.id] = customModel
            }
        }
        usageObservation = managedUsageController?.$state.sink { [weak self] state in
            let availability: AIProviderAvailability
            switch state {
            case .idle, .loading: availability = .checking
            case .loaded(let value): availability = value.availability
            case .unavailable(let reason): availability = .unavailable(reason)
            }
            self?.availabilityByProviderID[.commitPlusAI] = availability
        }
    }

    var descriptors: [AIProviderDescriptor] {
        registry.descriptors
    }

    var selectedDescriptor: AIProviderDescriptor {
        registry.provider(for: selectedProviderID)?.descriptor
            ?? registry.descriptors[0]
    }

    var selectedProviderAvailability: AIProviderAvailability {
        availability(for: selectedProviderID)
    }

    func availability(for id: AIProviderID) -> AIProviderAvailability {
        if registry.provider(for: id)?.descriptor.billing == .commitPlus, !managedProviderAccess() {
            return .unavailable("Sign in with an active Commit+ Pro subscription to use Commit+ AI.")
        }
        return availabilityByProviderID[id] ?? .checking
    }

    func selectProvider(_ id: AIProviderID) {
        guard let descriptor = registry.provider(for: id)?.descriptor,
              descriptor.isImplemented else { return }
        if descriptor.billing == .commitPlus {
            guard managedProviderAccess(), !isGenerating else { return }
        }
        selectedProviderID = id
        defaults.set(id.rawValue, forKey: selectedProviderDefaultsKey)
        Task { await refreshAvailability(for: id) }
    }

    /// Applies to every provider on its next request; providers read it from the model store.
    func setThinkingEnabled(_ isEnabled: Bool) {
        modelStore.setThinkingEnabled(isEnabled)
        isThinkingEnabled = isEnabled
    }

    func isAPIKeyConfigured(for id: AIProviderID) -> Bool {
        configuredProviderIDs.contains(id)
    }

    func canSelect(
        _ descriptor: AIProviderDescriptor,
        restrictedProviderAccess: FeatureAccessDecision
    ) -> Bool {
        if descriptor.billing == .commitPlus {
            return descriptor.isImplemented && managedProviderAccess() && !isGenerating
        }
        guard descriptor.isImplemented,
              availability(for: descriptor.id).isAvailable else {
            return false
        }
        if descriptor.billing.usesPersonalCredential,
           !isAPIKeyConfigured(for: descriptor.id) {
            return false
        }
        if descriptor.requiresProToConfigureAPIKey,
           !restrictedProviderAccess.isAllowed {
            return false
        }
        return true
    }

    func model(for descriptor: AIProviderDescriptor) -> String? {
        guard descriptor.billing != .commitPlus else { return nil }
        return customModelsByProviderID[descriptor.id] ?? descriptor.defaultModel
    }

    func configurationDrafts() -> [AIProviderConfigurationDraft] {
        descriptors.compactMap { descriptor in
            guard descriptor.billing.usesPersonalCredential,
                  let model = model(for: descriptor) else { return nil }
            return AIProviderConfigurationDraft(id: descriptor.id, model: model)
        }
    }

    func saveAPIKey(_ apiKey: String, for id: AIProviderID) throws {
        guard registry.provider(for: id)?.descriptor.billing == .bringYourOwnKey else {
            throw CommitMessageGenerationError.providerRequestFailed("This provider does not use a personal API key.")
        }
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw CommitMessageGenerationError.providerRequestFailed("Enter an API key before saving.")
        }
        try credentialStore.saveAPIKey(normalizedKey, for: id)
        configuredProviderIDs.insert(id)
        invalidateAvailability()
    }

    func removeAPIKey(for id: AIProviderID) throws {
        guard registry.provider(for: id)?.descriptor.billing == .bringYourOwnKey else {
            throw CommitMessageGenerationError.providerRequestFailed("This provider does not use a personal API key.")
        }
        try credentialStore.deleteAPIKey(for: id)
        configuredProviderIDs.remove(id)
        invalidateAvailability()
        if selectedProviderID == id {
            selectProvider(.appleIntelligence)
        }
    }

    func applyProviderChanges(
        _ drafts: [AIProviderConfigurationDraft],
        restrictedProviderAccess: FeatureAccessDecision
    ) throws {
        for draft in drafts {
            guard registry.provider(for: draft.id)?.descriptor.billing.usesPersonalCredential == true else {
                throw CommitMessageGenerationError.providerRequestFailed("Only personal-key providers can be configured here.")
            }
        }
        for draft in drafts where !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let descriptor = registry.provider(for: draft.id)?.descriptor else { continue }
            if descriptor.requiresProToConfigureAPIKey,
               !restrictedProviderAccess.isAllowed {
                throw AIProviderConfigurationError.requiresPro(providerName: descriptor.displayName)
            }
        }

        for draft in drafts {
            let usesAPIKey = registry.provider(for: draft.id)?.descriptor.billing == .bringYourOwnKey
            if usesAPIKey, !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try saveAPIKey(draft.apiKey, for: draft.id)
            } else if usesAPIKey, draft.shouldRemoveAPIKey {
                try removeAPIKey(for: draft.id)
            }

            guard let descriptor = registry.provider(for: draft.id)?.descriptor,
                  let defaultModel = descriptor.defaultModel else { continue }
            let normalizedModel = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedModel.isEmpty || normalizedModel == defaultModel {
                modelStore.resetModel(for: draft.id)
                customModelsByProviderID.removeValue(forKey: draft.id)
            } else {
                modelStore.saveCustomModel(normalizedModel, for: draft.id)
                customModelsByProviderID[draft.id] = normalizedModel
            }
        }
        if !drafts.isEmpty { invalidateAvailability() }
    }

    // MARK: Connected accounts (ChatGPT sign-in)

    private func connectedAccountProvider(_ id: AIProviderID) -> (any ConnectedAccountAIProvider)? {
        registry.provider(for: id) as? any ConnectedAccountAIProvider
    }

    private func deviceCodeProvider(_ id: AIProviderID) -> (any DeviceCodeAccountAIProvider)? {
        registry.provider(for: id) as? any DeviceCodeAccountAIProvider
    }

    /// Whether the provider signs in with a GitHub device code (GitHub Copilot) rather than the browser.
    func usesDeviceCodeSignIn(_ id: AIProviderID) -> Bool {
        deviceCodeProvider(id) != nil
    }

    func isProviderTelemetryEnabled(for id: AIProviderID) -> Bool {
        telemetryEnabledByProviderID[id] ?? deviceCodeProvider(id)?.isTelemetryEnabled ?? false
    }

    func setProviderTelemetryEnabled(_ isEnabled: Bool, for id: AIProviderID) {
        guard let provider = deviceCodeProvider(id) else { return }
        telemetryEnabledByProviderID[id] = isEnabled
        Task { await provider.setTelemetryEnabled(isEnabled) }
    }

    /// Clears a runtime or server failure so the next availability check tries again.
    func retryProvider(_ id: AIProviderID) {
        guard let provider = deviceCodeProvider(id) else { return }
        Task {
            await provider.resetAfterFailure()
            invalidateAvailability()
        }
    }

    func connectedAccount(for id: AIProviderID) -> ConnectedAIAccountSummary? {
        connectedAccounts[id]
    }

    func signInState(for id: AIProviderID) -> AIProviderSignInState {
        signInStates[id] ?? .idle
    }

    func authorizationURL(for id: AIProviderID) -> URL? {
        authorizationURLs[id]
    }

    func returningAccount(for id: AIProviderID) -> ChatGPTReturningAccount? {
        returningAccounts[id]
    }

    func signInErrorMessage(for id: AIProviderID) -> String? {
        signInErrorMessages[id]
    }

    func models(forConnectedAccount id: AIProviderID) -> [AIProviderModelOption] {
        connectedAccountModels[id] ?? []
    }

    /// Records that the user accepted the unofficial-provider notice on this Mac.
    func acknowledgeUnofficialProviderRisk() {
        defaults.set(true, forKey: unofficialRiskDefaultsKey)
        isUnofficialProviderRiskAcknowledged = true
    }

    private func updateConnectedAccount(_ account: ConnectedAIAccountSummary?, for id: AIProviderID) {
        connectedAccounts[id] = account
        if account != nil {
            configuredProviderIDs.insert(id)
        } else {
            configuredProviderIDs.remove(id)
            connectedAccountModels[id] = nil
        }
    }

    /// Opens the provider's ChatGPT sign-in in the browser and waits for the loopback
    /// callback. `newAccount` registers a new client instead of returning to the saved
    /// account (official flow only).
    func signIn(
        to id: AIProviderID,
        restrictedProviderAccess: FeatureAccessDecision,
        newAccount: Bool = false
    ) {
        guard signInTasks[id] == nil else { return }
        if let provider = deviceCodeProvider(id) {
            signInWithDeviceCode(provider)
            return
        }
        guard let provider = connectedAccountProvider(id) else { return }
        let descriptor = provider.descriptor
        guard restrictedProviderAccess.isAllowed else {
            signInErrorMessages[id] = AIProviderConfigurationError
                .requiresProToConnect(providerName: descriptor.displayName).localizedDescription
            return
        }
        guard !descriptor.isUnofficial || isUnofficialProviderRiskAcknowledged else {
            signInErrorMessages[id] = "Acknowledge the notice about this unofficial connection before signing in."
            return
        }
        let session = provider.session
        signInErrorMessages[id] = nil
        signInStates[id] = .waitingForBrowser
        signInTasks[id] = Task { [weak self] in
            do {
                let server = try await ChatGPTLoopbackCallbackServer.start(for: session.configuration)
                defer { server.stop() }
                let authorizationURL = try await session.beginAuthorization(
                    redirectURI: server.redirectURI,
                    newAccount: newAccount
                )
                self?.authorizationURLs[id] = authorizationURL
                self?.openURL(authorizationURL)
                // Stopping the server ends the callback stream, so a timeout ends the wait below.
                let timeout = self?.signInTimeout ?? .seconds(600)
                let timer = Task {
                    try await Task.sleep(for: timeout)
                    server.stop()
                }
                defer { timer.cancel() }
                var account: ConnectedAIAccountSummary?
                for await callbackURL in server.callbacks {
                    do {
                        account = try await session.completeAuthorization(callbackURL: callbackURL)
                        break
                    } catch let error as GitProviderOAuthError
                        where error == .stateMismatch || error == .missingState || error == .unsupportedCallback {
                        continue
                    }
                }
                try Task.checkCancellation()
                guard let account else { throw ChatGPTAuthError.timedOut }
                if let self {
                    self.updateConnectedAccount(account, for: id)
                    self.invalidateAvailability()
                    await self.refreshConnectedAccountModels(for: id)
                }
            } catch is CancellationError {
            } catch ChatGPTAuthError.consentDenied {
            } catch {
                self?.signInErrorMessages[id] = error.localizedDescription
            }
            await session.cancelAuthorization()
            self?.returningAccounts[id] = await session.returningAccount()
            self?.authorizationURLs[id] = nil
            self?.signInStates[id] = .idle
            self?.signInTasks[id] = nil
        }
    }

    /// Shows a GitHub device code and waits for the user to approve it. Copilot is not
    /// Pro-gated, so no Commit+ access check applies.
    private func signInWithDeviceCode(_ provider: any DeviceCodeAccountAIProvider) {
        let id = provider.descriptor.id
        signInErrorMessages[id] = nil
        signInStates[id] = .preparingDeviceCode
        signInTasks[id] = Task { [weak self] in
            var didComplete = false
            do {
                let account: ConnectedAIAccountSummary
                switch try await provider.beginSignIn() {
                case .signedIn(let signedIn):
                    account = signedIn
                case .deviceCode(let authorization):
                    try Task.checkCancellation()
                    self?.signInStates[id] = .waitingForDeviceCode(authorization)
                    account = try await provider.completeSignIn()
                }
                try Task.checkCancellation()
                didComplete = true
                if let self {
                    self.updateConnectedAccount(account, for: id)
                    self.invalidateAvailability()
                    await self.refreshConnectedAccountModels(for: id)
                }
            } catch is CancellationError {
            } catch {
                self?.signInErrorMessages[id] = error.localizedDescription
            }
            if !didComplete {
                // Runs outside this cancelled task so its server requests are not cancelled too.
                await Task { await provider.cancelSignIn() }.value
            }
            self?.signInStates[id] = .idle
            self?.signInTasks[id] = nil
        }
    }

    func openDeviceVerificationPage(for id: AIProviderID) {
        guard case .waitingForDeviceCode(let authorization) = signInState(for: id) else { return }
        openURL(authorization.verificationURI)
    }

    func cancelSignIn(to id: AIProviderID) {
        signInTasks[id]?.cancel()
    }

    func copyAuthorizationURL(for id: AIProviderID) {
        guard let url = authorizationURLs[id] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// Revokes and deletes the provider's sign-in. Allowed without Pro, so a lapsed
    /// subscriber can still remove the connection.
    func disconnect(_ id: AIProviderID) async {
        cancelSignIn(to: id)
        if let provider = deviceCodeProvider(id) {
            await provider.signOut()
        } else if let session = connectedAccountProvider(id)?.session {
            await session.disconnect()
        } else {
            return
        }
        updateConnectedAccount(nil, for: id)
        invalidateAvailability()
        if selectedProviderID == id {
            selectProvider(.appleIntelligence)
        }
    }

    func refreshReturningAccount(for id: AIProviderID) async {
        guard let session = connectedAccountProvider(id)?.session else { return }
        returningAccounts[id] = await session.returningAccount()
    }

    func refreshConnectedAccountModels(for id: AIProviderID) async {
        guard connectedAccounts[id] != nil else { return }
        let models: [AIProviderModelOption]?
        if let provider = deviceCodeProvider(id) {
            models = try? await provider.availableModels()
        } else if let provider = connectedAccountProvider(id) {
            models = try? await provider.availableModels()
        } else {
            return
        }
        if let models, !models.isEmpty {
            connectedAccountModels[id] = models
        }
    }

    private func validateProviderAccess(_ descriptor: AIProviderDescriptor) throws {
        if descriptor.billing == .commitPlus {
            guard managedProviderAccess() else {
                throw AIProviderConfigurationError.unavailableOnCurrentPlan(providerName: descriptor.displayName)
            }
            return
        }
        guard descriptor.requiresProToConfigureAPIKey else { return }
        // A saved key or persisted selection does not grant access after logout/downgrade.
        guard restrictedProviderAccess().isAllowed else {
            throw AIProviderConfigurationError.unavailableOnCurrentPlan(providerName: descriptor.displayName)
        }
    }

    /// Invalidating is cheap and does not start provider work from the Welcome window.
    /// Visible AI surfaces observe the revision and request their own refresh.
    func invalidateAvailability() {
        for request in availabilityTasks.values { request.task.cancel() }
        availabilityTasks.removeAll()
        for descriptor in registry.descriptors {
            availabilityByProviderID[descriptor.id] = descriptor.isImplemented ? .checking : .comingSoon
        }
        availabilityRevision += 1
    }

    func refreshManagedUsageIfNeeded() async {
        guard requestedProviderIDs.contains(.commitPlusAI), managedProviderAccess() else { return }
        await refreshAvailability(for: .commitPlusAI)
    }

    func refreshAvailability(selectedOnly: Bool = false) async {
        let ids = selectedOnly ? [selectedProviderID] : registry.providers.map { $0.descriptor.id }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { await self.refreshAvailability(for: id) }
            }
        }
    }

    private func refreshAvailability(for id: AIProviderID) async {
        guard !Task.isCancelled, let provider = registry.provider(for: id) else { return }
        requestedProviderIDs.insert(id)
        let request: (id: UUID, task: Task<AIProviderAvailability, Never>)
        if let pending = availabilityTasks[id] {
            request = pending
        } else {
            if provider.descriptor.billing == .bringYourOwnKey {
                if (try? credentialStore.apiKey(for: id)) != nil {
                    configuredProviderIDs.insert(id)
                } else {
                    configuredProviderIDs.remove(id)
                }
            }
            if let session = connectedAccountProvider(id)?.session {
                updateConnectedAccount(await session.account(), for: id)
                returningAccounts[id] = await session.returningAccount()
            } else if let deviceCodeProvider = deviceCodeProvider(id) {
                updateConnectedAccount(await deviceCodeProvider.connectedAccount(), for: id)
            }
            request = (UUID(), Task { await provider.availability() })
            availabilityTasks[id] = request
        }
        let value = await request.task.value
        // A changed account/key or a newer refresh must win over an old result.
        guard availabilityTasks[id]?.id == request.id else { return }
        availabilityTasks[id] = nil
        availabilityByProviderID[id] = value
        // Checking availability is what learns that a device-code sign-in expired.
        if let deviceCodeProvider = deviceCodeProvider(id), signInTasks[id] == nil {
            updateConnectedAccount(await deviceCodeProvider.connectedAccount(), for: id)
        }
    }

    func generateCommitMessage(
        repositoryURL: URL,
        branchName: String?,
        changeSource: CommitChangeSource,
        recentCommitSubjects: [String]
    ) async throws -> GeneratedCommitMessage {
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("A commit message is already being generated.")
        }
        try Task.checkCancellation()
        let generationID = UUID()
        commitMessageGenerationID = generationID
        isGenerating = true
        defer {
            if commitMessageGenerationID == generationID {
                commitMessageGenerationID = nil
                isGenerating = false
            }
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        try validateProviderAccess(provider.descriptor)
        let providerID = selectedProviderID
        let providerAvailability = await provider.availability()
        try validateCommitMessageGeneration(generationID)
        availabilityByProviderID[providerID] = providerAvailability
        guard providerAvailability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(providerAvailability.detail)
        }

        try validateProviderAccess(provider.descriptor)

        let snapshot = try await snapshotLoader.commitChangeSnapshot(
            in: repositoryURL,
            source: changeSource,
            characterBudget: provider.descriptor.inputCharacterBudget
        )
        try validateCommitMessageGeneration(generationID)
        let request = CommitMessageGenerationRequest(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            changeSource: changeSource,
            changes: snapshot,
            recentCommitSubjects: Array(recentCommitSubjects.prefix(8))
        )
        try validateProviderAccess(provider.descriptor)
        let generated = try await provider.generateCommitMessage(request: request)
        try validateCommitMessageGeneration(generationID)
        let currentFingerprint = try await snapshotLoader.changesFingerprint(
            in: repositoryURL,
            source: changeSource
        )
        try validateCommitMessageGeneration(generationID)
        guard providerID == selectedProviderID, currentFingerprint == snapshot.fingerprint else {
            throw CommitMessageGenerationError.changesChanged(changeSource)
        }
        return generated
    }

    func cancelCommitMessageGeneration() {
        guard commitMessageGenerationID != nil else { return }
        commitMessageGenerationID = nil
        isGenerating = false
    }

    private func validateCommitMessageGeneration(_ id: UUID) throws {
        try Task.checkCancellation()
        guard commitMessageGenerationID == id else { throw CancellationError() }
    }

    func answerRepositoryQuestion(
        repositoryURL: URL,
        branchName: String?,
        question: String,
        tool: RepositoryAIToolCall,
        sessionID: String? = nil,
        onTextDelta: (@Sendable (String) async -> Void)? = nil
    ) async throws -> RepositoryAIAnswer {
        try Task.checkCancellation()
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else {
            throw RepositoryAIError.emptyQuestion
        }
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("Another AI request is already running.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        try validateProviderAccess(provider.descriptor)
        let providerID = selectedProviderID
        let providerAvailability = await provider.availability()
        availabilityByProviderID[providerID] = providerAvailability
        guard providerAvailability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(providerAvailability.detail)
        }

        try validateProviderAccess(provider.descriptor)
        isGenerating = true
        defer { isGenerating = false }

        let result = try await repositoryToolExecutor.execute(
            tool,
            in: repositoryURL,
            characterBudget: provider.descriptor.inputCharacterBudget
        )
        try Task.checkCancellation()
        let request = RepositoryAIRequest(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            question: normalizedQuestion,
            toolResult: result,
            sessionID: sessionID
        )
        try validateProviderAccess(provider.descriptor)
        let response: RepositoryAIAnswer
        if let onTextDelta {
            response = try await provider.streamRepositoryResponse(
                request: request,
                onTextDelta: onTextDelta
            )
        } else {
            response = try await provider.generateRepositoryResponse(request: request)
        }
        try Task.checkCancellation()
        let currentFingerprint = try await repositoryToolExecutor.fingerprint(
            for: tool,
            in: repositoryURL
        )
        guard providerID == selectedProviderID,
              currentFingerprint == result.fingerprint else {
            throw RepositoryAIError.contextChanged
        }

        guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryAIError.emptyResponse
        }
        try Task.checkCancellation()
        return response
    }

    /// Sends already-loaded, provider-neutral evidence through the same standalone
    /// Repository AI path. The caller owns context loading and must re-resolve its
    /// immutable fingerprint after generation.
    func answerRepositoryAnalysisQuestion(
        repositoryURL: URL,
        branchName: String?,
        question: String,
        result: RepositoryAIToolResult,
        currentFingerprint: @escaping () async throws -> String,
        sessionID: String? = nil,
        onTextDelta: (@Sendable (String) async -> Void)? = nil
    ) async throws -> RepositoryAIAnswer {
        try Task.checkCancellation()
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else { throw RepositoryAIError.emptyQuestion }
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("Another AI request is already running.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        try validateProviderAccess(provider.descriptor)
        let providerID = selectedProviderID
        let availability = await provider.availability()
        availabilityByProviderID[providerID] = availability
        guard availability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(availability.detail)
        }

        try validateProviderAccess(provider.descriptor)
        isGenerating = true
        defer { isGenerating = false }
        try Task.checkCancellation()
        let request = RepositoryAIRequest(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            question: normalizedQuestion,
            toolResult: result,
            sessionID: sessionID
        )
        try validateProviderAccess(provider.descriptor)
        let response: RepositoryAIAnswer
        if let onTextDelta {
            response = try await provider.streamRepositoryResponse(
                request: request,
                onTextDelta: onTextDelta
            )
        } else {
            response = try await provider.generateRepositoryResponse(request: request)
        }
        guard providerID == selectedProviderID,
              try await currentFingerprint() == result.fingerprint else {
            throw RepositoryAIError.contextChanged
        }
        guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryAIError.emptyResponse
        }
        try Task.checkCancellation()
        return response
    }

    func answerRepositoryFileQuestion(
        repositoryURL: URL,
        branchName: String?,
        question: String,
        reference: RepositoryAIFileReference,
        includeDiff: Bool,
        sessionID: String? = nil
    ) async throws -> (answer: RepositoryAIAnswer, manifest: RepositoryAIEvidenceManifest) {
        try Task.checkCancellation()
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else { throw RepositoryAIError.emptyQuestion }
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("Another AI request is already running.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        try validateProviderAccess(provider.descriptor)
        let providerID = selectedProviderID
        let availability = await provider.availability()
        availabilityByProviderID[providerID] = availability
        guard availability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(availability.detail)
        }

        try validateProviderAccess(provider.descriptor)
        isGenerating = true
        defer { isGenerating = false }
        let budget = provider.descriptor.inputCharacterBudget
        let result: RepositoryAIToolResult
        let manifest: RepositoryAIEvidenceManifest
        if includeDiff {
            let diff = try await repositoryFileContextService.readFileDiff(
                reference,
                contextLines: 3,
                maximumHunks: 12,
                characterBudget: budget,
                in: repositoryURL
            )
            manifest = diff.manifest
            result = RepositoryAIToolResult(
                toolName: "read_file_diff",
                title: diff.reference.displayLabel,
                fingerprint: diff.evidence.fingerprint,
                content: RepositoryAIPrompt.fileEvidence(diff),
                isTruncated: diff.isTruncated
            )
        } else {
            let context = try await repositoryFileContextService.readFileContext(
                reference,
                lineRange: nil,
                characterBudget: budget,
                in: repositoryURL
            )
            manifest = context.manifest
            result = RepositoryAIToolResult(
                toolName: "read_file_context",
                title: context.reference.displayLabel,
                fingerprint: context.evidence.fingerprint,
                content: RepositoryAIPrompt.fileEvidence(context),
                isTruncated: context.isTruncated
            )
        }
        try Task.checkCancellation()
        try validateProviderAccess(provider.descriptor)
        let response = try await provider.generateRepositoryResponse(request: RepositoryAIRequest(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            question: normalizedQuestion,
            toolResult: result,
            sessionID: sessionID
        ))
        try Task.checkCancellation()
        guard providerID == selectedProviderID else { throw RepositoryAIError.contextChanged }
        guard let evidence = manifest.evidence.first else { throw RepositoryAIError.invalidResponse("Repository AI did not receive file evidence.") }
        let currentFingerprint = try await repositoryFileContextService.currentFingerprint(for: evidence.reference, in: repositoryURL)
        guard currentFingerprint == evidence.fingerprint else { throw RepositoryAIError.contextChanged }
        let validated = manifest.validatedCitations(from: response.citations)
        try Task.checkCancellation()
        return (RepositoryAIAnswer(text: response.text, citations: validated.accepted), manifest)
    }

    func answerRepositoryQuestionWithAgent(
        repositoryURL: URL,
        branchName: String?,
        question: String,
        conversation: [RepositoryAIMessage] = [],
        allowsBuiltInWorkflows: Bool = false
    ) async throws -> RepositoryAIAgentRunResult {
        try Task.checkCancellation()
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else {
            throw RepositoryAIError.emptyQuestion
        }
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("Another AI request is already running.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        try validateProviderAccess(provider.descriptor)
        guard provider.supportsRepositoryAgent else {
            throw RepositoryAIAgentError.unsupportedProvider(provider.descriptor.displayName)
        }

        let providerID = selectedProviderID
        let providerAvailability = await provider.availability()
        availabilityByProviderID[providerID] = providerAvailability
        guard providerAvailability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(providerAvailability.detail)
        }

        try validateProviderAccess(provider.descriptor)
        isGenerating = true
        defer { isGenerating = false }

        let result = try await repositoryAgentHarness.answer(
            question: normalizedQuestion,
            repositoryURL: repositoryURL,
            branchName: branchName,
            conversation: conversation,
            allowsBuiltInWorkflows: allowsBuiltInWorkflows,
            provider: provider
        )
        try Task.checkCancellation()
        guard providerID == selectedProviderID else {
            throw RepositoryAIError.contextChanged
        }
        return result
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("Another AI request is already running.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        try validateProviderAccess(provider.descriptor)

        let providerID = selectedProviderID
        let providerAvailability = await provider.availability()
        availabilityByProviderID[providerID] = providerAvailability
        guard providerAvailability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(providerAvailability.detail)
        }

        try validateProviderAccess(provider.descriptor)
        isGenerating = true
        defer { isGenerating = false }

        let response = try await provider.generateConflictResolution(request: request)
        guard providerID == selectedProviderID else {
            throw ConflictAIResolutionError.staleFile(
                "The selected AI provider changed while conflicts were being resolved."
            )
        }
        return response
    }
}
