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
import Combine
import Foundation

@MainActor
final class AIProviderController: ObservableObject {
    @Published private(set) var availabilityByProviderID: [AIProviderID: AIProviderAvailability] = [:]
    @Published private(set) var configuredProviderIDs: Set<AIProviderID> = []
    @Published private(set) var customModelsByProviderID: [AIProviderID: String] = [:]
    @Published private(set) var isGenerating = false
    @Published private(set) var selectedProviderID: AIProviderID

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
        managedUsageController: CommitPlusAIUsageController? = nil
    ) {
        self.managedUsageController = managedUsageController
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
        let storedID = defaults.string(forKey: selectedProviderDefaultsKey).map(AIProviderID.init(rawValue:))
        if let storedID, registry.provider(for: storedID)?.descriptor.isImplemented == true {
            selectedProviderID = storedID
        } else {
            selectedProviderID = .appleIntelligence
        }

        for descriptor in registry.descriptors {
            availabilityByProviderID[descriptor.id] = descriptor.isImplemented ? .checking : .comingSoon
            if descriptor.billing == .bringYourOwnKey,
               (try? credentialStore.apiKey(for: descriptor.id)) != nil {
                configuredProviderIDs.insert(descriptor.id)
            }
            if descriptor.billing == .bringYourOwnKey,
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
        if descriptor.billing == .commitPlus { Task { await managedUsageController?.refresh() } }
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
        if descriptor.billing == .bringYourOwnKey,
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
            guard descriptor.billing == .bringYourOwnKey,
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
    }

    func removeAPIKey(for id: AIProviderID) throws {
        guard registry.provider(for: id)?.descriptor.billing == .bringYourOwnKey else {
            throw CommitMessageGenerationError.providerRequestFailed("This provider does not use a personal API key.")
        }
        try credentialStore.deleteAPIKey(for: id)
        configuredProviderIDs.remove(id)
        if selectedProviderID == id {
            selectProvider(.appleIntelligence)
        }
    }

    func applyProviderChanges(
        _ drafts: [AIProviderConfigurationDraft],
        restrictedProviderAccess: FeatureAccessDecision
    ) throws {
        for draft in drafts {
            guard registry.provider(for: draft.id)?.descriptor.billing == .bringYourOwnKey else {
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
            if !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try saveAPIKey(draft.apiKey, for: draft.id)
            } else if draft.shouldRemoveAPIKey {
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

    func refreshAvailability() async {
        await withTaskGroup(of: (AIProviderID, AIProviderAvailability).self) { group in
            for provider in registry.providers {
                let id = provider.descriptor.id
                group.addTask { (id, await provider.availability()) }
            }
            for await (id, availability) in group {
                availabilityByProviderID[id] = availability
            }
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

        let snapshot = try await snapshotLoader.commitChangeSnapshot(
            in: repositoryURL,
            source: changeSource,
            characterBudget: provider.descriptor.inputCharacterBudget
        )
        let request = CommitMessageGenerationRequest(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            changeSource: changeSource,
            changes: snapshot,
            recentCommitSubjects: Array(recentCommitSubjects.prefix(8))
        )
        try validateProviderAccess(provider.descriptor)
        let generated = try await provider.generateCommitMessage(request: request)
        let currentFingerprint = try await snapshotLoader.changesFingerprint(
            in: repositoryURL,
            source: changeSource
        )
        guard providerID == selectedProviderID, currentFingerprint == snapshot.fingerprint else {
            throw CommitMessageGenerationError.changesChanged(changeSource)
        }
        return generated
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
