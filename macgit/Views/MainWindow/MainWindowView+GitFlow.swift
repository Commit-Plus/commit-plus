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
        Task {
            guard await authorizeGitFlowAccess() else { return }
            await MainActor.run {
                initiallySelectGitFlowSettings = true
                presentRepositorySettingsWindow()
            }
        }
    }

    func requestStartGitFlow(_ kind: GitFlowTopicKind) {
        Task {
            guard await authorizeGitFlowAccess() else { return }
            await MainActor.run {
                if gitFlowConfiguration.isEnabled {
                    pendingGitFlowTopicKind = kind
                } else {
                    initiallySelectGitFlowSettings = true
                    presentRepositorySettingsWindow()
                }
            }
        }
    }

    func startGitFlow(_ plan: GitFlowStartPlan, openAfterCreate: Bool) async -> Bool {
        guard await authorizeGitFlowAccess() else { return false }
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
        Task {
            guard await authorizeGitFlowAccess() else { return }
            let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
            do {
                let plan = try GitFlowPlanner().finishPlan(
                    kind: kind,
                    currentBranch: currentBranch,
                    configuration: gitFlowConfiguration
                )
                await MainActor.run {
                    gitFlowCurrentBranch = currentBranch
                    pendingGitFlowFinishPlan = plan
                }
            } catch {
                await MainActor.run { syncState.showError(error.localizedDescription) }
            }
        }
    }

    func finishGitFlow(_ plan: GitFlowFinishPlan) async -> Bool {
        guard await authorizeGitFlowAccess() else { return false }
        do {
            let result = try await GitFlowService().finish(plan, in: repositoryURL)
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

    private func registerCompletedGitFlowFinish(_ result: GitFlowFinishResult) async {
        if let rewrittenSourceTip = result.rewrittenSourceTip {
            await registerCompletedRebaseFinish(result, rewrittenSourceTip: rewrittenSourceTip)
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
            undoManager.register(
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
        rewrittenSourceTip: String
    ) async {
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
            undoManager.register(
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
