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
            hasStagedChanges: syncState.stagedBadgeCount > 0
        ) { message, commitAllChanges in
            pendingToolbarCommit = (message, commitAllChanges)
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
        PushSheetView(repositoryURL: repositoryURL, defaultRemote: repoSettings.defaultRemoteName, onForcePush: { branch, remote, remoteBranch in
            pendingSheetForcePush = (branch, remote, remoteBranch)
        }) { options in
            runRemoteOperation("Pushing branches...", remotes: [options.remote]) { credentialResolver in
                await syncState.performPush(
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
                runRepositoryOperation("Fetching remotes...") {
                    await syncState.performFetch(
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
    func branchSheet(startPoint: GitBranchStartPoint?) -> some View {
        BranchSheetView(
            repositoryURL: repositoryURL,
            undoManager: undoManager,
            initialStartPoint: startPoint,
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Tag")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tag name:")
                    .font(.system(size: 13))
                TextField("Enter tag name...", text: $tagNameInput)
                    .textFieldStyle(.roundedBorder)
            }

            if let startPoint = tagStartPoint {
                Text("Create tag from commit: \(startPoint.message) - \(startPoint.shortHash)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingTagSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Tag") {
                    Task { await createTagFromBranch() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagNameInput.trimmingCharacters(in: .whitespaces).isEmpty || tagStartPoint == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
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
                        syncState.startBackgroundSync(
                            repositoryURL: repositoryURL,
                            settings: newSettings,
                            globalAutoFetchEnabled: appState.autoFetchEnabled
                        )
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
    func startGitFlowSheet(for kind: GitFlowTopicKind) -> some View {
        StartGitFlowSheet(
            kind: kind,
            configuration: gitFlowConfiguration,
            worktreeRootURL: gitFlowWorktreeRootURL ?? repositoryURL,
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

    func tagMoveConfirmationSheet(for confirmation: PendingTagMoveConfirmation) -> some View {
        MoveTagConfirmationSheet(
            confirmation: confirmation,
            onConfirm: { remote in
                pendingTagMoveConfirmation = nil
                runRepositoryOperation("Moving tag \(confirmation.tagName)...") {
                    await performTagMove(confirmation, forcePushRemote: remote)
                }
            },
            onCancel: {
                pendingTagMoveConfirmation = nil
            }
        )
    }

    func deleteTagConfirmationSheet(for confirmation: PendingTagDeletion) -> some View {
        DeleteTagConfirmationSheet(
            confirmation: confirmation,
            onConfirm: { remote in
                pendingTagDeletion = nil
                let message = remote.map { "Deleting \(confirmation.tag) on \($0)..." }
                    ?? "Deleting \(confirmation.tag)..."
                runRepositoryOperation(message) {
                    await deleteTag(confirmation.tag, remote: remote)
                }
            },
            onCancel: {
                pendingTagDeletion = nil
            }
        )
    }
}

struct MoveTagConfirmationSheet: View {
    let confirmation: PendingTagMoveConfirmation
    let onConfirm: (String?) -> Void
    let onCancel: () -> Void

    @State private var forcePush = false
    @State private var selectedRemote = ""

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

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Move Tag") {
                    onConfirm(forcePush ? selectedRemote : nil)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 13))
                .disabled(forcePush && selectedRemote.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 500, maxWidth: 560)
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
    let onConfirm: (String?) -> Void
    let onCancel: () -> Void

    @State private var deleteOnRemote = false
    @State private var selectedRemote = ""

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
                    .disabled(confirmation.remotes.isEmpty)

                if deleteOnRemote {
                    Picker("Remote", selection: $selectedRemote) {
                        ForEach(confirmation.remotes, id: \.self) { remote in
                            Text(remote).tag(remote)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Delete", role: .destructive) {
                    onConfirm(deleteOnRemote ? selectedRemote : nil)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(deleteOnRemote && selectedRemote.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
        .task {
            selectedRemote = confirmation.remotes.first ?? ""
        }
    }
}
