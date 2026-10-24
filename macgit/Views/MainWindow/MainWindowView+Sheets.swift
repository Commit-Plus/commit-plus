//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

extension MainWindowView {
    @ViewBuilder
    var commitSheet: some View {
        CommitSheetView(
            aiProviderController: aiProviderController,
            message: $toolbarCommitMessage,
            repositoryURL: repositoryURL,
            hasStagedChanges: syncState.stagedBadgeCount > 0,
            commitsAllChanges: commitSheetCommitsAllChanges
        ) { message, commitAllChanges in
            try await commitFromToolbar(message: message, commitAllChanges: commitAllChanges)
        }
        .replacingSheet(item: $protectedBranchCommitController.warning,
                        onDismiss: { protectedBranchCommitController.finish(.cancel) }) { warning in
            ProtectedBranchCommitSheet(warning: warning, skipWarnings: $repoSettings.skipProtectedBranchCommitWarnings) { decision in
                protectedBranchCommitController.finish(decision)
            }
            .onChange(of: repoSettings.skipProtectedBranchCommitWarnings) { _, _ in commitRulePreferenceChanged() }
        }
    }

    @ViewBuilder
    var pullSheet: some View {
        PullSheetView(
            repositoryURL: repositoryURL,
            preselectedRemote: repoSettings.defaultRemoteName,
            preselectedBranch: resolvedPullPreselectedBranch(),
            defaultPullStrategy: repoSettings.pullStrategy
        ) { remote, branch, options in
            runRemoteOperation("Pulling \(remote)/\(branch)...", remotes: [remote]) { credentialResolver in
                guard await waitForBackgroundRemoteActivity() else { return }
                await syncState.performPull(
                    remote: remote,
                    branch: branch,
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    credentialResolver: credentialResolver
                )
            }
        }
    }

    @ViewBuilder
    var pushSheet: some View {
        PushSheetView(repositoryURL: repositoryURL, defaultRemote: repoSettings.defaultRemoteName,
                      preselectedRemote: pushSheetSelection?.remote,
                      preselectedBranch: pushSheetSelection?.branch,
                      preselectedRemoteBranch: pushSheetSelection?.remoteBranch,
                      onForcePush: { branch, remote, remoteBranch in
            pendingSheetForcePush = (branch, remote, remoteBranch)
        }) { options in
            runBackgroundRemoteOperation(
                "Pushing to \(options.remote)",
                remotes: [options.remote],
                kind: .push,
                dedupeKey: options
            ) { credentialResolver in
                await syncState.performBackgroundPush(
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    credentialResolver: credentialResolver
                )
            }
        }
    }

    @ViewBuilder
    var fetchSheet: some View {
        FetchSheetView(repositoryURL: repositoryURL) { options in
            Task {
                guard let credentialResolver = await credentialResolverForFetch(options: options) else { return }
                operationProgress.runInBackground(title: "Fetching remotes", kind: .fetch, dedupeKey: options) {
                    await syncState.performBackgroundFetch(
                        options: options,
                        repositoryURL: repositoryURL,
                        credentialResolver: credentialResolver
                    )
                }
            }
        }
    }

    @ViewBuilder
    var addSubmoduleSheet: some View {
        AddSubmoduleSheet(
            repositoryURL: repositoryURL,
            onAdd: { request in
                try await GitStatusService.shared.addSubmodule(
                    request,
                    in: repositoryURL,
                    credentialResolver: providerCredentialResolver
                )
            },
            onCompleted: { request in
                appState.showSubmodules = true
                selectedItem = .submodule(request.path)
            },
            onRunRepositoryOperation: runRepositoryOperation
        )
    }

    @ViewBuilder
    var addLinkSubtreeSheet: some View {
        AddLinkSubtreeSheet(
            repositoryURL: repositoryURL,
            onAdd: { request in
                try await GitStatusService.shared.addSubtree(
                    request,
                    in: repositoryURL,
                    credentialResolver: providerCredentialResolver
                )
            },
            onLink: { request in
                try await GitStatusService.shared.linkExistingSubtree(request, in: repositoryURL)
            },
            onCompleted: { entry in
                appState.showSubtrees = true
                selectedItem = .subtree(entry.id)
            },
            onRunRepositoryOperation: runRepositoryOperation
        )
    }

    @ViewBuilder
    func branchSheet(startPoint: GitBranchStartPoint?, initialBranchName: String? = nil) -> some View {
        BranchSheetView(
            repositoryURL: repositoryURL,
            undoManager: undoManager,
            initialStartPoint: startPoint,
            initialBranchName: initialBranchName,
            onRunBackgroundRemoteBranchDeletion: runBackgroundRemoteBranchDeletion,
            onCommitAllChangesRequested: {
                commitSheetCommitsAllChanges = true
                showCommitSheetIfNoConflicts()
            },
            onRunRepositoryOperation: runRepositoryOperation,
            onCompleted: {
                Task {
                    await syncState.refresh(repositoryURL: repositoryURL)
                    NotificationCenter.default.post(
                        name: .repositoryDidChange,
                        object: nil,
                        userInfo: ["repositoryURL": repositoryURL]
                    )
                }
            }
        )
    }

    @ViewBuilder
    var tagSheet: some View {
        if let startPoint = tagStartPoint {
            CreateTagAtReferenceSheet(
                startPoint: startPoint, name: $tagNameInput,
                onCancel: { showingTagSheet = false },
                onCreate: { name in
                    try await createTagAtReference(name: name, startPoint: startPoint)
                },
                onCompleted: {
                    showingTagSheet = false
                    Task {
                        await syncState.refresh(repositoryURL: repositoryURL)
                        NotificationCenter.default.post(name: .repositoryDidChange, object: nil,
                                                        userInfo: ["repositoryURL": repositoryURL])
                    }
                }
            )
        }
    }

    @ViewBuilder
    var newTagSheet: some View {
        TagSheetView(
            repositoryURL: repositoryURL,
            onRunRepositoryOperation: runRepositoryOperation,
            onCreate: { request in
                try await createTag(from: request)
            }
        )
    }

    @ViewBuilder
    var renameSheet: some View {
        RenameBranchSheetView(
            repositoryURL: repositoryURL,
            currentName: branchToRename,
            undoManager: undoManager,
            onRunRepositoryOperation: runRepositoryOperation,
            onCompleted: {
                Task {
                    await syncState.refresh(repositoryURL: repositoryURL)
                    NotificationCenter.default.post(
                        name: .repositoryDidChange,
                        object: nil,
                        userInfo: ["repositoryURL": repositoryURL]
                    )
                }
            }
        )
        .id(branchToRename)
    }

    @ViewBuilder
    func commitDropConfirmationSheet(for confirmation: PendingCommitDropConfirmation) -> some View {
        GitDragActionConfirmationSheet(
            title: "Cherry-pick Commits",
            message: "Cherry-pick the selected commits into the current HEAD branch.",
            targetBranchName: confirmation.targetBranch,
            commits: confirmation.commits,
            primaryActionTitle: "Cherry-pick",
            onConfirm: {
                let request = confirmation
                pendingCommitDropConfirmation = nil
                runRepositoryOperation("Cherry-picking commits...") {
                    await performCommitDropCherryPick(request)
                }
            },
            onCancel: {
                pendingCommitDropConfirmation = nil
            }
        )
    }

    @ViewBuilder
    func branchDropConfirmationSheet(for confirmation: PendingBranchDropConfirmation) -> some View {
        GitDragActionConfirmationSheet(
            title: "Merge or Rebase Branch",
            message: "Review the branch action before continuing.",
            sourceBranchName: confirmation.sourceBranch,
            targetBranchName: confirmation.targetBranch,
            commits: [],
            primaryActionTitle: "Continue",
            selectedBranchOperation: Binding(
                get: { pendingBranchDropConfirmation?.operation ?? confirmation.operation },
                set: { newValue in
                    guard var pending = pendingBranchDropConfirmation else { return }
                    pending.operation = newValue
                    pendingBranchDropConfirmation = pending
                }
            ),
            onConfirm: {
                guard let request = pendingBranchDropConfirmation else { return }
                pendingBranchDropConfirmation = nil
                runRepositoryOperation(request.operation == .merge ? "Merging \(request.sourceBranch)..." : "Rebasing onto \(request.sourceBranch)...") {
                    await performBranchDropOperation(request)
                }
            },
            onCancel: {
                pendingBranchDropConfirmation = nil
            }
        )
    }

    @ViewBuilder
    var mergeSheet: some View {
        MergeSheetView(repositoryURL: repositoryURL) { branch, _, options in
            runRepositoryOperation("Merging \(branch)...") {
                await syncState.performMerge(branch: branch, options: options, repositoryURL: repositoryURL)
            }
        }
    }

    @ViewBuilder
    var stashSheet: some View {
        StashSheetView(paths: pendingStashPaths) { options in
            let pathsToStash = options.paths
            runRepositoryOperation(pathsToStash.isEmpty ? "Stashing changes..." : "Stashing \(pathsToStash.count) files...") {
                await syncState.performStash(
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager
                )
            }
            clearPendingStashPaths()
        }
        .onDisappear {
            clearPendingStashPaths()
        }
    }

    @MainActor
    func clearPendingStashPaths() {
        guard !pendingStashPaths.isEmpty else { return }
        pendingStashPaths = []
    }

    @ViewBuilder
    var stashActionSheet: some View {
        if let ref = pendingStashRef, let action = pendingStashAction {
            StashActionConfirmationSheet(stashRef: ref, action: action) { deleteAfterApplying in
                runRepositoryOperation(action == .apply ? "Applying \(ref)..." : "Deleting \(ref)...") {
                    await performStashAction(
                        ref: ref,
                        action: action,
                        deleteAfterApplying: deleteAfterApplying
                    )
                }
            }
        }
    }

    @ViewBuilder
    var repositorySettingsSheet: some View {
        RepositorySettingsSheetView(
            repositoryURL: repositoryURL,
            onClose: { showingRepositorySettings = false },
            initialSettings: repoSettings,
            initialGitFlowConfiguration: gitFlowConfiguration,
            initiallySelectGitFlow: initiallySelectGitFlowSettings,
            hasInvalidGitFlowConfiguration: gitFlowConfigurationIssue != nil,
            providerAccountResolver: providerAccountController.credentialResolver(
                preferredAccountIDsByRemoteIdentity: providerAccountPreferenceStore.preferences
            ),
            providerAccountPreferences: providerAccountPreferenceStore.preferences,
            onSave: { newSettings in
                let commitRuleChanged = repoSettings.skipProtectedBranchCommitWarnings != newSettings.skipProtectedBranchCommitWarnings
                let uid = commitRuleChanged ? accountController.account?.uid : nil
                Task {
                    do {
                        try await repoSettingsStore.update(for: repositoryURL.path, settings: newSettings, pendingCommitRuleUID: uid)
                        repoSettings = newSettings
                        try? await GitStatusService.shared.updateGitUserConfiguration(
                            useGlobalSettings: newSettings.useGlobalUserSettings,
                            name: newSettings.userName,
                            email: newSettings.userEmail,
                            in: repositoryURL
                        )
                        startBackgroundSyncIfLoaded(settings: newSettings)
                        await refreshRemotePresentation(for: newSettings.defaultRemoteName)
                        if commitRuleChanged { await reconcileCommitRulePreference() }
                    } catch { syncState.showError(error.localizedDescription) }
                }
            },
            onSaveGitFlowConfiguration: { configuration in
                guard await authorizeGitFlowAccess() else { return false }
                do {
                    try await GitFlowPlanner().validate(configuration, in: repositoryURL)
                    let syncWarning = try await gitFlowConfigurationSyncController.save(
                        configuration,
                        repositoryURL: repositoryURL,
                        uid: accountController.account?.uid
                    )
                    await MainActor.run {
                        gitFlowConfiguration = configuration
                        gitFlowConfigurationIssue = nil
                        if let syncWarning {
                            syncState.showError(syncWarning)
                        }
                    }
                    return true
                } catch {
                    await MainActor.run { syncState.showError(error.localizedDescription) }
                    return false
                }
            },
            onAuthorizeGitFlowAccess: { await authorizeGitFlowAccess() },
            onCreateGitFlowDevelopBranch: { request in
                guard await authorizeGitFlowAccess() else {
                    throw GitError.commandFailed("Git Flow access is not available for this repository.")
                }
                let branch = try await GitFlowService().createDevelopBranch(
                    request,
                    in: repositoryURL
                )
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
                return branch
            },
            onSaveProviderAccountPreferences: { preferences in
                Task {
                    do {
                        for (preferenceKey, accountID) in preferences {
                            try await providerAccountPreferenceStore.update(accountID: accountID, forPreferenceKey: preferenceKey)
                        }
                    } catch { syncState.showError(error.localizedDescription) }
                }
            },
            onOpenGitIgnore: openGitIgnoreFile,
            onOpenGitConfig: openGitConfigFile,
            onOpenRemoteURL: { remote in
                openRemoteURL(remote: remote)
            }
        )
    }

    @ViewBuilder
    func startGitFlowSheet(for kind: GitFlowTopicKind, initialTopicName: String? = nil) -> some View {
        StartGitFlowSheet(
            kind: kind,
            configuration: gitFlowConfiguration,
            worktreeRootURL: gitFlowWorktreeRootURL ?? repositoryURL,
            initialTopicName: initialTopicName,
            onRunRepositoryOperation: runRepositoryOperation,
            onStart: startGitFlow
        )
    }

    @ViewBuilder
    func finishGitFlowSheet(for plan: GitFlowFinishPlan) -> some View {
        FinishGitFlowSheet(
            plan: plan,
            onRunRepositoryOperation: runRepositoryOperation,
            onValidateTag: { tag in
                await GitFlowService().tagValidationError(tag, in: repositoryURL)?.localizedDescription
            },
            onFinish: finishGitFlow
        )
    }

    func tagMoveConfirmationSheet(for request: RepositorySheetRequest<(tag: String, commit: GitDraggedCommit)>) -> some View {
        RepositorySheetLoadingView(title: "Move Tag \(request.input.tag)", load: {
            try await loadTagMoveConfirmation(tagName: request.input.tag, commit: request.input.commit)
        }, onCancel: { pendingTagMoveConfirmation = nil }) { confirmation in
            MoveTagConfirmationSheet(
                confirmation: confirmation,
                onConfirm: { remote in
                    try await performTagMove(confirmation, forcePushRemote: remote)
                    pendingTagMoveConfirmation = nil
                    refreshAfterTagAction()
                },
                onCancel: { pendingTagMoveConfirmation = nil }
            )
        }
        .id(request.id)
    }

    func deleteTagConfirmationSheet(for confirmation: PendingTagDeletion) -> some View {
        DeleteTagConfirmationSheet(
            confirmation: confirmation,
            loadRemotes: { await GitStatusService.shared.remotes(in: repositoryURL).sorted() },
            onConfirm: { remote in
                try await deleteTag(confirmation.tag, remote: remote)
                pendingTagDeletion = nil
                refreshAfterTagAction()
            },
            onCancel: {
                if pendingProviderAccountSelection != nil { completeProviderAccountSelection(with: nil) }
                pendingTagDeletion = nil
            }
        )
        .replacingSheet(item: $pendingProviderAccountSelection) { selection in
            GitProviderAccountSelectionSheet(
                selection: selection,
                onSelect: { completeProviderAccountSelection(with: $0) },
                onCancel: { completeProviderAccountSelection(with: nil) }
            )
        }
        .onDisappear {
            if pendingProviderAccountSelection != nil { completeProviderAccountSelection(with: nil) }
        }
    }
}

struct MoveTagConfirmationSheet: View {
    let confirmation: PendingTagMoveConfirmation
    let onConfirm: @MainActor (String?) async throws -> Void
    let onCancel: () -> Void

    @State private var forcePush = false
    @State private var selectedRemote = ""
    @State private var isPerforming = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move Tag \(confirmation.tagName)")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Move the tag to a different commit. This changes the local tag and may require a force-push if it has already been published.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            commitSummary(title: "Current commit", hash: confirmation.currentCommit.commitHash, message: confirmation.currentCommit.subject)

            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            commitSummary(title: "New commit", hash: confirmation.newCommit.hash, message: confirmation.newCommit.message)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Force-push updated tag to remote", isOn: $forcePush)
                    .toggleStyle(.checkbox)
                    .disabled(confirmation.remotes.isEmpty)

                if forcePush {
                    Picker("Remote", selection: $selectedRemote) {
                        ForEach(confirmation.remotes, id: \.self) { remote in
                            Text(remote).tag(remote)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isPerforming)
                if isPerforming { ProgressView().controlSize(.small) }
                Button("Move Tag") {
                    guard !isPerforming else { return }
                    let remote = forcePush ? selectedRemote : nil
                    isPerforming = true
                    errorMessage = nil
                    Task {
                        defer { isPerforming = false }
                        do { try await onConfirm(remote) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(isPerforming || (forcePush && selectedRemote.isEmpty))
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 500, maxWidth: 560)
        .interactiveDismissDisabled(isPerforming)
        .task {
            selectedRemote = confirmation.remotes.first ?? ""
        }
    }

    private func commitSummary(title: String, hash: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(String(hash.prefix(7))) — \(message)")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct DeleteTagConfirmationSheet: View {
    let confirmation: PendingTagDeletion
    let loadRemotes: @MainActor () async -> [String]
    let onConfirm: @MainActor (String?) async throws -> Void
    let onCancel: () -> Void

    @State private var deleteOnRemote = false
    @State private var selectedRemote = ""
    @State private var isPerforming = false
    @State private var errorMessage: String?
    @State private var remotes: [String] = []
    @State private var isLoadingRemotes = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Tag")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Are you sure you want to delete the tag '\(confirmation.tag)'?")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Also delete on remote", isOn: $deleteOnRemote)
                    .toggleStyle(.checkbox)
                    .disabled(isLoadingRemotes || remotes.isEmpty)

                if isLoadingRemotes {
                    ProgressView("Loading remotes…").controlSize(.small)
                }
                if deleteOnRemote {
                    Picker("Remote", selection: $selectedRemote) {
                        ForEach(remotes, id: \.self) { remote in
                            Text(remote).tag(remote)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isPerforming)
                if isPerforming { ProgressView().controlSize(.small) }

                Button("Delete", role: .destructive) {
                    guard !isPerforming else { return }
                    let remote = deleteOnRemote ? selectedRemote : nil
                    isPerforming = true
                    errorMessage = nil
                    Task {
                        defer { isPerforming = false }
                        do { try await onConfirm(remote) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isPerforming || (deleteOnRemote && selectedRemote.isEmpty))
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
        .interactiveDismissDisabled(isPerforming)
        .task {
            let loaded = await loadRemotes()
            guard !Task.isCancelled else { return }
            remotes = loaded
            selectedRemote = loaded.first ?? ""
            isLoadingRemotes = false
        }
    }
}
