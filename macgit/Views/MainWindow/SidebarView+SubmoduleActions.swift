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

extension SidebarView {
    func presentDeinitializeSubmoduleConfirmation(_ entry: GitSubmoduleEntry) {
        let decision = SubmoduleLifecyclePolicy.decision(for: .deinitialize(force: false), entry: entry)
        guard decision.requiresConfirmation else {
            errorMessage = decision.message ?? "This submodule cannot be deinitialized."
            showingError = true
            return
        }
        submoduleToDeinitialize = entry
    }

    func presentRemoveSubmoduleConfirmation(_ entry: GitSubmoduleEntry) {
        let decision = SubmoduleLifecyclePolicy.decision(for: .remove(force: false), entry: entry)
        guard decision.requiresConfirmation else {
            errorMessage = decision.message ?? "This submodule cannot be removed."
            showingError = true
            return
        }
        submoduleToRemove = entry
    }

    func runSubmoduleDeinitialize(_ entry: GitSubmoduleEntry, force: Bool) {
        submoduleToDeinitialize = nil
        onRunRepositoryOperation("Deinitializing \(entry.path)...") {
            do {
                try await onRequestDeinitializeSubmodule(entry.path, force)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    func runSubmoduleRemove(_ entry: GitSubmoduleEntry, force: Bool) {
        submoduleToRemove = nil
        onRunRepositoryOperation("Removing submodule \(entry.path)...") {
            do {
                try await onRequestRemoveSubmodule(entry.path, force)
                await MainActor.run {
                    selection = .item(.fileStatus)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    @MainActor
    func loadSubmodules(force: Bool = false) async {
        if !force && hasLoadedSubmodules {
            return
        }

        let loadID = UUID()
        activeSubmoduleLoadID = loadID
        isLoadingSubmodules = true

        do {
            let entries = try await GitStatusService.shared.submodules(in: repositoryURL)
            guard activeSubmoduleLoadID == loadID else { return }
            let hadLoadedSubmodules = hasLoadedSubmodules
            let allFolders = collectFolderPaths(
                from: SidebarTreeBuilder.buildTree(from: entries.map(\.path))
            )
            submoduleEntries = entries
            hasLoadedSubmodules = true
            isLoadingSubmodules = false
            activeSubmoduleLoadID = nil
            // Refreshes preserve the user's tree state while dropping removed
            // folders. The selected submodule is revealed only on initial load.
            expandedSubmoduleFolders = expandedSubmoduleFolders.intersection(allFolders)
            if !hadLoadedSubmodules, case .submodule(let path) = selection {
                expandedSubmoduleFolders.formUnion(
                    SidebarTreeBuilder.expandedFolderPaths(revealing: path)
                        .intersection(allFolders)
                )
            }
            if case .submodule(let path) = selection,
               !entries.contains(where: { $0.path == path }) {
                selection = nil
            }
        } catch is CancellationError {
            if activeSubmoduleLoadID == loadID {
                isLoadingSubmodules = false
                activeSubmoduleLoadID = nil
            }
        } catch {
            guard activeSubmoduleLoadID == loadID else { return }
            hasLoadedSubmodules = true
            isLoadingSubmodules = false
            activeSubmoduleLoadID = nil
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
