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

struct SidebarSubtreePresentationModifier: ViewModifier {
    @Binding var subtreeToEdit: GitSubtreeEntry?
    @Binding var subtreeToUnlink: GitSubtreeEntry?

    let updateSubtree: @MainActor (GitSubtreeEntry) async throws -> Void
    let unlinkSubtree: @MainActor (GitSubtreeEntry) async -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    func body(content: Content) -> some View {
        content
            .sheet(item: $subtreeToEdit) { entry in
                EditSubtreeSheet(
                    entry: entry,
                    onSave: updateSubtree,
                    onRunRepositoryOperation: onRunRepositoryOperation
                )
            }
            .alert("Unlink Subtree", isPresented: Binding(
                get: { subtreeToUnlink != nil },
                set: { isPresented in
                    if !isPresented {
                        subtreeToUnlink = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) {
                    subtreeToUnlink = nil
                }
                Button("Unlink", role: .destructive) {
                    if let entry = subtreeToUnlink {
                        onRunRepositoryOperation("Unlinking \(entry.path)...") {
                            await unlinkSubtree(entry)
                        }
                    }
                }
            } message: {
                Text("Unlink removes Commit+ metadata only. Files under \(subtreeToUnlink?.path ?? "") remain unchanged.")
            }
    }
}
