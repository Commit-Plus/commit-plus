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
        case .tag:
            if !syncing { showingNewTagSheet = true }
        case .createPullRequest:
            prepareCreatePullRequest()
        case .refresh:
            Task {
                await syncState.refresh(repositoryURL: repositoryURL, force: true)
                NotificationCenter.default.post(
                    name: .repositoryLocalStateDidRefresh,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
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
            runUndoEntry(entry, menuAction: .undo)
        case .redo:
            guard let entry = undoManager.popForRedo() else {
                syncState.showInfo("Nothing to redo.")
                return
            }
            if entry.confirmationMessage?.isEmpty == false {
                pendingConfirmedUndo = (entry, action)
                return
            }
            runUndoEntry(entry, menuAction: .redo)
        }
    }

    /// Remote-only entries run in the background lane. Other entries can touch remote refs too,
    /// so they wait behind the overlay for queued background work.
    func runUndoEntry(_ entry: GitUndoEntry, menuAction: GitUndoMenuAction) {
        let operation = menuAction == .redo ? entry.redoOperation : entry.undoOperation
        guard operationProgress.hasPendingBackgroundWork,
              !GitUndoExecutor.canRunInBackground(operation) else {
            Task {
                await executeUndoEntry(entry, menuAction: menuAction)
            }
            return
        }
        runRepositoryOperation(menuAction == .redo ? "Redoing Git action..." : "Undoing Git action...") {
            await executeUndoEntry(entry, menuAction: menuAction)
        }
    }

    func executeUndoEntry(_ entry: GitUndoEntry, menuAction: GitUndoMenuAction) async {
        let operation = menuAction == .redo ? entry.redoOperation : entry.undoOperation
        let restoreEntry = {
            switch menuAction {
            case .undo: undoManager.restoreUndo(entry)
            case .redo: undoManager.restoreRedo(entry)
            }
        }

        let remotes = GitUndoExecutor.remoteNames(in: operation)
        var resolver: GitProviderCredentialResolver?
        if !remotes.isEmpty {
            guard let remoteResolver = await credentialResolverForRemoteOperation(remotes: remotes) else {
                restoreEntry()
                return
            }
            resolver = remoteResolver
        }

        if GitUndoExecutor.canRunInBackground(operation) {
            let verb = menuAction == .redo ? "Redoing" : "Undoing"
            operationProgress.runInBackground(title: "\(verb) \(entry.label)") {
                do {
                    try await performUndoOperation(operation, of: entry, credentialResolver: resolver)
                    await MainActor.run {
                        switch menuAction {
                        case .undo: undoManager.completeUndo(entry)
                        case .redo: undoManager.completeRedo(entry)
                        }
                    }
                    return .succeeded
                } catch {
                    await MainActor.run { restoreEntry() }
                    return .failed(error.localizedDescription)
                }
            }
            return
        }

        guard await waitForBackgroundRemoteActivity() else {
            restoreEntry()
            return
        }
        do {
            try await performUndoOperation(operation, of: entry, credentialResolver: resolver)
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
                restoreEntry()
                syncState.showError(error.localizedDescription)
            }
        }
    }

    private func performUndoOperation(
        _ operation: GitUndoOperation,
        of entry: GitUndoEntry,
        credentialResolver: GitProviderCredentialResolver?
    ) async throws {
        try await undoExecutor.execute(operation, in: entry.repositoryURL, credentialResolver: credentialResolver)
        // Undo/redo executes Git commands directly, bypassing the branch
        // service methods that normally invalidate sidebar list caches.
        await GitStatusService.shared.invalidateBranchListCache(in: entry.repositoryURL)
        await syncState.refresh(repositoryURL: repositoryURL)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        }
    }
}
