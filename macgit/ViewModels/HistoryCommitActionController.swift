// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import Observation

@Observable @MainActor
final class HistoryCommitActionController {
    enum Presentation: Identifiable {
        case checkout(Commit, hasUncommittedChanges: Bool)
        case reset(Commit, branchName: String)
        case tag(Commit), branch(Commit), merge(Commit), rebase(Commit)
        case squash([Commit], message: String)

        var id: String {
            switch self {
            case .checkout(let commit, _): "checkout:\(commit.hash)"
            case .reset(let commit, _): "reset:\(commit.hash)"
            case .tag(let commit): "tag:\(commit.hash)"
            case .branch(let commit): "branch:\(commit.hash)"
            case .merge(let commit): "merge:\(commit.hash)"
            case .rebase(let commit): "rebase:\(commit.hash)"
            case .squash(let commits, _): "squash:\(commits.map(\.hash).joined(separator: ","))"
            }
        }
    }

    struct Dependencies {
        let repositoryURL: URL
        let undoManager: GitUndoManager?
        let syncState: SyncState?
        let runOperation: RepositoryOperationRunner
        let requestCheckout: (String, Bool) -> Void
        let requestExplain: (Commit) -> Void
        let requestBrowseRevision: (Commit) -> Void
        let runCustomAction: (UUID, [String]) -> Void
        let headHash: () -> String?
    }

    var presentation: Presentation?
    var revertCandidate: Commit?
    var errorMessage: String?
    @ObservationIgnored var dependencies: Dependencies
    @ObservationIgnored private var requestToken = UUID()

    init(dependencies: Dependencies) { self.dependencies = dependencies }

    func dismiss() {
        requestToken = UUID()
        presentation = nil
        revertCandidate = nil
    }

    private func present(_ value: Presentation) {
        dismiss()
        presentation = value
    }

    func requestTag(_ commit: Commit) { present(.tag(commit)) }
    func requestBranch(_ commit: Commit) { present(.branch(commit)) }
    func requestMerge(_ commit: Commit) { present(.merge(commit)) }
    func requestRebase(_ commit: Commit) { present(.rebase(commit)) }
    func requestRevert(_ commit: Commit) { dismiss(); revertCandidate = commit }
    func requestSquash(_ commits: [Commit]) {
        guard HistoryLoadPolicy.canSquashCommits(commits, selectedHashes: commits.map(\.hash), headHash: dependencies.headHash()) else { return }
        present(.squash(commits, message: commits.map(\.message).joined(separator: "\n")))
    }
    func requestReset(_ commit: Commit) {
        dismiss()
        let token = requestToken
        let dependencies = dependencies
        Task {
            let branch = await GitStatusService.shared.currentBranch(in: dependencies.repositoryURL) ?? ""
            guard requestToken == token, self.dependencies.repositoryURL == dependencies.repositoryURL else { return }
            presentation = .reset(commit, branchName: branch)
        }
    }
    func requestCheckout(_ commit: Commit) {
        dismiss()
        let token = requestToken
        let dependencies = dependencies
        Task {
            let count = await GitStatusService.shared.uncommittedChangeCount(in: dependencies.repositoryURL)
            guard requestToken == token, self.dependencies.repositoryURL == dependencies.repositoryURL else { return }
            presentation = .checkout(commit, hasUncommittedChanges: count > 0)
        }
    }
    func handleDoubleClick(_ commit: Commit) {
        if let branch = HistoryCheckoutPolicy.branchRef(from: commit.refs) {
            dismiss()
            dependencies.requestCheckout(branch, false)
        } else {
            requestCheckout(commit)
        }
    }
    func requestExplain(_ commit: Commit) { dismiss(); dependencies.requestExplain(commit) }
    func requestBrowseRevision(_ commit: Commit) { dismiss(); dependencies.requestBrowseRevision(commit) }
    func runCustomAction(_ id: UUID, hashes: [String]) { dismiss(); dependencies.runCustomAction(id, hashes) }
    func requestCherryPick(_ commits: [Commit]) {
        dismiss()
        cherryPick(HistoryLoadPolicy.cherryPickCommits(from: commits))
    }

    func checkout(_ commit: Commit, discard: Bool) {
        let dependencies = dependencies
        dependencies.runOperation("Checking out commit...") {
            do {
                try await GitStatusService.shared.checkoutCommit(commit.hash, force: discard, in: dependencies.repositoryURL)
                self.dismiss()
                self.notifyRepositoryChanged(dependencies: dependencies)
            } catch { self.errorMessage = error.localizedDescription }
        }
    }
    func cherryPick(_ commits: [Commit]) {
        let dependencies = dependencies
        guard !commits.isEmpty else { return }
        let message = commits.count == 1 ? "Cherry-picking \(commits[0].hash.prefix(7))..." : "Cherry-picking \(commits.count) commits..."
        dependencies.runOperation(message) { await self.executeCherryPick(commits, dependencies: dependencies) }
    }
    func merge(_ commit: Commit, commitImmediately: Bool, includeMessages: Bool) {
        let dependencies = dependencies
        dependencies.runOperation("Merging commit...") { await self.executeMerge(commit, commitImmediately: commitImmediately, includeMessages: includeMessages, dependencies: dependencies) }
    }
    func rebase(_ commit: Commit) {
        let dependencies = dependencies
        dependencies.runOperation("Rebasing onto commit...") { await self.executeRebase(commit, dependencies: dependencies) }
    }
    func reset(_ commit: Commit, mode: ResetMode) {
        let dependencies = dependencies
        dependencies.runOperation("Resetting HEAD...") { await self.executeReset(commit, mode: mode, dependencies: dependencies) }
    }
    func revert(_ commit: Commit) {
        let dependencies = dependencies
        dependencies.runOperation("Reverting commit...") { await self.executeRevert(commit, dependencies: dependencies) }
    }
    func squash(_ commits: [Commit], message: String) {
        let dependencies = dependencies
        dependencies.runOperation("Squashing \(commits.count) commits...") { await self.executeSquash(commits: commits, message: message, dependencies: dependencies) }
    }
    func createTag(_ commit: Commit, name: String) {
        let dependencies = dependencies
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dependencies.runOperation("Creating tag \(name)...") { await self.executeCreateTag(commit, name: name, dependencies: dependencies) }
    }
    func createBranch(_ commit: Commit, name: String, checkout: Bool) {
        let dependencies = dependencies
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dependencies.runOperation("Creating branch \(name)...") { await self.executeCreateBranch(commit, name: name, checkout: checkout, dependencies: dependencies) }
    }
    private func notifyRepositoryChanged(dependencies: Dependencies) {
        NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": dependencies.repositoryURL])
    }
    private func registerHeadUndo(
        label: String,
        oldHead: String?,
        redo: GitUndoOperation,
        dependencies: Dependencies
    ) async {
        guard let oldHead,
              let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: dependencies.repositoryURL),
              oldHead != newHead else { return }

        dependencies.undoManager?.register(
            GitUndoEntry(
                repositoryURL: dependencies.repositoryURL,
                label: label,
                undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                redoOperation: redo
            )
        )
    }

    private func executeCherryPick(_ commits: [Commit], dependencies: Dependencies) async {
        guard !commits.isEmpty else { return }
        let hashes = commits.map(\.hash)

        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: dependencies.repositoryURL)
            try await GitStatusService.shared.cherryPickCommits(hashes, in: dependencies.repositoryURL)
            await registerHeadUndo(
                label: commits.count == 1
                    ? "Cherry-pick \(commits[0].hash.prefix(7))"
                    : "Cherry-pick \(commits.count) commits",
                oldHead: oldHead,
                redo: commits.count == 1
                    ? .cherryPick(commit: commits[0].hash)
                    : .cherryPickCommits(commits: hashes),
                dependencies: dependencies
            )
            dismiss()
            notifyRepositoryChanged(dependencies: dependencies)
        } catch {
            await dependencies.syncState?.refresh(repositoryURL: dependencies.repositoryURL)
            let hasConflicts = await GitStatusService.shared.hasConflicts(in: dependencies.repositoryURL)
            let inProgress = await GitStatusService.shared.inProgressOperation(in: dependencies.repositoryURL)
            if hasConflicts {
                errorMessage = "Cherry-pick produced conflicts. Resolve them in the File status view, then continue or abort."
            } else if inProgress != nil {
                errorMessage = "Cherry-pick produced an empty commit. Open the File status view to skip or abort."
            } else {
                errorMessage = error.localizedDescription
            }
            notifyRepositoryChanged(dependencies: dependencies)
        }
    }

    private func executeMerge(_ commit: Commit, commitImmediately: Bool, includeMessages: Bool, dependencies: Dependencies) async {
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: dependencies.repositoryURL)
            try await GitStatusService.shared.mergeCommit(
                commit.hash,
                noCommit: !commitImmediately,
                log: includeMessages,
                in: dependencies.repositoryURL
            )
            await registerHeadUndo(
                label: "Merge \(commit.hash.prefix(7))",
                oldHead: oldHead,
                redo: .mergeCommit(
                    commit: commit.hash,
                    noCommit: !commitImmediately,
                    log: includeMessages
                ),
                dependencies: dependencies
            )
            dismiss()
            notifyRepositoryChanged(dependencies: dependencies)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func executeRebase(_ commit: Commit, dependencies: Dependencies) async {
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: dependencies.repositoryURL)
            try await GitStatusService.shared.rebaseCommit(commit.hash, in: dependencies.repositoryURL)
            await registerHeadUndo(
                label: "Rebase onto \(commit.hash.prefix(7))",
                oldHead: oldHead,
                redo: .rebaseOnto(commit: commit.hash),
                dependencies: dependencies
            )
            dismiss()
            notifyRepositoryChanged(dependencies: dependencies)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undoMode(for mode: ResetMode) -> GitUndoResetMode {
        switch mode {
        case .soft: .soft
        case .mixed: .mixed
        case .hard: .hard
        }
    }

    private func executeReset(_ commit: Commit, mode resetMode: ResetMode, dependencies: Dependencies) async {
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: dependencies.repositoryURL)
            try await GitStatusService.shared.resetToCommit(commit.hash, mode: resetMode, in: dependencies.repositoryURL)
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: dependencies.repositoryURL),
               oldHead != newHead {
                dependencies.undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: dependencies.repositoryURL,
                        label: "Reset HEAD",
                        undoOperation: .resetHead(
                            target: oldHead,
                            mode: resetMode == .hard ? .hard : .soft,
                            expectedHead: newHead
                        ),
                        redoOperation: .resetHead(
                            target: commit.hash,
                            mode: undoMode(for: resetMode),
                            expectedHead: oldHead
                        )
                    )
                )
            }
            dismiss()
            notifyRepositoryChanged(dependencies: dependencies)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func executeRevert(_ commit: Commit, dependencies: Dependencies) async {
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: dependencies.repositoryURL)
            try await GitStatusService.shared.revertCommit(commit.hash, in: dependencies.repositoryURL)
            await registerHeadUndo(
                label: "Revert \(commit.hash.prefix(7))",
                oldHead: oldHead,
                redo: .revert(commit: commit.hash),
                dependencies: dependencies
            )
            dismiss()
            notifyRepositoryChanged(dependencies: dependencies)
        } catch {
            await dependencies.syncState?.refresh(repositoryURL: dependencies.repositoryURL)
            let hasConflicts = await GitStatusService.shared.hasConflicts(in: dependencies.repositoryURL)
            let inProgress = await GitStatusService.shared.inProgressOperation(in: dependencies.repositoryURL)
            if hasConflicts {
                errorMessage = "Revert produced conflicts. Resolve them in the File status view, then continue or abort."
            } else if inProgress != nil {
                errorMessage = "Revert produced an empty commit. Open the File status view to skip or abort."
            } else {
                errorMessage = error.localizedDescription
            }
            notifyRepositoryChanged(dependencies: dependencies)
        }
    }

    private func executeSquash(commits: [Commit], message: String, dependencies: Dependencies) async {
        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: dependencies.repositoryURL)
        guard HistoryLoadPolicy.canSquashCommits(commits, selectedHashes: commits.map(\.hash), headHash: oldHead) else {
            return
        }

        do {
            try await GitStatusService.shared.squashCommits(
                commits.map(\.hash),
                message: message,
                in: dependencies.repositoryURL
            )
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: dependencies.repositoryURL),
               oldHead != newHead {
                dependencies.undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: dependencies.repositoryURL,
                        label: "Squash \(commits.count) commits",
                        undoOperation: .resetHead(target: oldHead, mode: .soft, expectedHead: newHead),
                        redoOperation: .commit(message: message, noVerify: false, signOff: false)
                    )
                )
            }
            dismiss()
            notifyRepositoryChanged(dependencies: dependencies)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func executeCreateTag(_ commit: Commit, name tagNameInput: String, dependencies: Dependencies) async {
        let name = tagNameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await GitStatusService.shared.createTag(
                name: name,
                commit: commit.hash,
                annotated: false,
                message: nil,
                in: dependencies.repositoryURL
            )
            dismiss()
            notifyRepositoryChanged(dependencies: dependencies)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func executeCreateBranch(_ commit: Commit, name branchNameInput: String, checkout checkoutNewBranch: Bool, dependencies: Dependencies) async {
        let name = branchNameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let support = GitBranchUndoSupport()
            let startPoint = try await support.tip(of: commit.hash, in: dependencies.repositoryURL)
            _ = try await GitStatusService.shared.createBranch(
                name: name,
                checkout: checkoutNewBranch,
                commit: commit.hash,
                in: dependencies.repositoryURL
            )
            dependencies.undoManager?.register(
                GitUndoEntry(
                    repositoryURL: dependencies.repositoryURL,
                    label: "Create branch \(name)",
                    undoOperation: .deleteLocalBranch(name: name, force: true, expectedTip: startPoint),
                    redoOperation: .createLocalBranch(name: name, startPoint: startPoint, checkout: checkoutNewBranch)
                )
            )

            dismiss()
            notifyRepositoryChanged(dependencies: dependencies)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
