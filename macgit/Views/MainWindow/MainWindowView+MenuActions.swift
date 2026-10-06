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
    var toolbarActionBinding: Binding<ToolbarAction> {
        Binding(
            get: { .commit },
            set: { newValue in
                handleToolbarAction(newValue)
            }
        )
    }

    func handleToolbarAction(_ action: ToolbarAction) {
        guard operationProgress.activeOperation == nil else { return }
        let syncing = syncState.isAnySyncing
        switch action {
        case .commit:
            if !syncing {
                showCommitSheetIfNoConflicts()
            }
        case .pull:
            if !syncing { showingPullSheet = true }
        case .push:
            if !syncing { showingPushSheet = true }
        case .fetch:
            if !syncing { showingFetchSheet = true }
        case .addSubmodule:
            showingAddSubmoduleSheet = true
        case .addLinkSubtree:
            showingAddLinkSubtreeSheet = true
        case .branch:
            presentBranchSheet(startPoint: nil)
        case .merge:
            if !syncing { showingMergeSheet = true }
        case .stash:
            if !syncing && syncState.stashableCount > 0 {
                showingStashSheet = true
            }
        case .remote:
            openRemoteURL()
        case .finder:
            showInFinder()
        case .editor:
            openRepositoryInExternalEditor()
        case .terminal:
            openTerminal()
        case .repositorySettings:
            presentRepositorySettingsWindow()
        case .search:
            showingSearchModal = true
        }
    }

    func handleGitUndoMenuAction(_ action: GitUndoMenuAction) {
        guard operationProgress.activeOperation == nil else { return }
        guard !syncState.isAnySyncing else {
            syncState.showInfo("Wait for the current Git operation to finish before undoing.")
            return
        }
        guard pendingConfirmedUndo == nil else { return }

        beginGitUndoMenuAction(action)
    }

    private func beginGitUndoMenuAction(_ action: GitUndoMenuAction) {
        switch action {
        case .undo:
            guard let entry = undoManager.popForUndo() else {
                syncState.showInfo("Nothing to undo.")
                return
            }
            if entry.confirmationMessage?.isEmpty == false {
                pendingConfirmedUndo = (entry, action)
                return
            }
            Task {
                await executeUndoEntry(entry, menuAction: .undo)
            }
        case .redo:
            guard let entry = undoManager.popForRedo() else {
                syncState.showInfo("Nothing to redo.")
                return
            }
            if entry.confirmationMessage?.isEmpty == false {
                pendingConfirmedUndo = (entry, action)
                return
            }
            Task {
                await executeUndoEntry(entry, menuAction: .redo)
            }
        }
    }

    func executeUndoEntry(_ entry: GitUndoEntry, menuAction: GitUndoMenuAction) async {
        let operation: GitUndoOperation
        switch menuAction {
        case .undo:
            operation = entry.undoOperation
        case .redo:
            operation = entry.redoOperation
        }

        do {
            if case .replaceRemoteBranch(let plan, let restoring) = operation {
                guard let resolver = await credentialResolverForRemoteOperation(remotes: [plan.remote]) else {
                    switch menuAction {
                    case .undo: undoManager.restoreUndo(entry)
                    case .redo: undoManager.restoreRedo(entry)
                    }
                    return
                }
                guard !syncState.isAnySyncing else {
                    throw GitError.commandFailed("Wait for the current Git operation to finish before undoing.")
                }
                syncState.isPushing = true
                defer { syncState.isPushing = false }
                try await GitStatusService.shared.replaceRemoteBranch(
                    plan, restoring: restoring, in: entry.repositoryURL, credentialResolver: resolver
                )
            } else {
                try await undoExecutor.execute(operation, in: entry.repositoryURL)
            }
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
            await MainActor.run {
                switch menuAction {
                case .undo:
                    undoManager.completeUndo(entry)
                    syncState.showInfo("Undid \(entry.label).")
                case .redo:
                    undoManager.completeRedo(entry)
                    syncState.showInfo("Redid \(entry.label).")
                }
            }
        } catch {
            await MainActor.run {
                switch menuAction {
                case .undo:
                    undoManager.restoreUndo(entry)
                case .redo:
                    undoManager.restoreRedo(entry)
                }
                syncState.showError(error.localizedDescription)
            }
        }
    }
}
