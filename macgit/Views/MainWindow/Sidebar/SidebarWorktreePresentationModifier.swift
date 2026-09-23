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

struct SidebarWorktreePresentationModifier: ViewModifier {
    @Binding var worktreeToLabel: WorktreeEntry?
    @Binding var worktreeLabelInput: String
    @Binding var worktreeToLock: WorktreeEntry?
    @Binding var worktreeLockReasonInput: String
    let isUpdatingWorktreeLock: Bool
    @Binding var worktreeToMove: WorktreeEntry?
    @Binding var worktreeMovePathInput: String
    @Binding var worktreeMoveErrorMessage: String?
    let canMoveWorktree: Bool
    let isMovingWorktree: Bool
    @Binding var worktreeToCheckout: WorktreeEntry?
    @Binding var availableWorktreeCheckoutBranches: [String]
    @Binding var selectedWorktreeCheckoutBranch: String
    @Binding var worktreeCheckoutErrorMessage: String?
    let canCheckoutWorktreeBranch: Bool
    let isCheckingOutWorktreeBranch: Bool
    @Binding var showingCreateWorktreeSheet: Bool
    @Binding var createWorktreeMode: WorktreeCreationMode
    let availableWorktreeBranches: [String]
    @Binding var selectedExistingWorktreeBranch: String
    @Binding var newWorktreeBranchName: String
    @Binding var newWorktreeBaseBranch: String
    @Binding var worktreePathInput: String
    @Binding var worktreeLabelDraft: String
    @Binding var openWorktreeAfterCreate: Bool
    let worktreeCreationErrorMessage: String?
    let canCreateWorktree: Bool
    let isCreatingWorktree: Bool
    @Binding var showingWorktreeRemovalConfirmation: Bool
    @Binding var showingMissingWorktreeAlert: Bool
    @Binding var showingWorktreeForceCheckoutConfirmation: Bool
    @Binding var showingPruneWorktreesConfirmation: Bool
    @Binding var pendingWorktreeRemoval: WorktreeEntry?
    @Binding var pendingWorktreeForceCheckout: WorktreeEntry?
    @Binding var missingWorktreeEntry: WorktreeEntry?

    let worktreeRemovalNeedsForce: Bool
    let worktreeRemovalMessage: String
    let saveWorktreeLabel: () async -> Void
    let lockWorktree: (WorktreeEntry) async -> Void
    let moveWorktree: (WorktreeEntry) async -> Void
    let checkoutWorktree: (WorktreeEntry, Bool) async -> Void
    let onCreateWorktreeModeChange: () -> Void
    let onSelectedExistingWorktreeBranchChange: () -> Void
    let onNewWorktreeBranchNameChange: () -> Void
    let onWorktreePathChange: (String) -> Void
    let createWorktree: () async -> Void
    let chooseReplacementWorktreeFolder: (WorktreeEntry) -> Void
    let deleteMissingWorktree: (WorktreeEntry) async -> Void
    let removeWorktree: (WorktreeEntry, Bool) async -> Void
    let pruneWorktrees: () async -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    func body(content: Content) -> some View {
        content
            .alert("Remove Worktree", isPresented: $showingWorktreeRemovalConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button(worktreeRemovalNeedsForce ? "Force Remove" : "Remove", role: .destructive) {
                    if let entry = pendingWorktreeRemoval {
                        onRunRepositoryOperation("Removing \(entry.displayTitle)...") {
                            await removeWorktree(entry, worktreeRemovalNeedsForce)
                        }
                    }
                }
            } message: {
                Text(worktreeRemovalMessage)
            }
            .alert("Worktree Moved or Deleted", isPresented: $showingMissingWorktreeAlert, presenting: missingWorktreeEntry) { entry in
                Button("Delete", role: .destructive) {
                    onRunRepositoryOperation("Removing missing worktree...") {
                        await deleteMissingWorktree(entry)
                    }
                }
                Button("Change folder") {
                    chooseReplacementWorktreeFolder(entry)
                }
                Button("Cancel", role: .cancel) {
                    missingWorktreeEntry = nil
                }
            } message: { entry in
                Text("\"\(entry.displayTitle)\" is no longer available at \(entry.path.path).")
            }
            .alert("Force Switch Branch", isPresented: $showingWorktreeForceCheckoutConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingWorktreeForceCheckout = nil
                }
                Button("Force Switch", role: .destructive) {
                    if let entry = pendingWorktreeForceCheckout {
                        onRunRepositoryOperation("Switching \(entry.displayTitle)...") {
                            await checkoutWorktree(entry, true)
                        }
                    }
                }
            } message: {
                Text("This worktree has uncommitted changes. Force checkout and discard conflicting changes?")
            }
            .alert("Prune Worktrees", isPresented: $showingPruneWorktreesConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Prune", role: .destructive) {
                    onRunRepositoryOperation("Pruning worktrees...") {
                        await pruneWorktrees()
                    }
                }
            } message: {
                Text("Remove stale worktree metadata and orphaned labels for paths that no longer exist?")
            }
            .replacingSheet(item: $worktreeToLabel) { entry in
                WorktreeLabelSheet(
                    entry: entry,
                    label: $worktreeLabelInput,
                    onCancel: {
                        worktreeToLabel = nil
                        worktreeLabelInput = ""
                    },
                    onSave: {
                        onRunRepositoryOperation("Saving worktree label...") {
                            await saveWorktreeLabel()
                        }
                    }
                )
            }
            .replacingSheet(item: $worktreeToLock) { entry in
                WorktreeLockSheet(
                    entry: entry,
                    reason: $worktreeLockReasonInput,
                    isUpdating: isUpdatingWorktreeLock,
                    onCancel: {
                        worktreeToLock = nil
                        worktreeLockReasonInput = ""
                    },
                    onLock: {
                        onRunRepositoryOperation("Locking \(entry.displayTitle)...") {
                            await lockWorktree(entry)
                        }
                    }
                )
            }
            .replacingSheet(item: $worktreeToMove) { entry in
                WorktreeMoveSheet(
                    entry: entry,
                    path: $worktreeMovePathInput,
                    errorMessage: worktreeMoveErrorMessage,
                    canMove: canMoveWorktree,
                    isMoving: isMovingWorktree,
                    onCancel: {
                        worktreeToMove = nil
                        worktreeMovePathInput = ""
                        worktreeMoveErrorMessage = nil
                    },
                    onMove: {
                        onRunRepositoryOperation("Moving \(entry.displayTitle)...") {
                            await moveWorktree(entry)
                        }
                    }
                )
            }
            .replacingSheet(item: $worktreeToCheckout) { entry in
                WorktreeCheckoutSheet(
                    entry: entry,
                    branches: availableWorktreeCheckoutBranches,
                    selection: $selectedWorktreeCheckoutBranch,
                    errorMessage: worktreeCheckoutErrorMessage,
                    canCheckout: canCheckoutWorktreeBranch,
                    isCheckingOut: isCheckingOutWorktreeBranch,
                    onCancel: {
                        worktreeToCheckout = nil
                        worktreeCheckoutErrorMessage = nil
                        selectedWorktreeCheckoutBranch = ""
                        availableWorktreeCheckoutBranches = []
                    },
                    onCheckout: {
                        if entry.dirtyCount > 0 {
                            pendingWorktreeForceCheckout = entry
                            showingWorktreeForceCheckoutConfirmation = true
                        } else {
                            onRunRepositoryOperation("Switching \(entry.displayTitle)...") {
                                await checkoutWorktree(entry, false)
                            }
                        }
                    }
                )
            }
            .replacingSheet(isPresented: $showingCreateWorktreeSheet) {
                CreateWorktreeSheet(
                    mode: $createWorktreeMode,
                    availableBranches: availableWorktreeBranches,
                    selectedExistingBranch: $selectedExistingWorktreeBranch,
                    newBranchName: $newWorktreeBranchName,
                    newBaseBranch: $newWorktreeBaseBranch,
                    path: $worktreePathInput,
                    label: $worktreeLabelDraft,
                    openAfterCreate: $openWorktreeAfterCreate,
                    errorMessage: worktreeCreationErrorMessage,
                    canCreate: canCreateWorktree,
                    isCreating: isCreatingWorktree,
                    onModeChange: onCreateWorktreeModeChange,
                    onSelectedExistingBranchChange: onSelectedExistingWorktreeBranchChange,
                    onNewBranchNameChange: onNewWorktreeBranchNameChange,
                    onPathChange: onWorktreePathChange,
                    onCancel: {
                        showingCreateWorktreeSheet = false
                    },
                    onCreate: {
                        onRunRepositoryOperation("Creating worktree...") {
                            await createWorktree()
                        }
                    }
                )
            }
    }
}
