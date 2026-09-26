//
//  CommitPatchController.swift
//  macgit
//
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software; you can redistribute it and/or modify
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
import Observation

@MainActor @Observable
final class CommitPatchController {
    var prepared: PreparedCommitPatch? {
        didSet { if prepared == nil { closeConflict() } }
    }
    private(set) var isResolving = false
    @ObservationIgnored private var conflictWindow: CommitPatchConflictWindowController?

    func openConflict(_ file: CommitPatchReviewFile) {
        guard !isBusy, prepared?.reviewFiles.contains(where: { $0.id == file.id && $0.state == .conflict }) == true else { return }
        if let conflictWindow {
            conflictWindow.showWindow(nil)
            conflictWindow.window?.makeKeyAndOrderFront(nil)
            return
        }
        let window = CommitPatchConflictWindowController()
        conflictWindow = window
        isResolving = true
        window.show(file: file, controller: self)
    }

    func closeConflict() {
        let window = conflictWindow
        conflictWindow = nil
        isResolving = false
        window?.close()
    }

    private(set) var isBusy = false
    private(set) var isPreparing = false
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var preparationID = UUID()
    var errorMessage = ""
    var showingError = false
    private(set) var reviewError: String?

    func prepare(_ request: CommitPatchRequest, in repositoryURL: URL) {
        guard !isBusy, prepared == nil else { return }
        reviewError = nil
        isBusy = true
        isPreparing = true
        let id = UUID()
        preparationID = id
        preparationTask = Task {
            defer {
                if preparationID == id {
                    isBusy = false
                    isPreparing = false
                    preparationTask = nil
                }
            }
            do {
                let result = try await GitStatusService.shared.prepareCommitPatch(request, in: repositoryURL)
                guard preparationID == id, !Task.isCancelled else { return }
                prepared = result
            } catch {
                guard preparationID == id, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func cancelPreparation() {
        guard isPreparing else { return }
        preparationID = UUID()
        preparationTask?.cancel()
        preparationTask = nil
        isPreparing = false
        isBusy = false
    }

    func apply(undoManager: GitUndoManager?, syncState: SyncState?, run: RepositoryOperationRunner) {
        guard let prepared, !isBusy else { return }
        guard !prepared.hasConflicts else { return }
        guard prepared.hasChanges else {
            self.prepared = nil
            return
        }
        reviewError = nil
        isBusy = true
        run("\(prepared.request.direction.rawValue) selected changes…") { [self] in
            defer { isBusy = false }
            do {
                try await GitStatusService.shared.applyCommitPatch(prepared)
                undoManager?.register(GitUndoEntry(
                    repositoryURL: prepared.repositoryURL,
                    label: "\(prepared.request.direction.rawValue) selected changes from \(prepared.request.commit.prefix(7))",
                    undoOperation: .sequence([.requireHead(prepared.targetHead), .checkedWorkingTreePatch(patch: prepared.patch, reverse: true)]),
                    redoOperation: .sequence([.requireHead(prepared.targetHead), .checkedWorkingTreePatch(patch: prepared.patch, reverse: false)])
                ))
                self.prepared = nil
                await syncState?.refresh(repositoryURL: prepared.repositoryURL)
                NotificationCenter.default.post(name: .repositoryDidChange, object: nil,
                    userInfo: ["repositoryURL": prepared.repositoryURL])
            } catch {
                reviewError = error.localizedDescription
            }
        }
    }

    /// Skipping only changes the preview; Apply revalidates the repository before writing.
    func skip(fileID: UUID) {
        guard !isBusy, var updated = prepared,
              let index = updated.reviewFiles.firstIndex(where: { $0.id == fileID && $0.state == .conflict }) else { return }
        updated.reviewFiles[index].state = .skipped
        updated.reviewFiles[index].conflict = nil
        updated.rebuildPatch()
        reviewError = nil
        prepared = updated
        closeConflict()
    }

    func resolveAndClose(fileID: UUID, result: String) {
        guard !isBusy else { return }
        Task { [self] in
            if await resolve(fileID: fileID, result: result) {
                closeConflict()
            }
        }
    }

    func resolve(fileID: UUID, result: String?) async -> Bool {
        guard let prepared, !isBusy else { return false }
        isBusy = true
        reviewError = nil
        defer { isBusy = false }
        do {
            self.prepared = try await GitStatusService.shared.resolveCommitPatch(prepared, fileID: fileID, result: result)
            return true
        } catch {
            reviewError = error.localizedDescription
            return false
        }
    }
}
