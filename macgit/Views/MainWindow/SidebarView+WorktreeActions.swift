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
import AppKit
import Foundation

extension SidebarView {
    var canCreateWorktree: Bool {
        let trimmedPath = worktreePathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }

        switch createWorktreeMode {
        case .existingBranch:
            return !selectedExistingWorktreeBranch.isEmpty
        case .newBranch:
            return !sanitizedWorktreeBranchName(newWorktreeBranchName).isEmpty
        }
    }

    var canMoveWorktree: Bool {
        guard let entry = worktreeToMove else { return false }
        let trimmedPath = worktreeMovePathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }

        let candidate = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
        return candidate != entry.path.standardizedFileURL.path
    }

    var canCheckoutWorktreeBranch: Bool {
        !selectedWorktreeCheckoutBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var worktreeRemovalNeedsForce: Bool {
        guard let entry = pendingWorktreeRemoval else { return false }
        return entry.dirtyCount > 0 || entry.isLocked
    }

    var worktreeRemovalMessage: String {
        guard let entry = pendingWorktreeRemoval else {
            return "Are you sure you want to remove this worktree?"
        }

        if entry.isLocked && entry.dirtyCount > 0 {
            return "This worktree is locked and has \(entry.dirtyCount) uncommitted changes. Remove it with --force?"
        }

        if entry.isLocked {
            return "This worktree is locked. Remove it with --force?"
        }

        if entry.dirtyCount > 0 {
            return "This worktree has \(entry.dirtyCount) uncommitted changes. Remove it with --force?"
        }

        return "Remove this worktree? The branch and commits are not deleted."
    }

    func loadWorktrees(force: Bool = false) async {
        if !force && (hasLoadedWorktrees || activeWorktreeLoadID != nil) {
            return
        }

        let loadID = UUID()
        activeWorktreeLoadID = loadID
        isLoadingWorktrees = !hasLoadedWorktrees
        defer {
            if activeWorktreeLoadID == loadID {
                activeWorktreeLoadID = nil
                isLoadingWorktrees = false
            }
        }

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repositoryURL)
        guard activeWorktreeLoadID == loadID else { return }
        await MainActor.run {
            worktreeEntries = entries
            hasLoadedWorktrees = true
        }
    }

    func isCurrentRepositoryWorktree(_ entry: WorktreeEntry) -> Bool {
        entry.path.standardizedFileURL == repositoryURL.standardizedFileURL
    }

    func isMissingWorktree(_ entry: WorktreeEntry) -> Bool {
        !isCurrentRepositoryWorktree(entry)
            && (entry.dirtyCount < 0 || !FileManager.default.fileExists(atPath: entry.path.path))
    }

    func selectWorktree(_ entry: WorktreeEntry) {
        if isMissingWorktree(entry) {
            showMissingWorktreeAlert(for: entry)
            return
        }

        selection = .worktree(entry.path)
    }

    func openWorktree(_ entry: WorktreeEntry) {
        if isMissingWorktree(entry) {
            showMissingWorktreeAlert(for: entry)
            return
        }

        onRequestOpenWorktree(entry.path)
    }

    func showMissingWorktreeAlert(for entry: WorktreeEntry) {
        missingWorktreeEntry = entry
        showingMissingWorktreeAlert = true
    }

    func beginEditingWorktreeLabel(_ entry: WorktreeEntry) {
        worktreeToLabel = entry
        worktreeLabelInput = entry.label ?? ""
    }

    func beginLockingWorktree(_ entry: WorktreeEntry) {
        worktreeToLock = entry
        worktreeLockReasonInput = ""
    }

    func beginMovingWorktree(_ entry: WorktreeEntry) {
        worktreeToMove = entry
        worktreeMovePathInput = suggestedMovedWorktreePath(for: entry).path
        worktreeMoveErrorMessage = nil
    }

    func saveWorktreeLabel() async {
        guard let entry = worktreeToLabel else { return }

        do {
            try await GitStatusService.shared.setWorktreeLabel(worktreeLabelInput, for: entry.path, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                worktreeToLabel = nil
                worktreeLabelInput = ""
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func clearWorktreeLabel(_ entry: WorktreeEntry) async {
        do {
            try await GitStatusService.shared.removeWorktreeLabel(for: entry.path, in: repositoryURL)
            await loadWorktrees(force: true)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func lockWorktree(_ entry: WorktreeEntry) async {
        await MainActor.run {
            isUpdatingWorktreeLock = true
        }
        defer {
            Task { @MainActor in
                isUpdatingWorktreeLock = false
            }
        }

        do {
            try await GitStatusService.shared.lockWorktree(
                at: entry.path,
                reason: worktreeLockReasonInput,
                in: repositoryURL
            )
            await loadWorktrees(force: true)
            await MainActor.run {
                worktreeToLock = nil
                worktreeLockReasonInput = ""
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func unlockWorktree(_ entry: WorktreeEntry) async {
        do {
            try await GitStatusService.shared.unlockWorktree(at: entry.path, in: repositoryURL)
            await loadWorktrees(force: true)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func pruneWorktrees() async {
        do {
            try await GitStatusService.shared.pruneWorktrees(in: repositoryURL)
            await loadWorktrees(force: true)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func prepareCreateWorktreeSheet() async {
        let branches = await GitStatusService.shared.cachedLocalBranches(in: repositoryURL)
        let current = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        let root: URL
        if let gitDirectory = try? await GitStatusService.shared.gitCommonDirectory(in: repositoryURL) {
            root = gitDirectory.deletingLastPathComponent()
        } else {
            root = repositoryURL
        }

        await MainActor.run {
            currentWorktreeBranch = current
            availableWorktreeBranches = branches.filter { !$0.isEmpty }
            selectedExistingWorktreeBranch = preferredExistingWorktreeBranch(from: branches, currentBranch: current)
            newWorktreeBaseBranch = current.isEmpty ? (branches.first ?? "") : current
            newWorktreeBranchName = ""
            worktreeRootURL = root
            customWorktreePath = false
            worktreeLabelDraft = ""
            worktreeCreationErrorMessage = nil
            isCreatingWorktree = false
            openWorktreeAfterCreate = true
            refreshWorktreePathIfNeeded(force: true)
            showingCreateWorktreeSheet = true
        }
    }

    func preferredExistingWorktreeBranch(from branches: [String], currentBranch: String) -> String {
        if let other = branches.first(where: { $0 != currentBranch }) {
            return other
        }
        return branches.first ?? ""
    }

    func refreshWorktreePathIfNeeded(force: Bool) {
        guard force || !customWorktreePath else { return }
        worktreePathInput = defaultWorktreePath().path
        customWorktreePath = false
    }

    func defaultWorktreePath() -> URL {
        let baseRoot = worktreeRootURL ?? repositoryURL
        return WorktreePathPolicy.suggestedPath(
            root: baseRoot,
            branchName: defaultWorktreeFolderName()
        )
    }

    func defaultWorktreeFolderName() -> String {
        switch createWorktreeMode {
        case .existingBranch:
            return sanitizedWorktreeFolderComponent(selectedExistingWorktreeBranch)
        case .newBranch:
            return sanitizedWorktreeFolderComponent(sanitizedWorktreeBranchName(newWorktreeBranchName))
        }
    }

    func sanitizedWorktreeBranchName(_ input: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/")
        var sanitized = ""
        for scalar in input.unicodeScalars {
            if allowed.contains(scalar) {
                sanitized.append(Character(scalar))
            } else {
                sanitized.append("-")
            }
        }

        while sanitized.contains("//") {
            sanitized = sanitized.replacingOccurrences(of: "//", with: "/")
        }

        return sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-/"))
    }

    func sanitizedWorktreeFolderComponent(_ input: String) -> String {
        WorktreePathPolicy.folderName(for: input)
    }

    func suggestedMovedWorktreePath(for entry: WorktreeEntry) -> URL {
        let currentPath = entry.path.standardizedFileURL
        let parent = currentPath.deletingLastPathComponent()
        let newName = currentPath.lastPathComponent + "-renamed"
        return parent.appendingPathComponent(newName, isDirectory: true)
    }

    func createWorktree() async {
        let path = URL(fileURLWithPath: worktreePathInput)
        let target: WorktreeAddTarget
        let trimmedBaseBranch = newWorktreeBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        switch createWorktreeMode {
        case .existingBranch:
            target = .existingBranch(selectedExistingWorktreeBranch)
        case .newBranch:
            target = .newBranch(
                name: sanitizedWorktreeBranchName(newWorktreeBranchName),
                base: trimmedBaseBranch.isEmpty ? nil : trimmedBaseBranch
            )
        }

        await MainActor.run {
            isCreatingWorktree = true
            worktreeCreationErrorMessage = nil
        }
        defer {
            Task { @MainActor in
                isCreatingWorktree = false
            }
        }

        do {
            try await GitStatusService.shared.addWorktree(
                at: path,
                target: target,
                label: worktreeLabelDraft,
                in: repositoryURL
            )
            await loadWorktrees(force: true)
            await MainActor.run {
                showingCreateWorktreeSheet = false
                worktreeCreationErrorMessage = nil
            }
            if openWorktreeAfterCreate {
                await MainActor.run {
                    onRequestOpenWorktree(path)
                }
            }
        } catch {
            await MainActor.run {
                worktreeCreationErrorMessage = error.localizedDescription
            }
        }
    }

    func moveWorktree(_ entry: WorktreeEntry) async {
        await MainActor.run {
            isMovingWorktree = true
            worktreeMoveErrorMessage = nil
        }
        defer {
            Task { @MainActor in
                isMovingWorktree = false
            }
        }

        let destination = URL(fileURLWithPath: worktreeMovePathInput)

        do {
            try await GitStatusService.shared.moveWorktree(from: entry.path, to: destination, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                worktreeToMove = nil
                worktreeMovePathInput = ""
                worktreeMoveErrorMessage = nil
            }
        } catch {
            await MainActor.run {
                worktreeMoveErrorMessage = error.localizedDescription
            }
        }
    }

    func chooseReplacementWorktreeFolder(for entry: WorktreeEntry) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select the new location for \(entry.displayTitle)"
            panel.prompt = "Change Folder"

            panel.beginSheetModal(for: NSApp.keyWindow!) { result in
                missingWorktreeEntry = nil

                guard result == .OK, let url = panel.url else {
                    return
                }

                Task {
                    await repairMissingWorktree(entry, newPath: url)
                }
            }
        }
    }

    func repairMissingWorktree(_ entry: WorktreeEntry, newPath: URL) async {
        do {
            try await GitStatusService.shared.repairWorktreeLocation(from: entry.path, to: newPath, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                selection = .worktree(newPath)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func prepareCheckoutWorktreeSheet(for entry: WorktreeEntry) async {
        let branches = await GitStatusService.shared.cachedLocalBranches(in: repositoryURL).filter { !$0.isEmpty }
        let selectedBranch = branches.contains(entry.branch ?? "") ? (entry.branch ?? "") : (branches.first ?? "")

        await MainActor.run {
            worktreeToCheckout = entry
            availableWorktreeCheckoutBranches = branches
            selectedWorktreeCheckoutBranch = selectedBranch
            worktreeCheckoutErrorMessage = nil
            pendingWorktreeForceCheckout = nil
            showingWorktreeForceCheckoutConfirmation = false
        }
    }

    func checkoutWorktree(_ entry: WorktreeEntry, force: Bool) async {
        await MainActor.run {
            isCheckingOutWorktreeBranch = true
            worktreeCheckoutErrorMessage = nil
            showingWorktreeForceCheckoutConfirmation = false
        }
        defer {
            Task { @MainActor in
                isCheckingOutWorktreeBranch = false
            }
        }

        do {
            try await GitStatusService.shared.checkoutBranch(
                selectedWorktreeCheckoutBranch,
                inWorktree: entry.path,
                force: force,
                repositoryURL: repositoryURL
            )
            await loadWorktrees(force: true)
            await MainActor.run {
                worktreeToCheckout = nil
                worktreeCheckoutErrorMessage = nil
                selectedWorktreeCheckoutBranch = ""
                availableWorktreeCheckoutBranches = []
                pendingWorktreeForceCheckout = nil
            }
        } catch {
            await MainActor.run {
                worktreeCheckoutErrorMessage = error.localizedDescription
                pendingWorktreeForceCheckout = nil
            }
        }
    }

    func deleteMissingWorktree(_ entry: WorktreeEntry) async {
        do {
            try await GitStatusService.shared.removeWorktree(at: entry.path, force: true, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                missingWorktreeEntry = nil
                showingMissingWorktreeAlert = false
                if selection == .worktree(entry.path) {
                    selection = nil
                }
            }
        } catch {
            await MainActor.run {
                missingWorktreeEntry = nil
                showingMissingWorktreeAlert = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func removeWorktree(_ entry: WorktreeEntry, force: Bool) async {
        do {
            try await GitStatusService.shared.removeWorktree(at: entry.path, force: force, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                pendingWorktreeRemoval = nil
                showingWorktreeRemovalConfirmation = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
