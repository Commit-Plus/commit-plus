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

extension MainWindowView {
    var gitFlowCommandState: GitFlowCommandState {
        GitFlowCommandState(
            isEnabled: gitFlowConfiguration.isEnabled,
            currentKind: GitFlowPlanner().topicKind(
                for: gitFlowCurrentBranch,
                configuration: gitFlowConfiguration
            ),
            operationInProgress: operationProgress.activeOperation != nil,
            hasPendingFinish: gitFlowFinishCheckpoint != nil,
            hasInvalidRecoveryState: gitFlowRecoveryIssue != nil
        )
    }

    @MainActor
    func authorizeGitFlowAccess(
        forceRefresh: Bool = false,
        presentNotice: Bool = true
    ) async -> Bool {
        let decision = await repositoryVisibilityController.accessDecision(
            for: .gitFlow,
            repositoryURL: repositoryURL,
            accounts: providerAccountController.accounts,
            entitlement: accountController.entitlement,
            policy: featureAccessController.policy,
            forceRefresh: forceRefresh
        )
        guard !Task.isCancelled else { return false }
        if case .denied(let denial) = decision, presentNotice {
            if denial == .requiresPro {
                proUpgradeErrorMessage = nil
                proUpgradePresentation = ProUpgradePresentation(feature: .gitFlow)
            } else {
                featureAccessNotice = FeatureAccessNotice(feature: .gitFlow, denial: denial)
            }
        }
        return decision.isAllowed
    }

    func handleGitFlowMenuAction(_ action: GitFlowMenuAction) {
        guard operationProgress.activeOperation == nil else { return }
        switch action {
        case .start(let kind):
            requestStartGitFlow(kind)
        case .finish(let kind):
            requestFinishGitFlow(kind)
        case .resumeFinish:
            resumeGitFlowFinish()
        case .abortFinish:
            abortGitFlowFinish()
        case .configure:
            requestPresentGitFlowSettings()
        case .disable:
            disableGitFlow()
        }
    }

    func requestPresentGitFlowSettings() {
        initiallySelectGitFlowSettings = true
        presentRepositorySettingsWindow()
    }

    func requestStartGitFlow(_ kind: GitFlowTopicKind) {
        if gitFlowConfiguration.isEnabled {
            pendingGitFlowStart = GitFlowStartPresentation(kind: kind)
        } else {
            requestPresentGitFlowSettings()
        }
    }

    func startGitFlow(_ plan: GitFlowStartPlan, openAfterCreate: Bool) async -> Bool {
        guard await authorizeGitFlowAccess(presentNotice: true) else {
            return false
        }
        do {
            let result = try await GitFlowService().start(plan, in: repositoryURL)
            await MainActor.run {
                switch result.placement {
                case .currentWorkingCopy(let previousRef):
                    undoManager.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Start \(plan.kind.displayName) \(plan.branchName)",
                            undoOperation: .sequence([
                                .checkoutRef(ref: previousRef),
                                .deleteLocalBranch(
                                    name: result.plan.branchName,
                                    force: true,
                                    expectedTip: result.createdTip
                                )
                            ]),
                            redoOperation: .createLocalBranch(
                                name: result.plan.branchName,
                                startPoint: result.createdTip,
                                checkout: true
                            )
                        )
                    )
                    selectedItem = .branch(result.plan.branchName)
                    gitFlowCurrentBranch = result.plan.branchName

                case .newWorktree(let path, let label):
                    undoManager.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Start \(plan.kind.displayName) \(plan.branchName) in worktree",
                            undoOperation: .removeGitFlowWorktree(
                                path: path,
                                branch: plan.branchName,
                                expectedTip: result.createdTip
                            ),
                            redoOperation: .recreateGitFlowWorktree(
                                path: path,
                                branch: plan.branchName,
                                baseTip: result.baseTip,
                                label: label
                            ),
                            confirmationMessage: "Undo will remove the linked worktree folder and its local branch. Continue?"
                        )
                    )
                    if openAfterCreate {
                        openWorktreeInNewWindow(at: path)
                    }
                }
            }
            await GitStatusService.shared.invalidateBranchListCache(in: repositoryURL)
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
            return true
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
            await refreshAfterGitFlowMutation()
            return false
        }
    }

    func canFinishGitFlow(_ kind: GitFlowTopicKind) -> Bool {
        kind.supportsFinish
            && gitFlowFinishCheckpoint == nil
            && GitFlowPlanner().topicKind(
                for: gitFlowCurrentBranch,
                configuration: gitFlowConfiguration
            ) == kind
    }

    func requestFinishGitFlow(_ kind: GitFlowTopicKind) {
        pendingGitFlowFinishPlan = RepositorySheetRequest(input: kind)
    }

    func loadGitFlowFinishPlan(_ kind: GitFlowTopicKind) async throws -> GitFlowFinishPlan {
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        let worktrees = await GitStatusService.shared.worktrees(in: repositoryURL)
        try Task.checkCancellation()
        let localWorktree = worktrees.dropFirst().first {
            $0.path.standardizedFileURL == repositoryURL.standardizedFileURL && $0.branch == currentBranch
        }
        return try GitFlowPlanner().finishPlan(
            kind: kind, currentBranch: currentBranch, configuration: gitFlowConfiguration,
            worktreePath: localWorktree?.path
        )
    }

    func finishGitFlow(_ plan: GitFlowFinishPlan) async -> Bool {
        guard await authorizeGitFlowAccess(presentNotice: true) else {
            return false
        }
        do {
            let result = try await GitFlowService().finish(plan, in: repositoryURL)
            if await cleanUpFinishedGitFlowWorktree(result) { return true }
            await registerCompletedGitFlowFinish(result)
            await refreshAfterGitFlowMutation()
            return true
        } catch {
            let mergeInProgress = await GitStatusService.shared.isMergeInProgress(in: repositoryURL)
            let rebaseInProgress = await GitStatusService.shared.isRebaseInProgress(in: repositoryURL)
            let checkpoint = await GitFlowRecoveryStore().checkpoint(in: repositoryURL)
            await MainActor.run {
                gitFlowFinishCheckpoint = checkpoint
                if mergeInProgress || rebaseInProgress {
                    selectedItem = .item(.fileStatus)
                    gitFlowCurrentBranch = rebaseInProgress ? plan.sourceBranch : plan.targetBranch
                }
                syncState.showError(error.localizedDescription)
            }
            await refreshAfterGitFlowMutation()
            return false
        }
    }

    func resumeGitFlowFinish() {
        runRepositoryOperation("Resuming Git Flow finish…") {
            do {
                let result = try await GitFlowService().resumeFinish(in: repositoryURL)
                if await cleanUpFinishedGitFlowWorktree(result) { return }
                await registerCompletedGitFlowFinish(result)
                await refreshAfterGitFlowMutation()
            } catch {
                let checkpoint = await GitFlowRecoveryStore().checkpoint(in: repositoryURL)
                await MainActor.run {
                    gitFlowFinishCheckpoint = checkpoint
                    selectedItem = .item(.fileStatus)
                    syncState.showError(error.localizedDescription)
                }
                await refreshAfterGitFlowMutation()
            }
        }
    }

    func abortGitFlowFinish() {
        runRepositoryOperation("Aborting Git Flow finish…") {
            do {
                try await GitFlowService().abortFinish(in: repositoryURL)
                await MainActor.run {
                    gitFlowFinishCheckpoint = nil
                    syncState.showInfo("Git Flow finish aborted.")
                }
                await refreshAfterGitFlowMutation()
            } catch {
                await MainActor.run {
                    syncState.showError(error.localizedDescription)
                }
                await refreshAfterGitFlowMutation()
            }
        }
    }

    private func cleanUpFinishedGitFlowWorktree(_ result: GitFlowFinishResult) async -> Bool {
        let plan = result.plan
        guard plan.removeWorktree, let path = plan.worktreePath else { return false }
        let git = GitStatusService.shared
        let entries = await git.worktrees(in: repositoryURL)
        guard let main = entries.first,
              let entry = entries.dropFirst().first(where: { $0.path.standardizedFileURL == path.standardizedFileURL }),
              path.standardizedFileURL == repositoryURL.standardizedFileURL,
              !entry.isLocked, entry.dirtyCount == 0,
              entry.branch == result.targetResults.last?.branch,
              entry.head == result.targetResults.last?.tipAfterMerge else {
            await MainActor.run {
                syncState.showError("Finish succeeded. Local cleanup was skipped because the worktree is dirty, locked, or its state changed. The local branch was kept.")
            }
            return false
        }
        do {
            await MainActor.run {
                if !RepositoryWindowContext.focusRepository(at: main.path.resolvingSymlinksInPath().standardizedFileURL) {
                    openWorktreeInNewWindow(at: main.path)
                }
            }
            try await git.removeWorktree(at: path, force: false, in: main.path)
        } catch {
            await MainActor.run { syncState.showError("Finish succeeded, but local cleanup failed: \(error.localizedDescription). The local branch was kept.") }
            return false
        }
        var didDelete = false
        var warning: String?
        if plan.deleteSourceBranch {
            do {
                let sourceTip = try await GitBranchUndoSupport().tip(of: plan.sourceBranch, in: main.path)
                guard sourceTip == (result.rewrittenSourceTip ?? result.sourceTip) else {
                    throw GitFlowFinishError.sourceRefMoved(plan.sourceBranch)
                }
                guard let target = result.targetResults.last else {
                    throw GitFlowFinishError.targetRefMoved(plan.targetBranch)
                }
                try await git.deleteFinishedGitFlowBranch(
                    name: plan.sourceBranch, expectedTip: sourceTip,
                    targetBranch: target.branch, targetTip: target.tipAfterMerge, in: main.path
                )
                didDelete = true
            } catch {
                warning = "Finish succeeded and the worktree was removed, but the local branch could not be deleted: \(error.localizedDescription)"
            }
        }
        let cleanedResult = GitFlowFinishResult(
            plan: plan, sourceTip: result.sourceTip, targetResults: result.targetResults,
            createdTagName: result.createdTagName, didDeleteSourceBranch: didDelete,
            deletionWarning: warning, rewrittenSourceTip: result.rewrittenSourceTip
        )
        await registerCompletedGitFlowFinish(cleanedResult, undoRepositoryURL: main.path)
        await git.invalidateBranchListCache(in: main.path)
        await RepositoryWindowContext.refreshRepository(at: main.path)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .repositoryDidChange, object: nil,
                userInfo: ["repositoryURL": main.path]
            )
            if let warning { syncState.showError(warning) }
            windowContext.window?.close()
        }
        return true
    }

    @MainActor
    private func registerGitFlowUndo(_ entry: GitUndoEntry) {
        if entry.repositoryURL.standardizedFileURL == repositoryURL.standardizedFileURL {
            undoManager.register(entry)
        } else {
            RepositoryWindowContext.registerTransferredUndo(entry)
        }
    }

    private func registerCompletedGitFlowFinish(_ result: GitFlowFinishResult, undoRepositoryURL: URL? = nil) async {
        let repositoryURL = undoRepositoryURL ?? self.repositoryURL
        if let rewrittenSourceTip = result.rewrittenSourceTip {
            await registerCompletedRebaseFinish(result, rewrittenSourceTip: rewrittenSourceTip, undoRepositoryURL: repositoryURL)
            return
        }
        let plan = result.plan
        let mergeMessage = "Finish \(plan.kind.displayName.lowercased()) '\(plan.sourceBranch)'"
        var undoOperations: [GitUndoOperation] = [.requireCleanWorkingTree]
        if result.didDeleteSourceBranch {
            undoOperations.append(.requireLocalBranchAbsent(plan.sourceBranch))
        } else {
            undoOperations.append(.requireLocalBranchTip(name: plan.sourceBranch, expectedTip: result.sourceTip))
        }
        if let tagName = result.createdTagName, let target = result.targetResults.first {
            undoOperations.append(.deleteTag(name: tagName, expectedTarget: target.tipAfterMerge))
        }
        for target in result.targetResults.reversed() {
            undoOperations.append(.checkoutRef(ref: target.branch))
            undoOperations.append(
                .resetHead(
                    target: target.tipBeforeMerge,
                    mode: .hard,
                    expectedHead: target.tipAfterMerge
                )
            )
        }
        if result.didDeleteSourceBranch {
            undoOperations.append(.createLocalBranch(name: plan.sourceBranch, startPoint: result.sourceTip, checkout: true))
        } else {
            undoOperations.append(.checkoutRef(ref: plan.sourceBranch))
        }

        var redoOperations: [GitUndoOperation] = [
            .requireCleanWorkingTree,
            .requireLocalBranchTip(name: plan.sourceBranch, expectedTip: result.sourceTip)
        ]
        for target in result.targetResults {
            redoOperations.append(.checkoutRef(ref: target.branch))
            redoOperations.append(.requireHead(target.tipBeforeMerge))
            redoOperations.append(.mergeNoFastForward(branch: plan.sourceBranch, message: mergeMessage))
            if target.branch == plan.primaryTargetBranch,
               let tagName = result.createdTagName {
                redoOperations.append(
                    .createTag(
                        name: tagName,
                        commit: target.tipAfterMerge,
                        annotated: true,
                        message: "\(plan.kind == .hotfix ? "Hotfix" : "Release") \(tagName)"
                    )
                )
            }
        }
        if result.didDeleteSourceBranch {
            redoOperations.append(.deleteLocalBranch(name: plan.sourceBranch, force: false, expectedTip: result.sourceTip))
        }

        await MainActor.run {
            registerGitFlowUndo(
                GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: "Finish \(plan.kind.displayName) \(plan.sourceBranch)",
                    undoOperation: .sequence(undoOperations),
                    redoOperation: .sequence(redoOperations),
                    confirmationMessage: "Undo will move Git Flow target branches back to their previous commits. Continue?"
                )
            )
            gitFlowFinishCheckpoint = nil
            let selectedBranch = result.targetResults.last?.branch ?? plan.targetBranch
            gitFlowCurrentBranch = selectedBranch
            selectedItem = .branch(selectedBranch)
            if let warning = result.deletionWarning {
                syncState.showError(warning)
            }
        }
    }

    private func registerCompletedRebaseFinish(
        _ result: GitFlowFinishResult,
        rewrittenSourceTip: String,
        undoRepositoryURL: URL? = nil
    ) async {
        let repositoryURL = undoRepositoryURL ?? self.repositoryURL
        guard let target = result.targetResults.first else { return }
        let plan = result.plan
        var undoOperations: [GitUndoOperation] = [.requireCleanWorkingTree]
        if result.didDeleteSourceBranch {
            undoOperations.append(.requireLocalBranchAbsent(plan.sourceBranch))
        } else {
            undoOperations.append(
                .requireLocalBranchTip(name: plan.sourceBranch, expectedTip: rewrittenSourceTip)
            )
        }
        undoOperations.append(.checkoutRef(ref: target.branch))
        undoOperations.append(
            .resetHead(
                target: target.tipBeforeMerge,
                mode: .hard,
                expectedHead: target.tipAfterMerge
            )
        )
        if result.didDeleteSourceBranch {
            undoOperations.append(
                .createLocalBranch(name: plan.sourceBranch, startPoint: result.sourceTip, checkout: true)
            )
        } else {
            undoOperations.append(
                .updateLocalBranch(
                    name: plan.sourceBranch,
                    newTip: result.sourceTip,
                    expectedTip: rewrittenSourceTip
                )
            )
            undoOperations.append(.checkoutRef(ref: plan.sourceBranch))
        }

        var redoOperations: [GitUndoOperation] = [
            .requireCleanWorkingTree,
            .requireLocalBranchTip(name: plan.sourceBranch, expectedTip: result.sourceTip),
            .checkoutRef(ref: target.branch),
            .requireHead(target.tipBeforeMerge),
            .updateLocalBranch(
                name: plan.sourceBranch,
                newTip: rewrittenSourceTip,
                expectedTip: result.sourceTip
            ),
            .mergeFastForward(branch: plan.sourceBranch)
        ]
        if result.didDeleteSourceBranch {
            redoOperations.append(
                .deleteLocalBranch(
                    name: plan.sourceBranch,
                    force: false,
                    expectedTip: rewrittenSourceTip
                )
            )
        }

        await MainActor.run {
            registerGitFlowUndo(
                GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: "Finish \(plan.kind.displayName) \(plan.sourceBranch)",
                    undoOperation: .sequence(undoOperations),
                    redoOperation: .sequence(redoOperations),
                    confirmationMessage: "Undo will restore the source branch before its rebase and move Develop back. Continue?"
                )
            )
            gitFlowFinishCheckpoint = nil
            gitFlowCurrentBranch = target.branch
            selectedItem = .branch(target.branch)
            if let warning = result.deletionWarning {
                syncState.showError(warning)
            }
        }
    }

    private func refreshAfterGitFlowMutation() async {
        let loadResult = await GitFlowRecoveryStore().loadResult(in: repositoryURL)
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        await GitStatusService.shared.invalidateBranchListCache(in: repositoryURL)
        await syncState.refresh(repositoryURL: repositoryURL)
        await MainActor.run {
            gitFlowCurrentBranch = currentBranch
            switch loadResult {
            case .none:
                gitFlowFinishCheckpoint = nil
                gitFlowRecoveryIssue = nil
            case .value(let checkpoint):
                gitFlowFinishCheckpoint = checkpoint
                gitFlowRecoveryIssue = nil
            case .invalid(let issue):
                gitFlowFinishCheckpoint = nil
                gitFlowRecoveryIssue = issue
            }
        }
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }

    func disableGitFlow() {
        var configuration = gitFlowConfiguration
        configuration.isEnabled = false
        gitFlowConfiguration = configuration
        Task {
            do {
                let syncWarning = try await gitFlowConfigurationSyncController.save(
                    configuration,
                    repositoryURL: repositoryURL,
                    uid: accountController.account?.uid
                )
                if let syncWarning {
                    await MainActor.run {
                        syncState.showError(syncWarning)
                    }
                }
            } catch {
                await MainActor.run {
                    syncState.showError(error.localizedDescription)
                }
            }
        }
    }
}
