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
final class RepositoryAIChatController: ObservableObject {
    // Evaluate live entitlement for every entry, including model-selected workflows.
    var workflowAccessDecision: () -> FeatureAccessDecision = { .denied(.requiresPro) }
    @Published var workflowAccessNotice: FeatureAccessNotice?

    @Published var draft = ""
    @Published var commitReferenceDraft = ""
    @Published var comparisonBaseDraft = ""
    @Published var comparisonHeadDraft = ""
    @Published var pullRequestNumberDraft = ""
    @Published private(set) var conversationTitle = "New conversation"
    @Published private(set) var messages: [RepositoryAIMessage] = []
    @Published private(set) var historyError: String?
    private let historyStore: RepositoryAIChatHistoryStore
    private var historyWriteTask: Task<Void, Never>?
    private var isRestoringHistory = false
    @Published private(set) var recentCommits: [RepositoryAICommitChoice] = []
    @Published private(set) var isStopping = false
    @Published private(set) var isRunning = false {
        didSet { if !isRunning { persistConversation() } }
    }
    @Published private(set) var isChoosingCommit = false
    @Published private(set) var isChoosingFile = false
    @Published private(set) var isChoosingComparison = false
    @Published private(set) var isChoosingPullRequest = false
    @Published private(set) var isLoadingCommits = false
    @Published private(set) var isLoadingFiles = false
    @Published private(set) var changedFiles: [RepositoryAIFileReference] = []
    @Published private(set) var streamingRevision = 0
    @Published private(set) var conversationPresentationID = UUID()
    @Published var pendingMutation: PendingRepositoryAIMutation?
    @Published private(set) var isExecutingMutation = false {
        didSet { if !isExecutingMutation { persistConversation() } }
    }
    @Published var pendingRemoteOperation: PendingRepositoryAIRemoteOperation?
    @Published private(set) var isExecutingRemoteOperation = false {
        didSet { if !isExecutingRemoteOperation { persistConversation() } }
    }

    private let repositoryURL: URL
    private let providerController: AIProviderController
    private let gitService: GitStatusService
    private let mutationExecutor: (any RepositoryAIMutationExecuting)?
    private let mutationContextProvider: (any RepositoryAIMutationContextProviding)?
    private let remoteOperationContextProvider: (any RepositoryAIRemoteOperationContextProviding)?
    private let commitAllPreparer: (any RepositoryAICommitAllPreparing)?
    private let pullRequestContextLoader: ((Int?, URL) async throws -> RepositoryAIPullRequestContext)?
    private let pullRequestFingerprintLoader: ((Int, URL) async throws -> String)?
    private var conversationSessionID = UUID().uuidString
    private var activeRequestTask: Task<Void, Never>?
    private var pendingQuickAction: (action: RepositoryAIQuickAction, question: String)?
    private var pendingMutationExpirationTask: Task<Void, Never>?
    private var pendingRemoteOperationExpirationTask: Task<Void, Never>?

    init(
        repositoryURL: URL,
        providerController: AIProviderController,
        gitService: GitStatusService = .shared,
        mutationExecutor: (any RepositoryAIMutationExecuting)? = nil,
        mutationContextProvider: (any RepositoryAIMutationContextProviding)? = nil,
        remoteOperationContextProvider: (any RepositoryAIRemoteOperationContextProviding)? = nil,
        commitAllPreparer: (any RepositoryAICommitAllPreparing)? = nil,
        pullRequestContextLoader: ((Int?, URL) async throws -> RepositoryAIPullRequestContext)? = nil,
        pullRequestFingerprintLoader: ((Int, URL) async throws -> String)? = nil,
        historyStore: RepositoryAIChatHistoryStore = .shared
    ) {
        self.historyStore = historyStore
        self.repositoryURL = repositoryURL
        self.providerController = providerController
        self.gitService = gitService
        self.mutationExecutor = mutationExecutor
        self.mutationContextProvider = mutationContextProvider
        self.remoteOperationContextProvider = remoteOperationContextProvider
        self.commitAllPreparer = commitAllPreparer
        self.pullRequestContextLoader = pullRequestContextLoader
        self.pullRequestFingerprintLoader = pullRequestFingerprintLoader
    }

    private var historyRepositoryPath: String {
        repositoryURL.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func persistConversation() {
        // Streaming only updates memory. Persist at explicit lifecycle boundaries.
        guard !isRestoringHistory, !isRunning, !isExecutingMutation,
              !isExecutingRemoteOperation, !messages.isEmpty else { return }
        let snapshot = RepositoryAIConversation(
            id: conversationSessionID, repositoryPath: historyRepositoryPath,
            title: conversationTitle, updatedAt: .now, messages: messages
        )
        let previousWrite = historyWriteTask
        let store = historyStore
        historyWriteTask = Task { [weak self] in
            await previousWrite?.value
            do {
                try await store.save(snapshot)
                self?.historyError = nil
            } catch {
                self?.historyError = "Could not save conversation history: \(error.localizedDescription)"
            }
        }
    }

    func conversationHistory(matching query: String) async throws -> [RepositoryAIConversationSummary] {
        await historyWriteTask?.value
        return try await historyStore.search(repositoryPath: historyRepositoryPath, query: query)
    }

    func deleteConversation(id: String) async throws {
        await historyWriteTask?.value
        try await historyStore.delete(id: id, repositoryPath: historyRepositoryPath)
    }

    func prepareConversationHistory() async {
        persistConversation()
        await historyWriteTask?.value
    }

    func restoreConversation(id: String) async throws {
        guard !isInteractionDisabled else { throw RepositoryAIError.contextChanged }
        await prepareConversationHistory()
        guard let conversation = try await historyStore.load(id: id, repositoryPath: historyRepositoryPath) else {
            throw RepositoryAIError.noRepositoryData("saved conversation")
        }
        guard !isInteractionDisabled else { throw RepositoryAIError.contextChanged }
        isRestoringHistory = true
        defer { isRestoringHistory = false }
        dismissSelection()
        draft = ""
        conversationSessionID = conversation.id
        conversationTitle = conversation.title
        messages = conversation.messages
        conversationPresentationID = UUID()
        streamingRevision += 1
    }

    var canSubmit: Bool {
        !isRunning
            && !isStopping
            && !isExecutingMutation
            && !isExecutingRemoteOperation
            && pendingMutation == nil
            && pendingRemoteOperation == nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isInteractionDisabled: Bool {
        isRunning
            || isStopping
            || isExecutingMutation
            || isExecutingRemoteOperation
            || pendingMutation != nil
            || pendingRemoteOperation != nil
    }

    var canExplainCommitReference: Bool {
        !isInteractionDisabled
            && !isLoadingCommits
            && !commitReferenceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reviewChanges() async {
        guard authorizeWorkflow() else { return }
        dismissSelection()
        await startRequest(
            "Review the current repository changes. Focus on concrete bugs, regressions, security issues, and missing tests.",
            mode: .fixedTool(.workingTreeChanges),
            contextTitle: "Repository analysis",
            conversationTitle: "Review changes"
        )
    }

    func prepareCommitExplanation() async {
        guard authorizeWorkflow() else { return }
        guard !isRunning, !isLoadingCommits else { return }
        dismissSelection()
        isChoosingCommit = true
        isLoadingCommits = true
        let commits = await gitService.recentCommits(limit: 10, in: repositoryURL)
        recentCommits = commits.map {
            RepositoryAICommitChoice(hash: $0.hash, subject: $0.message)
        }
        isLoadingCommits = false
    }

    func explainCommit(_ commit: RepositoryAICommitChoice) async {
        await explainCommit(reference: commit.hash, subject: commit.subject)
    }

    func explainCommitReference() async {
        await explainCommit(reference: commitReferenceDraft, subject: nil)
    }

    func cancelCommitSelection() {
        guard !isRunning, !isLoadingCommits else { return }
        pendingQuickAction = nil
        isChoosingCommit = false
        commitReferenceDraft = ""
    }

    func prepareFileReview() async {
        guard authorizeWorkflow() else { return }
        guard !isRunning, !isLoadingFiles else { return }
        dismissSelection()
        isChoosingFile = true
        isLoadingFiles = true
        changedFiles = (try? await gitService.listChangedFiles(in: repositoryURL)) ?? []
        isLoadingFiles = false
    }

    func reviewFile(_ reference: RepositoryAIFileReference, includeDiff: Bool = true) async {
        guard authorizeWorkflow() else { return }
        guard !isRunning else { return }
        let pendingQuestion = pendingQuickAction?.action == .reviewFile
            ? pendingQuickAction?.question
            : nil
        dismissSelection()
        await startRequest(
            pendingQuestion ?? (includeDiff
                ? "Review this file diff. Focus on concrete bugs, regressions, security issues, and missing tests."
                : "Explain this selected file context, including behavior and risks."),
            mode: .file(reference, includeDiff: includeDiff),
            contextTitle: reference.displayLabel,
            conversationTitle: "Review \(reference.path)",
            shouldAppendUserMessage: pendingQuestion == nil
        )
    }

    func cancelFileSelection() {
        guard !isRunning, !isLoadingFiles else { return }
        pendingQuickAction = nil
        isChoosingFile = false
        changedFiles.removeAll()
    }

    func prepareRefComparison() {
        guard authorizeWorkflow() else { return }
        guard !isRunning else { return }
        dismissSelection()
        if comparisonHeadDraft.isEmpty { comparisonHeadDraft = "HEAD" }
        isChoosingComparison = true
    }

    func compareRefs() async {
        guard authorizeWorkflow() else { return }
        guard !isRunning else { return }
        guard let base = RepositoryAIRef(comparisonBaseDraft),
              let head = RepositoryAIRef(comparisonHeadDraft) else {
            messages.append(RepositoryAIMessage(role: .assistant, text: RepositoryAIError.invalidRefReference.localizedDescription))
            persistConversation()
            return
        }
        let pendingQuestion = pendingQuickAction?.action == .compareRefs
            ? pendingQuickAction?.question
            : nil
        dismissSelection()
        await startRequest(
            pendingQuestion
                ?? "Compare these refs as a review. Explain meaningful behavior changes, risks, and missing tests.",
            mode: .comparison(base, head),
            contextTitle: "Compare \(base.name) → \(head.name)",
            conversationTitle: "Compare \(base.name) → \(head.name)",
            shouldAppendUserMessage: pendingQuestion == nil
        )
    }

    func cancelRefComparison() {
        guard !isRunning else { return }
        pendingQuickAction = nil
        isChoosingComparison = false
    }

    func preparePullRequestAnalysis() {
        guard authorizeWorkflow() else { return }
        guard !isRunning else { return }
        dismissSelection()
        isChoosingPullRequest = true
    }

    func analyzePullRequest() async {
        guard authorizeWorkflow() else { return }
        guard !isRunning, pullRequestContextLoader != nil, pullRequestFingerprintLoader != nil else { return }
        let number = Int(pullRequestNumberDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        guard number == nil || number! > 0 else {
            messages.append(RepositoryAIMessage(role: .assistant, text: "Enter a positive pull request number."))
            persistConversation()
            return
        }
        let pendingQuestion = pendingQuickAction?.action == .analyzePullRequest
            ? pendingQuickAction?.question
            : nil
        dismissSelection()
        let label = number.map { "Pull request #\($0)" } ?? "Selected pull request"
        await startRequest(
            pendingQuestion
                ?? "Analyze this pull request. Focus on concrete behavior changes, review risks, and missing tests.",
            mode: .pullRequest(number),
            contextTitle: label,
            conversationTitle: label,
            shouldAppendUserMessage: pendingQuestion == nil
        )
    }

    func cancelPullRequestAnalysis() {
        guard !isRunning else { return }
        pendingQuickAction = nil
        isChoosingPullRequest = false
    }

    private func explainCommit(reference: String, subject: String?) async {
        guard authorizeWorkflow() else { return }
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else { return }

        let pendingQuestion = pendingQuickAction?.action == .explainCommit
            ? pendingQuickAction?.question
            : nil
        dismissSelection()
        await startRequest(
            pendingQuestion
                ?? "Explain what this commit changes, why it likely exists, and any behavior or risks a reviewer should understand.",
            mode: .fixedTool(.commitChanges(reference: normalizedReference)),
            contextTitle: "Commit \(normalizedReference)",
            conversationTitle: subject.map { "Explain \($0)" } ?? "Explain \(normalizedReference)",
            shouldAppendUserMessage: pendingQuestion == nil
        )
    }

    func submitDraft() async {
        guard !isInteractionDisabled else { return }
        let question = draft
        draft = ""
        dismissSelection()
        await startRequest(
            question,
            mode: .agent,
            contextTitle: "Repository analysis"
        )
    }

    func startNewConversation() {
        guard !isRunning, !isExecutingMutation, !isExecutingRemoteOperation else { return }
        invalidatePendingMutation(reason: "Conversation reset.", appendTranscript: false)
        invalidatePendingRemoteOperation(reason: "Conversation reset.", appendTranscript: false)
        persistConversation()
        draft = ""
        messages.removeAll()
        dismissSelection()
        conversationTitle = "New conversation"
        conversationSessionID = UUID().uuidString
        conversationPresentationID = UUID()
    }

    func cancelActiveRequest() {
        guard isRunning, !isStopping, let activeRequestTask else { return }
        isStopping = true
        activeRequestTask.cancel()
    }

    func windowWillClose() {
        activeRequestTask?.cancel()
        pendingMutationExpirationTask?.cancel()
        pendingMutationExpirationTask = nil
        pendingRemoteOperationExpirationTask?.cancel()
        pendingRemoteOperationExpirationTask = nil
        pendingMutation = nil
        pendingRemoteOperation = nil
        dismissSelection()
    }

    func confirmPendingMutation(id: UUID) async {
        guard !isExecutingMutation,
              let pending = pendingMutation,
              pending.id == id else { return }
        guard pending.expiresAt > .now else {
            invalidatePendingMutation(reason: "The approval expired. Ask Repository AI to prepare a new proposal.")
            return
        }
        guard pending.conversationID == conversationSessionID else {
            invalidatePendingMutation(reason: "The originating conversation changed.")
            return
        }
        guard pending.providerID == providerController.selectedProviderID else {
            invalidatePendingMutation(reason: "The selected AI provider changed.")
            return
        }
        guard let mutationExecutor else {
            invalidatePendingMutation(reason: RepositoryAIMutationError.unavailable.localizedDescription)
            return
        }

        pendingMutationExpirationTask?.cancel()
        pendingMutationExpirationTask = nil
        pendingMutation = nil
        messages.append(RepositoryAIMessage(role: .assistant, text: "Confirmed — executing \(pending.preview.title.lowercased())."))
        isExecutingMutation = true
        defer { isExecutingMutation = false }

        do {
            let result = try await mutationExecutor.execute(
                pending.validatedMutation,
                in: repositoryURL
            )
            messages.append(RepositoryAIMessage(role: .assistant, text: result.summary))
        } catch let error as RepositoryAIMutationError {
            let prefix: String
            if case .stale = error {
                prefix = "Stale"
            } else if case .rejected = error {
                prefix = "Rejected"
            } else {
                prefix = "Failed"
            }
            messages.append(RepositoryAIMessage(
                role: .assistant,
                text: "\(prefix) — \(error.localizedDescription)"
            ))
        } catch {
            messages.append(RepositoryAIMessage(
                role: .assistant,
                text: "Failed — \(error.localizedDescription)"
            ))
        }
    }

    func cancelPendingMutation() {
        guard let pendingMutation, !isExecutingMutation else { return }
        self.pendingMutation = nil
        pendingMutationExpirationTask?.cancel()
        pendingMutationExpirationTask = nil
        messages.append(RepositoryAIMessage(
            role: .assistant,
            text: "Cancelled — \(pendingMutation.preview.title) was not run."
        ))
        persistConversation()
    }

    func confirmPendingRemoteOperation(
        id: UUID,
        execute: (RepositoryAIValidatedRemoteOperation) async throws -> RepositoryAIRemoteOperationExecutionResult
    ) async {
        guard !isExecutingRemoteOperation,
              let pending = pendingRemoteOperation,
              pending.id == id else { return }
        guard pending.expiresAt > .now else {
            invalidatePendingRemoteOperation(reason: "The approval expired. Ask Repository AI to prepare a new proposal.")
            return
        }
        guard pending.conversationID == conversationSessionID else {
            invalidatePendingRemoteOperation(reason: "The originating conversation changed.")
            return
        }
        guard pending.providerID == providerController.selectedProviderID else {
            invalidatePendingRemoteOperation(reason: "The selected AI provider changed.")
            return
        }

        pendingRemoteOperationExpirationTask?.cancel()
        pendingRemoteOperationExpirationTask = nil
        pendingRemoteOperation = nil
        messages.append(RepositoryAIMessage(
            role: .assistant,
            text: "Confirmed — executing \(pending.preview.title.lowercased())."
        ))
        isExecutingRemoteOperation = true
        defer { isExecutingRemoteOperation = false }

        do {
            let result = try await execute(pending.validatedOperation)
            messages.append(RepositoryAIMessage(role: .assistant, text: result.summary))
        } catch let error as RepositoryAIRemoteOperationError {
            let prefix: String
            switch error {
            case .stale: prefix = "Stale"
            case .rejected: prefix = "Rejected"
            case .cancelled: prefix = "Cancelled"
            case .invalidProviderResponse, .unavailable: prefix = "Failed"
            }
            messages.append(RepositoryAIMessage(role: .assistant, text: "\(prefix) — \(error.localizedDescription)"))
        } catch is CancellationError {
            messages.append(RepositoryAIMessage(role: .assistant, text: "Cancelled — the remote operation was not completed."))
        } catch {
            messages.append(RepositoryAIMessage(role: .assistant, text: "Failed — \(error.localizedDescription)"))
        }
    }

    func cancelPendingRemoteOperation() {
        guard let pendingRemoteOperation, !isExecutingRemoteOperation else { return }
        self.pendingRemoteOperation = nil
        pendingRemoteOperationExpirationTask?.cancel()
        pendingRemoteOperationExpirationTask = nil
        messages.append(RepositoryAIMessage(
            role: .assistant,
            text: "Cancelled — \(pendingRemoteOperation.preview.title) was not run."
        ))
        persistConversation()
    }

    func providerDidChange() {
        if let pendingMutation,
           pendingMutation.providerID != providerController.selectedProviderID {
            invalidatePendingMutation(reason: "The selected AI provider changed.")
        }
        if let pendingRemoteOperation,
           pendingRemoteOperation.providerID != providerController.selectedProviderID {
            invalidatePendingRemoteOperation(reason: "The selected AI provider changed.")
        }
    }

    func repositoryDidChange(_ changedRepositoryURL: URL) {
        guard changedRepositoryURL.standardizedFileURL == repositoryURL.standardizedFileURL else { return }
        invalidatePendingMutation(reason: "Repository state changed. Ask Repository AI to prepare a new proposal.")
        invalidatePendingRemoteOperation(reason: "Repository state changed. Ask Repository AI to prepare a new proposal.")
    }

    func repositoryLocalStateDidRefresh(_ refreshedRepositoryURL: URL) async {
        guard refreshedRepositoryURL.standardizedFileURL == repositoryURL.standardizedFileURL else { return }
        if let pending = pendingMutation, let mutationContextProvider {
            do {
                let context = try await mutationContextProvider.context(in: repositoryURL)
                guard pendingMutation?.id == pending.id else { return }
                if !RepositoryAIMutationPolicy.isCurrent(
                    pending.precondition,
                    proposal: pending.proposal,
                    context: context
                ) {
                    invalidatePendingMutation(
                        reason: "Repository state changed. Ask Repository AI to prepare a new proposal."
                    )
                }
            } catch {
                guard pendingMutation?.id == pending.id else { return }
                invalidatePendingMutation(
                    reason: "The current repository state could not be revalidated."
                )
            }
        }
        await revalidatePendingRemoteOperation()
    }

    func invalidatePendingMutation(reason: String, appendTranscript: Bool = true) {
        guard pendingMutation != nil else { return }
        pendingMutation = nil
        pendingMutationExpirationTask?.cancel()
        pendingMutationExpirationTask = nil
        if appendTranscript {
            messages.append(RepositoryAIMessage(role: .assistant, text: "Stale — \(reason)"))
            persistConversation()
        }
    }

    func repositoryRemoteRefsDidRefresh(_ refreshedRepositoryURL: URL) async {
        guard refreshedRepositoryURL.standardizedFileURL == repositoryURL.standardizedFileURL else { return }
        await revalidatePendingRemoteOperation()
    }

    func invalidatePendingRemoteOperation(reason: String, appendTranscript: Bool = true) {
        guard pendingRemoteOperation != nil else { return }
        pendingRemoteOperation = nil
        pendingRemoteOperationExpirationTask?.cancel()
        pendingRemoteOperationExpirationTask = nil
        if appendTranscript {
            messages.append(RepositoryAIMessage(role: .assistant, text: "Stale — \(reason)"))
            persistConversation()
        }
    }

    private func dismissSelection() {
        pendingQuickAction = nil
        commitReferenceDraft = ""
        recentCommits.removeAll()
        isChoosingCommit = false
        isChoosingFile = false
        isChoosingComparison = false
        isChoosingPullRequest = false
        isLoadingCommits = false
        isLoadingFiles = false
        changedFiles.removeAll()
    }

    private func startRequest(
        _ question: String,
        mode: RepositoryAIRequestMode,
        contextTitle: String,
        conversationTitle preferredTitle: String? = nil,
        shouldAppendUserMessage: Bool = true
    ) async {
        guard activeRequestTask == nil else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.ask(
                question,
                mode: mode,
                contextTitle: contextTitle,
                conversationTitle: preferredTitle,
                shouldAppendUserMessage: shouldAppendUserMessage
            )
        }
        activeRequestTask = task
        await task.value
        activeRequestTask = nil
        isStopping = false
    }

    private func ask(
        _ question: String,
        mode: RepositoryAIRequestMode,
        contextTitle: String,
        conversationTitle preferredTitle: String? = nil,
        shouldAppendUserMessage: Bool
    ) async {
        switch mode {
        case .agent:
            break // Free chat retains all existing Git tools.
        case .fixedTool, .file, .comparison, .pullRequest:
            guard authorizeWorkflow() else { return }
        }
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !isRunning,
              !isExecutingMutation,
              !isExecutingRemoteOperation,
              pendingMutation == nil,
              pendingRemoteOperation == nil else { return }

        if messages.isEmpty {
            conversationTitle = makeConversationTitle(from: preferredTitle ?? normalized)
        }
        if shouldAppendUserMessage {
            messages.append(RepositoryAIMessage(
                role: .user,
                text: normalized,
                contextTitle: contextTitle
            ))
        }
        persistConversation()
        isRunning = true
        defer { isRunning = false }

        var streamingMessageID: UUID?
        do {
            try Task.checkCancellation()
            let branch = await gitService.currentBranch(in: repositoryURL)
            try Task.checkCancellation()
            switch mode {
            case .agent:
                let result = try await providerController.answerRepositoryQuestionWithAgent(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    conversation: messages,
                    allowsBuiltInWorkflows: workflowAccessDecision().isAllowed
                )
                try Task.checkCancellation()
                if let quickAction = result.quickAction {
                    try await handleQuickAction(
                        quickAction,
                        question: normalized,
                        branch: branch,
                        streamingMessageID: &streamingMessageID
                    )
                } else if let workflow = result.mutationWorkflow {
                    await prepareMutationWorkflow(workflow)
                } else if let mutation = result.mutation {
                    presentPendingMutation(
                        mutation,
                        transcript: "Approval required — review the exact impact before confirming \(mutation.preview.title.lowercased())."
                    )
                } else if let remoteOperation = result.remoteOperation {
                    presentPendingRemoteOperation(remoteOperation)
                } else {
                    for toolResult in result.toolResults {
                        messages.append(RepositoryAIMessage(
                            role: .toolActivity,
                            text: toolResult.commandResult.displayCommand,
                            toolResult: toolResult
                        ))
                    }
                    messages.append(RepositoryAIMessage(role: .assistant, text: result.answer))
                }
            case .fixedTool(let tool):
                let messageID = beginStreamingAssistant()
                streamingMessageID = messageID
                let response = try await providerController.answerRepositoryQuestion(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    tool: tool,
                    sessionID: conversationSessionID,
                    onTextDelta: { [weak self] delta in
                        await self?.appendStreamingDelta(delta, to: messageID)
                    }
                )
                completeStreamingAssistant(messageID, with: response)
                streamingMessageID = nil
            case .file(let reference, let includeDiff):
                let response = try await providerController.answerRepositoryFileQuestion(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    reference: reference,
                    includeDiff: includeDiff,
                    sessionID: conversationSessionID
                )
                messages.append(RepositoryAIMessage(
                    role: .assistant,
                    text: response.answer.text,
                    citations: response.answer.citations,
                    evidenceManifest: response.manifest
                ))
            case .comparison(let base, let head):
                let budget = providerController.selectedDescriptor.inputCharacterBudget
                let comparison = try await gitService.compareRefs(
                    base: base,
                    head: head,
                    in: repositoryURL,
                    characterBudget: budget
                )
                let messageID = beginStreamingAssistant()
                streamingMessageID = messageID
                let response = try await providerController.answerRepositoryAnalysisQuestion(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    result: comparison.toolResult(characterBudget: budget),
                    currentFingerprint: { [gitService, repositoryURL] in
                        try await gitService.currentComparisonFingerprint(base: base, head: head, in: repositoryURL)
                    },
                    sessionID: conversationSessionID,
                    onTextDelta: { [weak self] delta in
                        await self?.appendStreamingDelta(delta, to: messageID)
                    }
                )
                completeStreamingAssistant(messageID, with: response)
                streamingMessageID = nil
            case .pullRequest(let number):
                guard let pullRequestContextLoader, let pullRequestFingerprintLoader else {
                    throw RepositoryAIError.noRepositoryData("an authenticated pull request for the current repository")
                }
                let context = try await pullRequestContextLoader(number, repositoryURL)
                let messageID = beginStreamingAssistant()
                streamingMessageID = messageID
                let response = try await providerController.answerRepositoryAnalysisQuestion(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    result: context.toolResult(characterBudget: providerController.selectedDescriptor.inputCharacterBudget),
                    currentFingerprint: {
                        try await pullRequestFingerprintLoader(context.detail.summary.number, self.repositoryURL)
                    },
                    sessionID: conversationSessionID,
                    onTextDelta: { [weak self] delta in
                        await self?.appendStreamingDelta(delta, to: messageID)
                    }
                )
                completeStreamingAssistant(messageID, with: response)
                streamingMessageID = nil
            }
        } catch is CancellationError {
            finishInterruptedAssistant(streamingMessageID)
            messages.append(RepositoryAIMessage(role: .assistant, text: "The AI request was cancelled."))
        } catch let error as RepositoryAIMutationError {
            finishInterruptedAssistant(streamingMessageID)
            messages.append(RepositoryAIMessage(
                role: .assistant,
                text: "Rejected — \(error.localizedDescription)"
            ))
        } catch let error as RepositoryAIRemoteOperationError {
            finishInterruptedAssistant(streamingMessageID)
            messages.append(RepositoryAIMessage(
                role: .assistant,
                text: "Rejected — \(error.localizedDescription)"
            ))
        } catch {
            finishInterruptedAssistant(streamingMessageID)
            let wasCancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
            messages.append(RepositoryAIMessage(
                role: .assistant,
                text: wasCancelled ? "The AI request was cancelled." : error.localizedDescription
            ))
        }
    }

    private func beginStreamingAssistant() -> UUID {
        let message = RepositoryAIMessage(role: .assistant, text: "Generating analysis…")
        messages.append(message)
        return message.id
    }

    private func appendStreamingDelta(_ delta: String, to id: UUID) {
        guard !isStopping, !Task.isCancelled else { return }
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        let existingText = message.text == "Generating analysis…" ? "" : message.text
        messages[index] = RepositoryAIMessage(
            id: message.id,
            role: message.role,
            text: existingText + delta,
            contextTitle: message.contextTitle,
            toolResult: message.toolResult,
            citations: message.citations,
            evidenceManifest: message.evidenceManifest
        )
        streamingRevision &+= 1
    }

    private func completeStreamingAssistant(_ id: UUID, with answer: RepositoryAIAnswer) {
        guard !isStopping, !Task.isCancelled else { return }
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        let truncationNotice = answer.isTruncated
            ? "\n\n> The provider reached its output limit. Ask “continue” to finish this analysis."
            : ""
        messages[index] = RepositoryAIMessage(
            id: message.id,
            role: message.role,
            text: answer.text + truncationNotice,
            contextTitle: message.contextTitle,
            toolResult: message.toolResult,
            citations: message.citations,
            evidenceManifest: message.evidenceManifest
        )
        streamingRevision &+= 1
    }

    private func prepareMutationWorkflow(_ workflow: RepositoryAIMutationWorkflow) async {
        switch workflow {
        case .commitAllChanges:
            guard let commitAllPreparer else {
                messages.append(RepositoryAIMessage(
                    role: .assistant,
                    text: "Rejected — the Commit All Changes workflow is unavailable in this repository window."
                ))
                return
            }

            messages.append(RepositoryAIMessage(
                role: .assistant,
                text: "Planned — stage all current changes automatically, generate a commit message, then ask before creating the commit."
            ))
            isExecutingMutation = true
            defer { isExecutingMutation = false }

            do {
                let preparation = try await commitAllPreparer.prepare(in: repositoryURL)
                messages.append(RepositoryAIMessage(role: .assistant, text: preparation.stageSummary))
                presentPendingMutation(
                    preparation.commitMutation,
                    transcript: "Approval required — all current changes are staged. Review the generated message before creating the commit."
                )
            } catch let error as RepositoryAICommitAllPreparationError {
                let prefix = error == .cancelledAfterStaging ? "Cancelled" : "Failed"
                messages.append(RepositoryAIMessage(
                    role: .assistant,
                    text: "\(prefix) — \(error.localizedDescription)"
                ))
            } catch let error as RepositoryAIMutationError {
                let prefix: String
                if case .stale = error {
                    prefix = "Stale"
                } else if case .rejected = error {
                    prefix = "Rejected"
                } else {
                    prefix = "Failed"
                }
                messages.append(RepositoryAIMessage(
                    role: .assistant,
                    text: "\(prefix) — \(error.localizedDescription)"
                ))
            } catch is CancellationError {
                messages.append(RepositoryAIMessage(
                    role: .assistant,
                    text: "Cancelled — the Commit All Changes workflow stopped. Any completed staging remains available through Git Undo."
                ))
            } catch {
                messages.append(RepositoryAIMessage(
                    role: .assistant,
                    text: "Failed — \(error.localizedDescription)"
                ))
            }
        }
    }

    private func presentPendingMutation(
        _ mutation: RepositoryAIValidatedMutation,
        transcript: String
    ) {
        let originatingMessageID = messages.last(where: { $0.role == .user })?.id ?? UUID()
        let pending = PendingRepositoryAIMutation(
            validatedMutation: mutation,
            conversationID: conversationSessionID,
            originatingMessageID: originatingMessageID,
            providerID: providerController.selectedProviderID
        )
        pendingMutation = pending
        messages.append(RepositoryAIMessage(role: .assistant, text: transcript))
        scheduleExpiration(for: pending)
    }

    private func presentPendingRemoteOperation(_ operation: RepositoryAIValidatedRemoteOperation) {
        let originatingMessageID = messages.last(where: { $0.role == .user })?.id ?? UUID()
        let pending = PendingRepositoryAIRemoteOperation(
            validatedOperation: operation,
            conversationID: conversationSessionID,
            originatingMessageID: originatingMessageID,
            providerID: providerController.selectedProviderID
        )
        pendingRemoteOperation = pending
        messages.append(RepositoryAIMessage(
            role: .assistant,
            text: "Approval required — review the exact remote target and preflight before confirming \(operation.preview.title.lowercased())."
        ))
        scheduleExpiration(for: pending)
    }

    private func finishInterruptedAssistant(_ id: UUID?) {
        guard let id, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              message.text != "Generating analysis…" else {
            messages.remove(at: index)
            return
        }
        messages[index] = RepositoryAIMessage(
            id: message.id,
            role: message.role,
            text: message.text + "\n\n> Response interrupted before completion.",
            contextTitle: message.contextTitle,
            toolResult: message.toolResult,
            citations: message.citations,
            evidenceManifest: message.evidenceManifest
        )
    }

    @discardableResult
    private func authorizeWorkflow() -> Bool {
        switch workflowAccessDecision() {
        case .allowed:
            return true
        case .denied(let denial):
            workflowAccessNotice = FeatureAccessNotice(feature: .repositoryAIActions, denial: denial)
            return false
        }
    }

    private func handleQuickAction(
        _ action: RepositoryAIQuickAction,
        question: String,
        branch: String?,
        streamingMessageID: inout UUID?
    ) async throws {
        guard authorizeWorkflow() else {
            messages.append(RepositoryAIMessage(
                role: .assistant,
                text: "This built-in Repository AI workflow requires Pro. You can continue chatting and using Git tools."
            ))
            return
        }
        switch action {
        case .reviewChanges:
            let messageID = beginStreamingAssistant()
            streamingMessageID = messageID
            let response = try await providerController.answerRepositoryQuestion(
                repositoryURL: repositoryURL,
                branchName: branch,
                question: question,
                tool: .workingTreeChanges,
                sessionID: conversationSessionID,
                onTextDelta: { [weak self] delta in
                    await self?.appendStreamingDelta(delta, to: messageID)
                }
            )
            completeStreamingAssistant(messageID, with: response)
            streamingMessageID = nil
        case .explainCommit:
            pendingQuickAction = (action, question)
            isChoosingCommit = true
            isLoadingCommits = true
            let commits = await gitService.recentCommits(limit: 10, in: repositoryURL)
            recentCommits = commits.map {
                RepositoryAICommitChoice(hash: $0.hash, subject: $0.message)
            }
            isLoadingCommits = false
        case .reviewFile:
            pendingQuickAction = (action, question)
            isChoosingFile = true
            isLoadingFiles = true
            changedFiles = (try? await gitService.listChangedFiles(in: repositoryURL)) ?? []
            isLoadingFiles = false
        case .compareRefs:
            pendingQuickAction = (action, question)
            if comparisonHeadDraft.isEmpty { comparisonHeadDraft = "HEAD" }
            isChoosingComparison = true
        case .analyzePullRequest:
            pendingQuickAction = (action, question)
            isChoosingPullRequest = true
        }
    }

    private enum RepositoryAIRequestMode {
        case agent
        case fixedTool(RepositoryAIToolCall)
        case file(RepositoryAIFileReference, includeDiff: Bool)
        case comparison(RepositoryAIRef, RepositoryAIRef)
        case pullRequest(Int?)
    }

    private func makeConversationTitle(from text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let title = words.prefix(5).joined(separator: " ")
        guard words.count > 5 else { return title }
        return "\(title)…"
    }

    private func scheduleExpiration(for pending: PendingRepositoryAIMutation) {
        pendingMutationExpirationTask?.cancel()
        let delay = max(0, pending.expiresAt.timeIntervalSinceNow)
        pendingMutationExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, self.pendingMutation?.id == pending.id else { return }
            self.invalidatePendingMutation(
                reason: "The approval expired. Ask Repository AI to prepare a new proposal."
            )
        }
    }

    private func scheduleExpiration(for pending: PendingRepositoryAIRemoteOperation) {
        pendingRemoteOperationExpirationTask?.cancel()
        let delay = max(0, pending.expiresAt.timeIntervalSinceNow)
        pendingRemoteOperationExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, self.pendingRemoteOperation?.id == pending.id else { return }
            self.invalidatePendingRemoteOperation(
                reason: "The approval expired. Ask Repository AI to prepare a new proposal."
            )
        }
    }

    private func revalidatePendingRemoteOperation() async {
        guard let pending = pendingRemoteOperation,
              let remoteOperationContextProvider else { return }
        do {
            let context = try await remoteOperationContextProvider.context(in: repositoryURL)
            guard pendingRemoteOperation?.id == pending.id else { return }
            if !RepositoryAIRemoteOperationPolicy.isCurrent(
                pending.validatedOperation,
                context: context
            ) {
                invalidatePendingRemoteOperation(
                    reason: "Remote or repository state changed. Ask Repository AI to prepare a new proposal."
                )
            }
        } catch {
            guard pendingRemoteOperation?.id == pending.id else { return }
            invalidatePendingRemoteOperation(
                reason: "The current remote state could not be revalidated."
            )
        }
    }
}
