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
import SwiftUI

struct RepositoryAIChatView: View {
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @EnvironmentObject private var accountController: AccountSessionController

    private var workflowAccess: FeatureAccessDecision {
        featureAccessController.decision(for: .repositoryAIActions, entitlement: accountController.entitlement)
    }

    private var providerAccess: FeatureAccessDecision {
        featureAccessController.decision(for: .aiBringYourOwnKey, entitlement: accountController.entitlement)
    }

    @ObservedObject var controller: RepositoryAIChatController
    @ObservedObject var providerController: AIProviderController
    let accessDecision: FeatureAccessDecision
    let isSignedIn: Bool
    let onRequestAccess: () -> Void
    let onExecuteRemoteOperation: (RepositoryAIValidatedRemoteOperation) async throws -> RepositoryAIRemoteOperationExecutionResult
    @State private var isShowingQuickActions = false
    @State private var isShowingHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(controller.conversationTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button("Conversation history", systemImage: "clock.arrow.circlepath") { isShowingHistory = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(controller.isInteractionDisabled)
                    .help("Conversation History")

                Button("New conversation", systemImage: "plus", action: controller.startNewConversation)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(controller.isInteractionDisabled)
                    .help("New Conversation")
            }

            if controller.isChoosingCommit {
                RepositoryAICommitPickerView(
                    controller: controller,
                    onSelectCommit: explainCommit,
                    onSubmitReference: explainCommitReference
                )
            } else if controller.isChoosingFile {
                RepositoryAIFilePickerView(controller: controller, onSelect: reviewFile)
            } else if controller.isChoosingComparison {
                RepositoryAIRefComparisonPickerView(controller: controller, onSubmit: compareRefs)
            } else if controller.isChoosingPullRequest {
                RepositoryAIPullRequestPickerView(controller: controller, onSubmit: analyzePullRequest)
            } else if controller.messages.isEmpty {
                welcomeContent
            } else {
                transcript
            }

            if let error = controller.historyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            composer
        }
        .padding(16)
        .task {
            await providerController.refreshAvailability()
        }
        .sheet(isPresented: $isShowingHistory) {
            RepositoryAIChatHistorySheet(controller: controller)
        }
        .sheet(item: $controller.pendingMutation, onDismiss: controller.cancelPendingMutation) { pending in
            RepositoryAIMutationConfirmationSheet(
                pending: pending,
                isExecuting: controller.isExecutingMutation,
                onCancel: controller.cancelPendingMutation,
                onConfirm: { confirmPendingMutation(pending.id) }
            )
        }
        .sheet(
            item: $controller.pendingRemoteOperation,
            onDismiss: controller.cancelPendingRemoteOperation
        ) { pending in
            RepositoryAIRemoteOperationConfirmationSheet(
                pending: pending,
                isExecuting: controller.isExecutingRemoteOperation,
                onCancel: controller.cancelPendingRemoteOperation,
                onConfirm: { confirmPendingRemoteOperation(pending.id) }
            )
        }
        .onChange(of: providerController.selectedProviderID) {
            controller.providerDidChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            guard let repositoryURL = notification.userInfo?["repositoryURL"] as? URL else { return }
            controller.repositoryDidChange(repositoryURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh)) { notification in
            guard let repositoryURL = notification.userInfo?["repositoryURL"] as? URL else { return }
            Task { await controller.repositoryLocalStateDidRefresh(repositoryURL) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryRemoteRefsDidRefresh)) { notification in
            guard let repositoryURL = notification.userInfo?["repositoryURL"] as? URL else { return }
            Task { await controller.repositoryRemoteRefsDidRefresh(repositoryURL) }
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Repository AI", systemImage: "sparkles")
                    .font(.headline)
                Text("Review local changes, compare refs, or analyze an authenticated pull request.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(action: runReviewChanges) {
                quickActionLabel(
                    title: "Review changes",
                    detail: "Find bugs, regressions, and missing tests",
                    systemImage: "checkmark.bubble"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isInteractionDisabled)

            Button(action: runExplainCommit) {
                quickActionLabel(
                    title: "Explain commit",
                    detail: "Summarize intent, behavior, and risks",
                    systemImage: "text.magnifyingglass"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isInteractionDisabled)

            Button(action: runReviewFile) {
                quickActionLabel(
                    title: "Review file",
                    detail: "Inspect a staged or working-tree file diff",
                    systemImage: "doc.text.magnifyingglass"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isInteractionDisabled)

            Button(action: runCompareRefs) {
                quickActionLabel(
                    title: "Compare branches or refs",
                    detail: "Review a bounded three-dot diff",
                    systemImage: "arrow.left.arrow.right"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isInteractionDisabled)

            Button(action: runAnalyzePullRequest) {
                quickActionLabel(
                    title: "Analyze pull request",
                    detail: "Use current-repository GitHub or GitLab context",
                    systemImage: "arrow.triangle.branch"
                )
            }
            .buttonStyle(.plain)
            .disabled(controller.isInteractionDisabled)

            if !accessDecision.isAllowed {
                Button(accessButtonTitle, systemImage: "lock.open", action: onRequestAccess)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var transcript: some View {
        RepositoryAIChatTranscriptView(controller: controller)
            .id(controller.conversationPresentationID)
            .frame(maxHeight: .infinity)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ask about this context", text: $controller.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .frame(minHeight: 28, alignment: .topLeading)
                .disabled(controller.isInteractionDisabled)
                .onSubmit(submitDraft)

            HStack(spacing: 8) {
                Button("Quick actions", systemImage: "plus") {
                    isShowingQuickActions = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .disabled(controller.isInteractionDisabled)
                .help("Quick actions")
                .popover(isPresented: $isShowingQuickActions, arrowEdge: .bottom) {
                    quickActionsPopover
                }

                Spacer(minLength: 0)

                AIProviderMenu(
                    controller: providerController,
                    restrictedProviderAccess: providerAccess,
                    showsConfigureAction: true,
                    labelMode: .model
                )

                if controller.isRunning || controller.isStopping {
                    Button(action: controller.cancelActiveRequest) {
                        Image(systemName: "stop.fill")
                            .opacity(controller.isStopping ? 0 : 1)
                            .overlay {
                                if controller.isStopping {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .disabled(controller.isStopping)
                    .accessibilityLabel(controller.isStopping ? "Stopping generation" : "Stop generating")
                    .help(controller.isStopping ? "Stopping generation…" : "Stop generating")
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            (controller.isStopping ? NSCursor.arrow : NSCursor.pointingHand).set()
                        case .ended:
                            NSCursor.arrow.set()
                        }
                    }
                    .onChange(of: controller.isStopping) { _, stopping in
                        if stopping { NSCursor.arrow.set() }
                    }
                    .onDisappear { NSCursor.arrow.set() }
                } else {
                    Button("Send question", systemImage: "arrow.up", action: submitDraft)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .disabled(!controller.canSubmit || !providerController.selectedProviderAvailability.isAvailable)
                        .help(providerController.selectedProviderAvailability.isAvailable ? "Send" : providerController.selectedProviderAvailability.detail)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.primary.opacity(0.075))
                .stroke(.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var quickActionsPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quick actions")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            quickActionButton(
                title: "Review changes",
                detail: "Find bugs, regressions, and missing tests",
                systemImage: "checkmark.bubble",
                action: runReviewChanges
            )
            quickActionButton(
                title: "Explain commit",
                detail: "Summarize intent, behavior, and risks",
                systemImage: "text.magnifyingglass",
                action: runExplainCommit
            )
            quickActionButton(
                title: "Review file",
                detail: "Inspect a staged or working-tree file diff",
                systemImage: "doc.text.magnifyingglass",
                action: runReviewFile
            )
            quickActionButton(
                title: "Compare branches or refs",
                detail: "Review a bounded three-dot diff",
                systemImage: "arrow.left.arrow.right",
                action: runCompareRefs
            )
            quickActionButton(
                title: "Analyze pull request",
                detail: "Use current-repository GitHub or GitLab context",
                systemImage: "arrow.triangle.branch",
                action: runAnalyzePullRequest
            )
        }
        .padding(.bottom, 8)
        .frame(width: 320)
    }

    private func quickActionButton(
        title: String,
        detail: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            isShowingQuickActions = false
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !workflowAccess.isAllowed {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Requires Pro")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var accessButtonTitle: String {
        isSignedIn ? "Upgrade to use Repository AI" : "Sign in to use Repository AI"
    }

    private func quickActionLabel(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: workflowAccess.isAllowed ? "chevron.right" : "lock.fill")
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .contentShape(.rect)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.primary.opacity(0.075))
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private func runReviewChanges() {
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        Task { await controller.reviewChanges() }
    }

    private func runExplainCommit() {
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        Task { await controller.prepareCommitExplanation() }
    }

    private func runReviewFile() {
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        Task { await controller.prepareFileReview() }
    }

    private func runCompareRefs() {
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        controller.prepareRefComparison()
    }

    private func runAnalyzePullRequest() {
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        controller.preparePullRequestAnalysis()
    }

    private func reviewFile(_ file: RepositoryAIFileReference) {
        Task { await controller.reviewFile(file) }
    }

    private func explainCommit(_ commit: RepositoryAICommitChoice) {
        Task { await controller.explainCommit(commit) }
    }

    private func explainCommitReference() {
        Task { await controller.explainCommitReference() }
    }

    private func compareRefs() {
        Task { await controller.compareRefs() }
    }

    private func analyzePullRequest() {
        Task { await controller.analyzePullRequest() }
    }

    private func submitDraft() {
        guard providerController.selectedProviderAvailability.isAvailable else { return }
        guard accessDecision.isAllowed else {
            onRequestAccess()
            return
        }
        Task { await controller.submitDraft() }
    }

    private func confirmPendingMutation(_ id: UUID) {
        Task { await controller.confirmPendingMutation(id: id) }
    }

    private func confirmPendingRemoteOperation(_ id: UUID) {
        Task {
            await controller.confirmPendingRemoteOperation(
                id: id,
                execute: onExecuteRemoteOperation
            )
        }
    }
}
