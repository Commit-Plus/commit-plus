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

struct SubmoduleLifecyclePresentationModifier: ViewModifier {
    @Binding var submoduleToEdit: GitSubmoduleEntry?
    @Binding var submoduleToDeinitialize: GitSubmoduleEntry?
    @Binding var submoduleToRemove: GitSubmoduleEntry?
    @Binding var forceRemoveSubmodule: Bool

    let onSaveSettings: @MainActor (GitSubmoduleEntry, String, String?) async throws -> Void
    let onDeinitialize: (GitSubmoduleEntry, Bool) -> Void
    let onRemove: (GitSubmoduleEntry, Bool) -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    private var deinitializeMessage: String {
        guard let entry = submoduleToDeinitialize else { return "" }
        let decision = SubmoduleLifecyclePolicy.decision(for: .deinitialize(force: false), entry: entry)
        return decision.message ?? "Deinitialize \(entry.path)?"
    }

    private var deinitializeRequiresForce: Bool {
        guard let entry = submoduleToDeinitialize else { return false }
        let decision = SubmoduleLifecyclePolicy.decision(for: .deinitialize(force: false), entry: entry)
        return !decision.isAllowed && decision.requiresConfirmation
    }

    private var removeMessage: String {
        guard let entry = submoduleToRemove else { return "" }
        if forceRemoveSubmodule {
            return "This submodule has staged changes that are not committed. Force removal discards the staged submodule registration."
        }
        let decision = SubmoduleLifecyclePolicy.decision(for: .remove(force: false), entry: entry)
        return decision.message ?? "Remove \(entry.path)?"
    }

    private var removeRequiresForce: Bool {
        if forceRemoveSubmodule {
            return true
        }
        guard let entry = submoduleToRemove else { return false }
        let decision = SubmoduleLifecyclePolicy.decision(for: .remove(force: false), entry: entry)
        return !decision.isAllowed && decision.requiresConfirmation
    }

    func body(content: Content) -> some View {
        content
            .replacingSheet(item: $submoduleToEdit) { entry in
                EditSubmoduleSheet(
                    entry: entry,
                    onSave: { url, branch in
                        try await onSaveSettings(entry, url, branch)
                    },
                    onRunRepositoryOperation: onRunRepositoryOperation
                )
            }
            .alert("Deinitialize Submodule", isPresented: Binding(
                get: { submoduleToDeinitialize != nil },
                set: { isPresented in
                    if !isPresented {
                        submoduleToDeinitialize = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) {
                    submoduleToDeinitialize = nil
                }
                Button(deinitializeRequiresForce ? "Force Deinitialize" : "Deinitialize", role: .destructive) {
                    if let entry = submoduleToDeinitialize {
                        onDeinitialize(entry, deinitializeRequiresForce)
                    }
                }
            } message: {
                Text(deinitializeMessage)
            }
            .alert("Remove Submodule", isPresented: Binding(
                get: { submoduleToRemove != nil },
                set: { isPresented in
                    if !isPresented {
                        submoduleToRemove = nil
                        forceRemoveSubmodule = false
                    }
                }
            )) {
                Button("Cancel", role: .cancel) {
                    submoduleToRemove = nil
                    forceRemoveSubmodule = false
                }
                Button(removeRequiresForce ? "Force Remove" : "Remove", role: .destructive) {
                    if let entry = submoduleToRemove {
                        onRemove(entry, removeRequiresForce)
                    }
                }
            } message: {
                Text(removeMessage)
            }
    }
}
