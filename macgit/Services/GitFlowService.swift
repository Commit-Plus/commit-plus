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

import Foundation

enum GitFlowStartError: LocalizedError, Equatable {
    case dirtyWorkingTree
    case unfinishedOperation
    case missingBaseBranch(String)
    case branchAlreadyExists(String)
    case invalidBranchName(String)
    case missingWorktreePath
    case invalidWorktreePath
    case worktreePathAlreadyExists(String)
    case worktreePathAlreadyRegistered(String)
    case partialWorktreeCreation(String)
    case pendingFinishRecovery
    case invalidRecoveryState(String)

    var errorDescription: String? {
        switch self {
        case .dirtyWorkingTree:
            return "Commit, stash, or discard the current changes before starting Git Flow."
        case .unfinishedOperation:
            return "Finish or abort the current Git operation before starting Git Flow."
        case .missingBaseBranch(let branch):
            return "The starting branch '\(branch)' does not exist."
        case .branchAlreadyExists(let branch):
            return "The branch '\(branch)' already exists."
        case .invalidBranchName(let branch):
            return "'\(branch)' is not a valid Git branch name."
        case .missingWorktreePath:
            return "Choose an absolute path for the new worktree."
        case .invalidWorktreePath:
            return "The worktree path must be absolute and normalized."
        case .worktreePathAlreadyExists(let path):
            return "A file or folder already exists at '\(path)'."
        case .worktreePathAlreadyRegistered(let path):
            return "'\(path)' is already registered as a worktree."
        case .partialWorktreeCreation(let message):
            return message
        case .pendingFinishRecovery:
            return "Resume or abort the pending Git Flow finish before starting another flow."
        case .invalidRecoveryState(let message):
            return message
        }
    }
}

enum GitFlowFinishError: LocalizedError, Equatable {
    case dirtyWorkingTree
    case unfinishedOperation
    case currentBranchChanged(expected: String)
    case missingTargetBranch(String)
    case targetCheckedOutInWorktree(String)
    case tagAlreadyExists(String)
    case invalidTagName(String)
    case missingCheckpoint
    case pendingFinishRecovery
    case invalidRecoveryState(String)
    case sourceRefMoved(String)
    case targetRefMoved(String)

    var errorDescription: String? {
        switch self {
        case .dirtyWorkingTree:
            return "Commit, stash, or discard the current changes before finishing Git Flow."
        case .unfinishedOperation:
            return "Finish or abort the current Git operation before finishing Git Flow."
        case .currentBranchChanged(let expected):
            return "Check out '\(expected)' again before finishing it."
        case .missingTargetBranch(let branch):
            return "The target branch '\(branch)' does not exist."
        case .targetCheckedOutInWorktree(let branch):
            return "The target branch '\(branch)' is checked out in another worktree."
        case .tagAlreadyExists(let tag):
            return "The tag '\(tag)' already exists."
        case .invalidTagName(let tag):
            return "'\(tag)' is not a valid Git tag name."
        case .missingCheckpoint:
            return "There is no Git Flow finish operation to resume."
        case .pendingFinishRecovery:
            return "Resume or abort the pending Git Flow finish before starting another finish."
        case .invalidRecoveryState(let message):
            return message
        case .sourceRefMoved(let branch):
            return "The source branch '\(branch)' moved after this finish started. Commit+ left the recovery checkpoint unchanged."
        case .targetRefMoved(let branch):
            return "The target branch '\(branch)' moved after this finish started. Commit+ did not reset it."
        }
    }
}

enum GitFlowDevelopBranchCreationError: LocalizedError, Equatable {
    case emptyBranchName
    case missingMainBranch(String)
    case branchAlreadyExists(String)
    case invalidBranchName(String)

    var errorDescription: String? {
        switch self {
        case .emptyBranchName:
            return "Enter a name for the Develop branch."
        case .missingMainBranch(let branch):
            return "The selected Main branch '\(branch)' does not exist."
        case .branchAlreadyExists(let branch):
            return "The branch '\(branch)' already exists. Select it from the Develop branch menu."
        case .invalidBranchName(let branch):
            return "'\(branch)' is not a valid Git branch name."
        }
    }
}

struct GitFlowService {
    private let recoveryStore = GitFlowRecoveryStore()

    func createDevelopBranch(
        name: String,
        startingPoint: String,
        in repositoryURL: URL
    ) async throws -> String {
        try await createDevelopBranch(
            GitFlowDevelopBranchRequest(name: name, startingPoint: startingPoint),
            in: repositoryURL
        )
    }

    func createDevelopBranch(
        _ request: GitFlowDevelopBranchRequest,
        in repositoryURL: URL
    ) async throws -> String {
        let branchName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branchName.isEmpty else {
            throw GitFlowDevelopBranchCreationError.emptyBranchName
        }

        let git = GitStatusService.shared
        let branches = await git.localBranches(in: repositoryURL)
        guard branches.contains(request.startingPoint) else {
            throw GitFlowDevelopBranchCreationError.missingMainBranch(request.startingPoint)
        }
        guard !branches.contains(branchName) else {
            throw GitFlowDevelopBranchCreationError.branchAlreadyExists(branchName)
        }
        guard await git.isValidBranchName(branchName, in: repositoryURL) else {
            throw GitFlowDevelopBranchCreationError.invalidBranchName(branchName)
        }

        _ = try await git.createBranch(
            name: branchName,
            checkout: false,
            commit: request.startingPoint,
            in: repositoryURL
        )
        return branchName
    }

    func start(_ plan: GitFlowStartPlan, in repositoryURL: URL) async throws -> GitFlowStartResult {
        let git = GitStatusService.shared
        switch await recoveryStore.loadResult(in: repositoryURL) {
        case .none:
            break
        case .value:
            throw GitFlowStartError.pendingFinishRecovery
        case .invalid(let issue):
            throw GitFlowStartError.invalidRecoveryState(issue.message)
        }
        guard await git.hasUnfinishedGitFlowStartOperation(in: repositoryURL) == false else {
            throw GitFlowStartError.unfinishedOperation
        }

        guard await localBranchExists(plan.baseBranch, in: repositoryURL) else {
            throw GitFlowStartError.missingBaseBranch(plan.baseBranch)
        }
        guard await localBranchExists(plan.branchName, in: repositoryURL) == false else {
            throw GitFlowStartError.branchAlreadyExists(plan.branchName)
        }
        guard await git.isValidBranchName(plan.branchName, in: repositoryURL) else {
            throw GitFlowStartError.invalidBranchName(plan.branchName)
        }

        let support = GitBranchUndoSupport()
        let baseTip = try await support.tip(of: plan.baseBranch, in: repositoryURL)

        switch plan.destination {
        case .currentWorkingCopy:
            guard await git.dirtyCount(in: repositoryURL) == 0 else {
                throw GitFlowStartError.dirtyWorkingTree
            }
            let previousRef = try await support.currentRef(in: repositoryURL)
            _ = try await git.createBranch(
                name: plan.branchName,
                checkout: true,
                commit: plan.baseBranch,
                in: repositoryURL
            )
            return GitFlowStartResult(
                plan: plan,
                placement: .currentWorkingCopy(previousRef: previousRef),
                baseTip: baseTip,
                createdTip: baseTip
            )

        case .newWorktree:
            return try await startInNewWorktree(
                plan,
                baseTip: baseTip,
                repositoryURL: repositoryURL
            )
        }
    }

    private func startInNewWorktree(
        _ plan: GitFlowStartPlan,
        baseTip: String,
        repositoryURL: URL
    ) async throws -> GitFlowStartResult {
        guard let path = plan.worktreePath else {
            throw GitFlowStartError.missingWorktreePath
        }
        let normalizedPath = path.standardizedFileURL
        guard path.isFileURL,
              (path.path as NSString).isAbsolutePath,
              WorktreeLabelStore.key(for: path) == WorktreeLabelStore.key(for: normalizedPath) else {
            throw GitFlowStartError.invalidWorktreePath
        }

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: normalizedPath.path) else {
            throw GitFlowStartError.worktreePathAlreadyExists(normalizedPath.path)
        }

        let git = GitStatusService.shared
        let worktrees = await git.worktrees(in: repositoryURL)
        let normalizedKey = WorktreeLabelStore.key(for: normalizedPath)
        guard !worktrees.contains(where: { WorktreeLabelStore.key(for: $0.path) == normalizedKey }) else {
            throw GitFlowStartError.worktreePathAlreadyRegistered(normalizedPath.path)
        }

        do {
            // Recheck the ref immediately before `git worktree add -b`.
            guard await localBranchExists(plan.baseBranch, in: repositoryURL),
                  try await GitBranchUndoSupport().tip(of: plan.baseBranch, in: repositoryURL) == baseTip else {
                throw GitFlowStartError.missingBaseBranch(plan.baseBranch)
            }
            guard await localBranchExists(plan.branchName, in: repositoryURL) == false else {
                throw GitFlowStartError.branchAlreadyExists(plan.branchName)
            }
            guard await git.isValidBranchName(plan.branchName, in: repositoryURL) else {
                throw GitFlowStartError.invalidBranchName(plan.branchName)
            }
            try await git.addWorktree(
                at: normalizedPath,
                target: .newBranch(name: plan.branchName, base: baseTip),
                label: plan.worktreeLabel,
                in: repositoryURL,
                notifyChange: false
            )
        } catch {
            do {
                try await cleanUpFailedWorktreeStart(
                    plan: plan,
                    path: normalizedPath,
                    baseTip: baseTip,
                    repositoryURL: repositoryURL
                )
            } catch let cleanupError {
                throw GitFlowStartError.partialWorktreeCreation(
                    "Worktree creation failed and Commit+ could not safely clean up: \(cleanupError.localizedDescription)"
                )
            }
            throw error
        }

        return GitFlowStartResult(
            plan: plan,
            placement: .newWorktree(path: normalizedPath, label: plan.worktreeLabel),
            baseTip: baseTip,
            createdTip: baseTip
        )
    }

    private func cleanUpFailedWorktreeStart(
        plan: GitFlowStartPlan,
        path: URL,
        baseTip: String,
        repositoryURL: URL
    ) async throws {
        let git = GitStatusService.shared
        let worktrees = await git.worktrees(in: repositoryURL)
        let pathKey = WorktreeLabelStore.key(for: path)
        let matchingPath = worktrees.first { WorktreeLabelStore.key(for: $0.path) == pathKey }
        let branchWorktree = worktrees.first { $0.branch == plan.branchName }

        if let matchingPath {
            guard matchingPath.branch == plan.branchName,
                  matchingPath.isLocked == false,
                  matchingPath.dirtyCount == 0,
                  try await GitBranchUndoSupport().tip(of: "HEAD", in: path) == baseTip else {
                throw GitError.commandFailed("The partially created worktree no longer matches the requested branch and tip.")
            }
            try await git.removeWorktree(
                at: path,
                force: false,
                in: repositoryURL,
                notifyChange: false
            )
        } else if branchWorktree != nil {
            throw GitError.commandFailed("The new branch is attached to an unexpected worktree path.")
        }

        if let actualTip = try? await GitBranchUndoSupport().tip(of: plan.branchName, in: repositoryURL) {
            guard actualTip == baseTip else {
                throw GitError.commandFailed("The partially created branch moved and was left untouched.")
            }
            _ = try await git.deleteBranch(
                name: plan.branchName,
                force: true,
                in: repositoryURL
            )
        }

        if fileManagerDirectoryIsEmpty(path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    private func fileManagerDirectoryIsEmpty(_ path: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: path.path),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: path.path) else {
            return false
        }
        return contents.isEmpty
    }

    func finish(_ plan: GitFlowFinishPlan, in repositoryURL: URL) async throws -> GitFlowFinishResult {
        let plan = plan.normalizedForExecution()
        let git = GitStatusService.shared
        switch await recoveryStore.loadResult(in: repositoryURL) {
        case .none:
            break
        case .value:
            throw GitFlowFinishError.pendingFinishRecovery
        case .invalid(let issue):
            throw GitFlowFinishError.invalidRecoveryState(issue.message)
        }
        guard await git.hasUnfinishedGitFlowStartOperation(in: repositoryURL) == false else {
            throw GitFlowFinishError.unfinishedOperation
        }
        guard await git.dirtyCount(in: repositoryURL) == 0 else {
            throw GitFlowFinishError.dirtyWorkingTree
        }
        guard await git.currentBranch(in: repositoryURL) == plan.sourceBranch else {
            throw GitFlowFinishError.currentBranchChanged(expected: plan.sourceBranch)
        }
        try await validateTargets(for: plan, in: repositoryURL)
        if plan.createTag, let validationError = await tagValidationError(
            plan.tagName ?? "",
            in: repositoryURL
        ) {
            throw validationError
        }

        let support = GitBranchUndoSupport()
        let sourceTip = try await support.tip(of: plan.sourceBranch, in: repositoryURL)
        if plan.strategy == .rebaseFastForward, !plan.kind.requiresReleaseTag {
            return try await finishByRebase(
                plan,
                sourceTip: sourceTip,
                repositoryURL: repositoryURL
            )
        }
        var checkpoint = GitFlowFinishCheckpoint(
            plan: plan,
            sourceTip: sourceTip,
            targetResults: [],
            createdTagName: nil,
            phase: .primaryMerge
        )
        try await recoveryStore.save(checkpoint, in: repositoryURL)

        checkpoint = try await mergeTarget(at: 0, checkpoint: checkpoint, in: repositoryURL)
        checkpoint = try await createTagIfNeeded(checkpoint, in: repositoryURL)
        if plan.secondaryTargetBranch != nil {
            checkpoint.phase = .secondaryMerge
            try await recoveryStore.save(checkpoint, in: repositoryURL)
            checkpoint = try await mergeTarget(at: 1, checkpoint: checkpoint, in: repositoryURL)
        }

        var didDelete = false
        var deletionWarning: String?
        if plan.deleteSourceBranch && !plan.removeWorktree {
            do {
                _ = try await git.deleteBranch(name: plan.sourceBranch, force: false, in: repositoryURL)
                didDelete = true
            } catch {
                deletionWarning = "The merge completed, but Commit+ could not delete '\(plan.sourceBranch)': \(error.localizedDescription)"
            }
        }
        try await recoveryStore.clear(in: repositoryURL)

        return GitFlowFinishResult(
            plan: plan,
            sourceTip: sourceTip,
            targetResults: checkpoint.targetResults,
            createdTagName: checkpoint.createdTagName,
            didDeleteSourceBranch: didDelete,
            deletionWarning: deletionWarning,
            rewrittenSourceTip: nil
        )
    }

    func resumeFinish(in repositoryURL: URL) async throws -> GitFlowFinishResult {
        var checkpoint: GitFlowFinishCheckpoint
        switch await recoveryStore.loadResult(in: repositoryURL) {
        case .none:
            throw GitFlowFinishError.missingCheckpoint
        case .value(let value):
            checkpoint = value
        case .invalid(let issue):
            throw GitFlowFinishError.invalidRecoveryState(issue.message)
        }
        let git = GitStatusService.shared
        if checkpoint.phase == .topicRebase || checkpoint.phase == .topicFastForward {
            return try await resumeRebaseFinish(checkpoint, in: repositoryURL)
        }
        if await git.isMergeInProgress(in: repositoryURL) {
            _ = try await git.runGit(arguments: ["merge", "--continue"], in: repositoryURL)
        } else if await git.dirtyCount(in: repositoryURL) != 0 {
            throw GitFlowFinishError.dirtyWorkingTree
        }

        switch checkpoint.phase {
        case .primaryMerge:
            checkpoint = try await recordCurrentMergeIfNeeded(at: 0, checkpoint: checkpoint, in: repositoryURL)
            checkpoint = try await createTagIfNeeded(checkpoint, in: repositoryURL)
            if checkpoint.plan.secondaryTargetBranch != nil {
                checkpoint.phase = .secondaryMerge
                try await recoveryStore.save(checkpoint, in: repositoryURL)
                checkpoint = try await mergeTarget(at: 1, checkpoint: checkpoint, in: repositoryURL)
            }
        case .secondaryMerge:
            checkpoint = try await recordCurrentMergeIfNeeded(at: 1, checkpoint: checkpoint, in: repositoryURL)
        case .topicRebase, .topicFastForward:
            preconditionFailure("Rebase checkpoints are handled before merge recovery.")
        }

        var didDelete = false
        var deletionWarning: String?
        if checkpoint.plan.deleteSourceBranch && !checkpoint.plan.removeWorktree {
            do {
                _ = try await git.deleteBranch(name: checkpoint.plan.sourceBranch, force: false, in: repositoryURL)
                didDelete = true
            } catch {
                deletionWarning = "The merge completed, but Commit+ could not delete '\(checkpoint.plan.sourceBranch)': \(error.localizedDescription)"
            }
        }
        try await recoveryStore.clear(in: repositoryURL)

        return GitFlowFinishResult(
            plan: checkpoint.plan,
            sourceTip: checkpoint.sourceTip,
            targetResults: checkpoint.targetResults,
            createdTagName: checkpoint.createdTagName,
            didDeleteSourceBranch: didDelete,
            deletionWarning: deletionWarning,
            rewrittenSourceTip: nil
        )
    }

    func abortFinish(in repositoryURL: URL) async throws {
        let checkpoint: GitFlowFinishCheckpoint
        switch await recoveryStore.loadResult(in: repositoryURL) {
        case .none:
            throw GitFlowFinishError.missingCheckpoint
        case .value(let value):
            checkpoint = value
        case .invalid(let issue):
            throw GitFlowFinishError.invalidRecoveryState(issue.message)
        }
        let git = GitStatusService.shared
        if checkpoint.phase == .topicRebase || checkpoint.phase == .topicFastForward {
            try await abortRebaseFinish(checkpoint, in: repositoryURL)
            return
        }
        if await git.isMergeInProgress(in: repositoryURL) {
            try await git.abortMerge(in: repositoryURL)
        }
        let support = GitBranchUndoSupport()
        let actualSourceTip = try await support.tip(of: checkpoint.plan.sourceBranch, in: repositoryURL)
        guard actualSourceTip == checkpoint.sourceTip else {
            throw GitFlowFinishError.sourceRefMoved(checkpoint.plan.sourceBranch)
        }
        for target in checkpoint.targetResults {
            let actualTip = try await support.tip(of: target.branch, in: repositoryURL)
            guard actualTip == target.tipAfterMerge else {
                throw GitFlowFinishError.targetRefMoved(target.branch)
            }
        }
        if let tagName = checkpoint.createdTagName {
            let actualTagTarget = try await support.tip(of: "\(tagName)^{commit}", in: repositoryURL)
            guard actualTagTarget == checkpoint.targetResults.first?.tipAfterMerge else {
                throw GitFlowFinishError.targetRefMoved("tag \(tagName)")
            }
            try await git.deleteTag(name: tagName, in: repositoryURL)
        }
        for target in checkpoint.targetResults.reversed() {
            _ = try await git.runGit(arguments: ["checkout", target.branch], in: repositoryURL)
            _ = try await git.runGit(arguments: ["reset", "--hard", target.tipBeforeMerge], in: repositoryURL)
        }
        _ = try await git.runGit(arguments: ["checkout", checkpoint.plan.sourceBranch], in: repositoryURL)
        try await recoveryStore.clear(in: repositoryURL)
    }

    private func mergeMessage(for plan: GitFlowFinishPlan) -> String {
        "Finish \(plan.kind.displayName.lowercased()) '\(plan.sourceBranch)'"
    }

    private func validateTargets(for plan: GitFlowFinishPlan, in repositoryURL: URL) async throws {
        let git = GitStatusService.shared
        let branches = await git.localBranches(in: repositoryURL)
        for branch in plan.targetBranches {
            guard branches.contains(branch) else {
                throw GitFlowFinishError.missingTargetBranch(branch)
            }
            if try await git.worktreePath(for: branch, in: repositoryURL) != nil {
                throw GitFlowFinishError.targetCheckedOutInWorktree(branch)
            }
        }
    }

    private func mergeTarget(
        at index: Int,
        checkpoint: GitFlowFinishCheckpoint,
        in repositoryURL: URL
    ) async throws -> GitFlowFinishCheckpoint {
        var checkpoint = checkpoint
        let plan = checkpoint.plan
        let branch = plan.targetBranches[index]
        try await validateTarget(branch, for: plan, in: repositoryURL)
        let support = GitBranchUndoSupport()
        let actualSourceTip = try await support.tip(of: plan.sourceBranch, in: repositoryURL)
        guard actualSourceTip == checkpoint.sourceTip else {
            throw GitFlowFinishError.sourceRefMoved(plan.sourceBranch)
        }
        let oldTip = try await support.tip(of: branch, in: repositoryURL)
        _ = try await GitStatusService.shared.runGit(arguments: ["checkout", branch], in: repositoryURL)
        let checkedOutTip = try await support.tip(of: branch, in: repositoryURL)
        guard checkedOutTip == oldTip else {
            throw GitFlowFinishError.targetRefMoved(branch)
        }
        checkpoint.phase = index == 0 ? .primaryMerge : .secondaryMerge
        try await recoveryStore.save(checkpoint, in: repositoryURL)
        _ = try await GitStatusService.shared.runGit(
            arguments: ["merge", "--no-ff", plan.sourceBranch, "-m", mergeMessage(for: plan)],
            in: repositoryURL
        )
        let newTip = try await support.tip(of: branch, in: repositoryURL)
        checkpoint.targetResults.append(
            GitFlowFinishTargetResult(branch: branch, tipBeforeMerge: oldTip, tipAfterMerge: newTip)
        )
        try await recoveryStore.save(checkpoint, in: repositoryURL)
        return checkpoint
    }

    private func recordCurrentMergeIfNeeded(
        at index: Int,
        checkpoint: GitFlowFinishCheckpoint,
        in repositoryURL: URL
    ) async throws -> GitFlowFinishCheckpoint {
        var checkpoint = checkpoint
        guard checkpoint.targetResults.count == index else { return checkpoint }
        let branch = checkpoint.plan.targetBranches[index]
        let support = GitBranchUndoSupport()
        let newTip = try await support.tip(of: branch, in: repositoryURL)
        let beforeTip = try await support.tip(of: "HEAD^1", in: repositoryURL)
        checkpoint.targetResults.append(
            GitFlowFinishTargetResult(branch: branch, tipBeforeMerge: beforeTip, tipAfterMerge: newTip)
        )
        try await recoveryStore.save(checkpoint, in: repositoryURL)
        return checkpoint
    }

    private func createTagIfNeeded(
        _ checkpoint: GitFlowFinishCheckpoint,
        in repositoryURL: URL
    ) async throws -> GitFlowFinishCheckpoint {
        var checkpoint = checkpoint
        guard checkpoint.createdTagName == nil,
              checkpoint.plan.createTag,
              let tagName = checkpoint.plan.tagName,
              let target = checkpoint.targetResults.first else {
            return checkpoint
        }
        if try await tagExists(tagName, in: repositoryURL) {
            throw GitFlowFinishError.tagAlreadyExists(tagName)
        }
        try await GitStatusService.shared.createTag(
            name: tagName,
            commit: target.tipAfterMerge,
            annotated: true,
            message: tagMessage(for: checkpoint.plan.kind, tagName: tagName),
            in: repositoryURL
        )
        checkpoint.createdTagName = tagName
        try await recoveryStore.save(checkpoint, in: repositoryURL)
        return checkpoint
    }

    private func tagExists(_ tag: String, in repositoryURL: URL) async throws -> Bool {
        do {
            _ = try await GitStatusService.shared.runGit(
                arguments: ["show-ref", "--verify", "--quiet", "refs/tags/\(tag)"],
                in: repositoryURL
            )
            return true
        } catch {
            return false
        }
    }

    private func localBranchExists(_ branch: String, in repositoryURL: URL) async -> Bool {
        do {
            _ = try await GitStatusService.shared.runGit(
                arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
                in: repositoryURL
            )
            return true
        } catch {
            return false
        }
    }

    private func validateTarget(
        _ branch: String,
        for plan: GitFlowFinishPlan,
        in repositoryURL: URL
    ) async throws {
        let git = GitStatusService.shared
        guard await git.localBranches(in: repositoryURL).contains(branch) else {
            throw GitFlowFinishError.missingTargetBranch(branch)
        }
        if try await git.worktreePath(for: branch, in: repositoryURL) != nil,
           await git.currentBranch(in: repositoryURL) != branch {
            throw GitFlowFinishError.targetCheckedOutInWorktree(branch)
        }
        let sourceTip = try await GitBranchUndoSupport().tip(of: plan.sourceBranch, in: repositoryURL)
        guard !sourceTip.isEmpty else { throw GitFlowFinishError.sourceRefMoved(plan.sourceBranch) }
    }

    func tagValidationError(_ tag: String, in repositoryURL: URL) async -> GitFlowFinishError? {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard await GitStatusService.shared.isValidTagName(tag, in: repositoryURL) else {
            return .invalidTagName(tag)
        }
        guard (try? await tagExists(tag, in: repositoryURL)) != true else {
            return .tagAlreadyExists(tag)
        }
        return nil
    }

    private func finishByRebase(
        _ plan: GitFlowFinishPlan,
        sourceTip: String,
        repositoryURL: URL
    ) async throws -> GitFlowFinishResult {
        let support = GitBranchUndoSupport()
        try await validateTarget(plan.primaryTargetBranch, for: plan, in: repositoryURL)
        let targetTip = try await support.tip(of: plan.primaryTargetBranch, in: repositoryURL)
        var checkpoint = GitFlowFinishCheckpoint(
            plan: plan,
            sourceTip: sourceTip,
            targetResults: [],
            createdTagName: nil,
            phase: .topicRebase,
            targetTipBeforeIntegration: targetTip
        )
        try await recoveryStore.save(checkpoint, in: repositoryURL)

        let currentSourceTip = try await support.tip(of: plan.sourceBranch, in: repositoryURL)
        guard currentSourceTip == sourceTip else {
            throw GitFlowFinishError.sourceRefMoved(plan.sourceBranch)
        }
        let currentTargetTip = try await support.tip(of: plan.primaryTargetBranch, in: repositoryURL)
        guard currentTargetTip == targetTip else {
            throw GitFlowFinishError.targetRefMoved(plan.primaryTargetBranch)
        }
        _ = try await GitStatusService.shared.runGit(
            arguments: ["rebase", plan.primaryTargetBranch],
            in: repositoryURL
        )
        checkpoint.rewrittenSourceTip = try await support.tip(of: plan.sourceBranch, in: repositoryURL)
        checkpoint.phase = .topicFastForward
        try await recoveryStore.save(checkpoint, in: repositoryURL)
        return try await completeRebaseFastForward(checkpoint, in: repositoryURL)
    }

    private func resumeRebaseFinish(
        _ savedCheckpoint: GitFlowFinishCheckpoint,
        in repositoryURL: URL
    ) async throws -> GitFlowFinishResult {
        var checkpoint = savedCheckpoint
        let git = GitStatusService.shared
        let support = GitBranchUndoSupport()

        if checkpoint.phase == .topicRebase {
            if await git.isRebaseInProgress(in: repositoryURL) {
                _ = try await git.runGit(arguments: ["rebase", "--continue"], in: repositoryURL)
            } else if await git.dirtyCount(in: repositoryURL) != 0 {
                throw GitFlowFinishError.dirtyWorkingTree
            }
            checkpoint.rewrittenSourceTip = try await support.tip(
                of: checkpoint.plan.sourceBranch,
                in: repositoryURL
            )
            checkpoint.phase = .topicFastForward
            try await recoveryStore.save(checkpoint, in: repositoryURL)
        }
        return try await completeRebaseFastForward(checkpoint, in: repositoryURL)
    }

    private func completeRebaseFastForward(
        _ savedCheckpoint: GitFlowFinishCheckpoint,
        in repositoryURL: URL
    ) async throws -> GitFlowFinishResult {
        var checkpoint = savedCheckpoint
        let git = GitStatusService.shared
        let support = GitBranchUndoSupport()
        guard let targetTipBefore = checkpoint.targetTipBeforeIntegration,
              let rewrittenSourceTip = checkpoint.rewrittenSourceTip else {
            throw GitFlowFinishError.missingCheckpoint
        }
        try await validateTarget(
            checkpoint.plan.primaryTargetBranch,
            for: checkpoint.plan,
            in: repositoryURL
        )
        let actualSourceTip = try await support.tip(of: checkpoint.plan.sourceBranch, in: repositoryURL)
        guard actualSourceTip == rewrittenSourceTip else {
            throw GitFlowFinishError.currentBranchChanged(expected: checkpoint.plan.sourceBranch)
        }
        let actualTargetTip = try await support.tip(of: checkpoint.plan.primaryTargetBranch, in: repositoryURL)
        guard actualTargetTip == targetTipBefore else {
            throw GitFlowFinishError.currentBranchChanged(expected: checkpoint.plan.primaryTargetBranch)
        }

        _ = try await git.runGit(arguments: ["checkout", checkpoint.plan.primaryTargetBranch], in: repositoryURL)
        _ = try await git.runGit(
            arguments: ["merge", "--ff-only", checkpoint.plan.sourceBranch],
            in: repositoryURL
        )
        let targetTipAfter = try await support.tip(of: checkpoint.plan.primaryTargetBranch, in: repositoryURL)
        checkpoint.targetResults = [
            GitFlowFinishTargetResult(
                branch: checkpoint.plan.primaryTargetBranch,
                tipBeforeMerge: targetTipBefore,
                tipAfterMerge: targetTipAfter
            )
        ]
        try await recoveryStore.save(checkpoint, in: repositoryURL)

        let deletion = await deleteSourceIfRequested(checkpoint.plan, in: repositoryURL)
        try await recoveryStore.clear(in: repositoryURL)
        return GitFlowFinishResult(
            plan: checkpoint.plan,
            sourceTip: checkpoint.sourceTip,
            targetResults: checkpoint.targetResults,
            createdTagName: nil,
            didDeleteSourceBranch: deletion.didDelete,
            deletionWarning: deletion.warning,
            rewrittenSourceTip: rewrittenSourceTip
        )
    }

    private func abortRebaseFinish(
        _ checkpoint: GitFlowFinishCheckpoint,
        in repositoryURL: URL
    ) async throws {
        let git = GitStatusService.shared
        let support = GitBranchUndoSupport()
        if await git.isRebaseInProgress(in: repositoryURL) {
            _ = try await git.runGit(arguments: ["rebase", "--abort"], in: repositoryURL)
        } else {
            if let targetTipBefore = checkpoint.targetTipBeforeIntegration {
                let actualTargetTip = try await support.tip(of: checkpoint.plan.primaryTargetBranch, in: repositoryURL)
                guard actualTargetTip == targetTipBefore else {
                    throw GitError.commandFailed("Cannot abort because the target branch moved.")
                }
            }
            _ = try await git.runGit(arguments: ["checkout", checkpoint.plan.sourceBranch], in: repositoryURL)
            _ = try await git.runGit(arguments: ["reset", "--hard", checkpoint.sourceTip], in: repositoryURL)
        }
        let restoredSourceTip = try await support.tip(of: checkpoint.plan.sourceBranch, in: repositoryURL)
        guard restoredSourceTip == checkpoint.sourceTip else {
            throw GitError.commandFailed("Cannot abort because the source branch could not be restored.")
        }
        try await recoveryStore.clear(in: repositoryURL)
    }

    private func deleteSourceIfRequested(
        _ plan: GitFlowFinishPlan,
        in repositoryURL: URL
    ) async -> (didDelete: Bool, warning: String?) {
        guard plan.deleteSourceBranch && !plan.removeWorktree else { return (false, nil) }
        do {
            _ = try await GitStatusService.shared.deleteBranch(
                name: plan.sourceBranch,
                force: false,
                in: repositoryURL
            )
            return (true, nil)
        } catch {
            return (
                false,
                "The integration completed, but Commit+ could not delete '\(plan.sourceBranch)': \(error.localizedDescription)"
            )
        }
    }

    private func tagMessage(for kind: GitFlowTopicKind, tagName: String) -> String {
        "\(kind == .hotfix ? "Hotfix" : "Release") \(tagName)"
    }
}
