//
//  GitUndoExecutor.swift
//  macgit
//

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

enum GitUndoError: LocalizedError, Equatable {
    case emptyPathList
    case expectedHeadMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .emptyPathList:
            return "Cannot undo this Git action because it does not contain any file paths."
        case .expectedHeadMismatch(let expected, let actual):
            return "Cannot undo because HEAD moved. Expected \(expected), but found \(actual)."
        }
    }
}

struct GitUndoExecutor {
    private let runner: any GitCommandRunning
    private let patchRunner: any GitPatchApplying
    private let stashSupport: GitStashUndoSupport
    private let branchSupport: GitBranchUndoSupport
    private let remoteSupport: GitRemoteUndoSupport
    private let snapshotStore: GitFileUndoSnapshotStore

    init(
        runner: (any GitCommandRunning)? = nil,
        patchRunner: (any GitPatchApplying)? = nil,
        stashSupport: GitStashUndoSupport? = nil,
        branchSupport: GitBranchUndoSupport? = nil,
        remoteSupport: GitRemoteUndoSupport? = nil,
        snapshotStore: GitFileUndoSnapshotStore = GitFileUndoSnapshotStore()
    ) {
        let resolvedRunner = runner ?? GitStatusService.shared
        self.runner = resolvedRunner
        self.patchRunner = patchRunner ?? GitStatusService.shared
        self.stashSupport = stashSupport ?? GitStashUndoSupport(runner: resolvedRunner)
        self.branchSupport = branchSupport ?? GitBranchUndoSupport(runner: resolvedRunner)
        self.remoteSupport = remoteSupport ?? GitRemoteUndoSupport(runner: resolvedRunner)
        self.snapshotStore = snapshotStore
    }

    func execute(_ operation: GitUndoOperation, in repositoryURL: URL) async throws {
        switch operation {
        case .requireCleanWorkingTree:
            let status = try await runner.runGit(arguments: ["status", "--porcelain"], in: repositoryURL)
            guard status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GitError.commandFailed("Commit, stash, or discard working tree changes before undoing this Git Flow action.")
            }
        case .requireHead(let expected):
            let actual = try await branchSupport.tip(of: "HEAD", in: repositoryURL)
            guard actual == expected else {
                throw GitUndoError.expectedHeadMismatch(expected: expected, actual: actual)
            }
        case .requireLocalBranchTip(let name, let expectedTip):
            let actualTip = try await branchSupport.tip(of: name, in: repositoryURL)
            guard actualTip == expectedTip else {
                throw GitError.commandFailed("Cannot continue because branch '\(name)' moved.")
            }
        case .requireLocalBranchAbsent(let name):
            if (try? await runner.runGit(
                arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(name)"],
                in: repositoryURL
            )) != nil {
                throw GitError.commandFailed("Cannot restore branch '\(name)' because it already exists.")
            }
        case .stageFiles(let paths):
            try await runFileCommand(["add", "--"], paths: paths, in: repositoryURL)
        case .unstageFiles(let paths):
            try await runFileCommand(["reset", "HEAD", "--"], paths: paths, in: repositoryURL)
        case .applyPatch(let patch, let cached, let reverse):
            try await patchRunner.applyPatch(patch, in: repositoryURL, cached: cached, reverse: reverse)
        case .checkedWorkingTreePatch(let patch, let reverse):
            try await GitStatusService.shared.applyCheckedWorkingTreePatch(patch, reverse: reverse, in: repositoryURL)
        case .resetHead(let target, let mode, let expectedHead):
            if let expectedHead {
                let actual = try await runner.runGit(arguments: ["rev-parse", "HEAD"], in: repositoryURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard actual == expectedHead else {
                    throw GitUndoError.expectedHeadMismatch(expected: expectedHead, actual: actual)
                }
            }
            _ = try await runner.runGit(arguments: ["reset", mode.flag, target], in: repositoryURL)
        case .commit(let message, let noVerify, let signOff):
            var arguments = ["commit", "-m", message]
            if noVerify { arguments.append("--no-verify") }
            if signOff { arguments.append("--signoff") }
            _ = try await runner.runGit(arguments: arguments, in: repositoryURL)
        case .cherryPick(let commit):
            try await runCherryPick(commits: [commit], in: repositoryURL)
        case .cherryPickCommits(let commits):
            try await runCherryPick(commits: commits, in: repositoryURL)
        case .revert(let commit):
            _ = try await runner.runGit(arguments: ["revert", "--no-edit", commit], in: repositoryURL)
        case .mergeCommit(let commit, let noCommit, let log):
            var arguments = ["merge"]
            if noCommit { arguments.append("--no-commit") }
            if log { arguments.append("--log") }
            arguments.append(commit)
            _ = try await runner.runGit(arguments: arguments, in: repositoryURL)
        case .mergeNoFastForward(let branch, let message):
            _ = try await runner.runGit(
                arguments: ["merge", "--no-ff", branch, "-m", message],
                in: repositoryURL
            )
        case .mergeFastForward(let branch):
            _ = try await runner.runGit(arguments: ["merge", "--ff-only", branch], in: repositoryURL)
        case .rebaseOnto(let commit):
            _ = try await runner.runGit(arguments: ["rebase", commit], in: repositoryURL)
        case .stashPush(let message, let keepIndex, let paths, let includeUntracked):
            var arguments = ["stash", "push"]
            if keepIndex { arguments.append("--keep-index") }
            if includeUntracked { arguments.append("--include-untracked") }
            if !message.isEmpty {
                arguments.append(contentsOf: ["-m", message])
            }
            if !paths.isEmpty {
                arguments.append("--")
                arguments.append(contentsOf: paths)
            }
            _ = try await runner.runGit(arguments: arguments, in: repositoryURL)
        case .stashApply(let ref):
            _ = try await runner.runGit(arguments: ["stash", "apply", ref], in: repositoryURL)
        case .stashApplyAndDrop(let hash):
            _ = try await runner.runGit(arguments: ["stash", "apply", hash], in: repositoryURL)
            try await stashSupport.dropStash(matchingHash: hash, in: repositoryURL)
        case .stashStore(let commit, let message):
            _ = try await runner.runGit(arguments: ["stash", "store", "-m", message, commit], in: repositoryURL)
        case .stashDropMatchingHash(let hash):
            try await stashSupport.dropStash(matchingHash: hash, in: repositoryURL)
        case .checkoutRef(let ref):
            _ = try await runner.runGit(arguments: ["checkout", ref], in: repositoryURL)
        case .createLocalBranch(let name, let startPoint, let checkout):
            if checkout {
                _ = try await runner.runGit(arguments: ["checkout", "-b", name, startPoint], in: repositoryURL)
            } else {
                _ = try await runner.runGit(arguments: ["branch", name, startPoint], in: repositoryURL)
            }
        case .deleteLocalBranch(let name, let force, let expectedTip):
            if let expectedTip {
                let actualTip = try await branchSupport.tip(of: name, in: repositoryURL)
                guard actualTip == expectedTip else {
                    throw GitError.commandFailed("Cannot delete branch '\(name)' because its tip changed.")
                }
            }
            let flag = force ? "-D" : "-d"
            _ = try await runner.runGit(arguments: ["branch", flag, name], in: repositoryURL)
        case .updateLocalBranch(let name, let newTip, let expectedTip):
            _ = try await runner.runGit(
                arguments: ["update-ref", "refs/heads/\(name)", newTip, expectedTip],
                in: repositoryURL
            )
        case .createTag(let name, let commit, let annotated, let message):
            var arguments = ["tag"]
            if annotated {
                arguments.append("-a")
            }
            arguments.append(name)
            if annotated, let message, !message.isEmpty {
                arguments.append(contentsOf: ["-m", message])
            }
            arguments.append(commit)
            _ = try await runner.runGit(arguments: arguments, in: repositoryURL)
        case .deleteTag(let name, let expectedTarget):
            if let expectedTarget {
                let actualTarget = try await branchSupport.tip(of: name, in: repositoryURL)
                guard actualTarget == expectedTarget else {
                    throw GitError.commandFailed("Cannot delete tag '\(name)' because it moved.")
                }
            }
            _ = try await runner.runGit(arguments: ["tag", "-d", name], in: repositoryURL)
        case .renameLocalBranch(let from, let to):
            _ = try await runner.runGit(arguments: ["branch", "-m", from, to], in: repositoryURL)
        case .deleteRemoteBranch(let remote, let branch, let expectedHash):
            let actualHash = try await remoteSupport.remoteHash(remote: remote, branch: branch, in: repositoryURL)
            guard actualHash == expectedHash else {
                throw GitError.commandFailed("Cannot delete remote branch '\(branch)' because it is no longer at the expected hash.")
            }
            _ = try await runner.runGit(arguments: ["push", remote, "--delete", branch], in: repositoryURL)
        case .pushBranch(let remote, let localBranch, let remoteBranch):
            let refSpec = localBranch == remoteBranch ? localBranch : "\(localBranch):\(remoteBranch)"
            _ = try await runner.runGit(arguments: ["push", remote, refSpec], in: repositoryURL)
        case .replaceRemoteBranch(let plan, let restoring):
            try await GitStatusService.shared.replaceRemoteBranch(plan, restoring: restoring, in: repositoryURL)
        case .setUpstream(let branch, let upstream):
            _ = try await runner.runGit(
                arguments: ["branch", "--set-upstream-to", upstream, branch],
                in: repositoryURL
            )
        case .sequence(let operations):
            for operation in operations {
                try await execute(operation, in: repositoryURL)
            }
        case .resetHardToHead(let expectedHead):
            if let expectedHead {
                let actual = try await runner.runGit(arguments: ["rev-parse", "HEAD"], in: repositoryURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard actual == expectedHead else {
                    throw GitUndoError.expectedHeadMismatch(expected: expectedHead, actual: actual)
                }
            }
            _ = try await runner.runGit(arguments: ["reset", "--hard", "HEAD"], in: repositoryURL)
        case .stashPop(let ref):
            _ = try await runner.runGit(arguments: ["stash", "pop", ref], in: repositoryURL)
        case .restoreFileSnapshot(let id):
            try snapshotStore.restore(snapshotID: id, in: repositoryURL)
        case .deleteFileSnapshot(let id):
            try snapshotStore.delete(snapshotID: id, in: repositoryURL)
        case .discardFiles(let paths):
            for path in paths {
                _ = try await runner.runGit(arguments: ["checkout", "--", path], in: repositoryURL)
            }
        case .removeFiles(let paths):
            for path in paths {
                _ = try await runner.runGit(arguments: ["rm", "-f", "--", path], in: repositoryURL)
            }
        case .removeGitFlowWorktree(let path, let branch, let expectedTip):
            try await removeGitFlowWorktree(
                path: path,
                branch: branch,
                expectedTip: expectedTip,
                repositoryURL: repositoryURL
            )
        case .recreateGitFlowWorktree(let path, let branch, let baseTip, let label):
            try await recreateGitFlowWorktree(
                path: path,
                branch: branch,
                baseTip: baseTip,
                label: label,
                repositoryURL: repositoryURL
            )
        }
    }

    private func removeGitFlowWorktree(
        path: URL,
        branch: String,
        expectedTip: String,
        repositoryURL: URL
    ) async throws {
        guard await OpenRepositoryRegistry.shared.isOpen(path) == false else {
            throw GitError.commandFailed("Close the linked worktree window before undoing this Git Flow start.")
        }

        let worktreeOutput = try await runner.runGit(
            arguments: ["worktree", "list", "--porcelain"],
            in: repositoryURL
        )
        guard let entry = worktreeEntry(at: path, in: worktreeOutput) else {
            throw GitError.commandFailed("Cannot undo because the linked worktree is missing or moved.")
        }
        guard entry.branch == branch else {
            throw GitError.commandFailed("Cannot undo because the linked worktree is checked out to another branch.")
        }
        guard entry.isLocked == false else {
            throw GitError.commandFailed("Unlock the linked worktree before undoing this Git Flow start.")
        }

        let status = try await runner.runGit(arguments: ["status", "--porcelain"], in: path)
        guard status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.commandFailed("Commit, stash, or discard changes in the linked worktree before undoing.")
        }
        let actualBranch = try await runner.runGit(
            arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
            in: path
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard actualBranch == branch else {
            throw GitError.commandFailed("Cannot undo because the linked worktree branch changed.")
        }
        let branchTip = try await branchSupport.tip(of: branch, in: repositoryURL)
        let worktreeTip = try await branchSupport.tip(of: "HEAD", in: path)
        guard branchTip == expectedTip, worktreeTip == expectedTip else {
            throw GitError.commandFailed("Cannot undo because the Git Flow branch has new commits.")
        }

        _ = try await runner.runGit(arguments: ["worktree", "remove", path.path], in: repositoryURL)
        _ = try await runner.runGit(arguments: ["branch", "-D", branch], in: repositoryURL)
        // A stale optional display label must not turn a completed Git undo into a failed undo entry.
        try? await removeWorktreeLabel(path: path, repositoryURL: repositoryURL)
    }

    private func recreateGitFlowWorktree(
        path: URL,
        branch: String,
        baseTip: String,
        label: String?,
        repositoryURL: URL
    ) async throws {
        guard FileManager.default.fileExists(atPath: path.path) == false else {
            throw GitError.commandFailed("Cannot redo because the worktree path already exists.")
        }
        if (try? await runner.runGit(
            arguments: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            in: repositoryURL
        )) != nil {
            throw GitError.commandFailed("Cannot redo because branch '\(branch)' already exists.")
        }
        let resolvedBase = try await branchSupport.tip(of: baseTip, in: repositoryURL)
        guard resolvedBase == baseTip else {
            throw GitError.commandFailed("Cannot redo because the recorded base commit is unavailable.")
        }

        _ = try await runner.runGit(
            arguments: ["worktree", "add", "-b", branch, path.path, baseTip],
            in: repositoryURL
        )
        do {
            try await setWorktreeLabel(label, path: path, repositoryURL: repositoryURL)
        } catch {
            _ = try? await runner.runGit(arguments: ["worktree", "remove", path.path], in: repositoryURL)
            _ = try? await runner.runGit(arguments: ["branch", "-D", branch], in: repositoryURL)
            throw error
        }
    }

    private struct UndoWorktreeEntry {
        let path: URL
        let branch: String?
        let isLocked: Bool
    }

    private func worktreeEntry(at expectedPath: URL, in output: String) -> UndoWorktreeEntry? {
        var entries: [UndoWorktreeEntry] = []
        var path: URL?
        var branch: String?
        var isLocked = false

        func flush() {
            guard let path else { return }
            entries.append(UndoWorktreeEntry(path: path, branch: branch, isLocked: isLocked))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.isEmpty {
                flush()
                path = nil
                branch = nil
                isLocked = false
            } else if line.hasPrefix("worktree ") {
                flush()
                path = URL(fileURLWithPath: String(line.dropFirst("worktree ".count))).standardizedFileURL
                branch = nil
                isLocked = false
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "locked" || line.hasPrefix("locked ") {
                isLocked = true
            }
        }
        flush()

        let expectedKey = WorktreeLabelStore.key(for: expectedPath)
        return entries.first { WorktreeLabelStore.key(for: $0.path) == expectedKey }
    }

    private func setWorktreeLabel(_ label: String?, path: URL, repositoryURL: URL) async throws {
        let commonDirectory = try await gitCommonDirectory(repositoryURL: repositoryURL)
        try WorktreeLabelStore().setLabel(label, for: path, in: commonDirectory)
    }

    private func removeWorktreeLabel(path: URL, repositoryURL: URL) async throws {
        let commonDirectory = try await gitCommonDirectory(repositoryURL: repositoryURL)
        try WorktreeLabelStore().removeLabel(for: path, in: commonDirectory)
    }

    private func gitCommonDirectory(repositoryURL: URL) async throws -> URL {
        let output = try await runner.runGit(
            arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            in: repositoryURL
        )
        return URL(
            fileURLWithPath: output.trimmingCharacters(in: .whitespacesAndNewlines),
            isDirectory: true
        ).standardizedFileURL
    }

    private func runFileCommand(_ prefix: [String], paths: [String], in repositoryURL: URL) async throws {
        guard !paths.isEmpty else {
            throw GitUndoError.emptyPathList
        }
        var arguments = prefix
        arguments.append(contentsOf: paths)
        _ = try await runner.runGit(arguments: arguments, in: repositoryURL)
    }

    private func runCherryPick(commits: [String], in repositoryURL: URL) async throws {
        guard !commits.isEmpty else {
            throw GitError.commandFailed("Select at least one commit to cherry-pick.")
        }
        _ = try await runner.runGit(arguments: ["cherry-pick"] + commits, in: repositoryURL)
    }
}
