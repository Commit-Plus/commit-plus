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

struct SidebarBranchPresentationModifier: ViewModifier {
    @Binding var deleteConfirmationTarget: DeleteConfirmationTarget?
    @Binding var forceDeleteBranch: Bool
    @Binding var remoteBranchDeleteTarget: RemoteBranchDeleteTarget?

    let repositoryURL: URL
    let undoManager: GitUndoManager?
    let currentBranch: String
    let branchesUnderPrefix: (String) -> [String]
    let cancelDeleteConfirmation: () -> Void
    let confirmDeleteBranch: (String) -> Void
    let onPrefixDeleteCompleted: () -> Void
    let deleteRemoteBranch: (RemoteBranchDeleteTarget) async -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    func body(content: Content) -> some View {
        content
            .replacingSheet(item: $deleteConfirmationTarget, content: deleteConfirmationSheet)
            .alert("Delete Remote Branch", isPresented: remoteBranchDeletePresented) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive, action: confirmDeleteRemoteBranch)
            } message: {
                Text(remoteBranchDeleteMessage)
            }
    }

    @ViewBuilder
    private func deleteConfirmationSheet(for target: DeleteConfirmationTarget) -> some View {
        switch target {
        case .single(let branch):
            SidebarDeleteBranchSheet(
                branchName: branch,
                forceDelete: $forceDeleteBranch,
                onCancel: cancelDeleteConfirmation,
                onDelete: { confirmDeleteBranch(branch) }
            )
        case .prefix(let prefix):
            SidebarDeletePrefixSheet(
                repositoryURL: repositoryURL,
                branches: Set(branchesUnderPrefix(prefix).filter { $0 != currentBranch }),
                undoManager: undoManager,
                onRunRepositoryOperation: onRunRepositoryOperation,
                onCompleted: onPrefixDeleteCompleted
            )
        }
    }

    private var remoteBranchDeletePresented: Binding<Bool> {
        Binding(
            get: { remoteBranchDeleteTarget != nil },
            set: { isPresented in
                if !isPresented {
                    remoteBranchDeleteTarget = nil
                }
            }
        )
    }

    private var remoteBranchDeleteMessage: String {
        "Delete '\(remoteBranchDeleteTarget?.fullPath ?? "")' from the remote?"
    }

    private func confirmDeleteRemoteBranch() {
        guard let target = remoteBranchDeleteTarget else { return }
        onRunRepositoryOperation("Deleting \(target.fullPath)...") {
            await deleteRemoteBranch(target)
        }
    }
}
