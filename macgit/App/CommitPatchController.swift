// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

@MainActor @Observable
final class CommitPatchController {
    var prepared: PreparedCommitPatch?
    private(set) var isBusy = false
    var errorMessage = ""
    var showingError = false
    private(set) var reviewError: String?

    func prepare(_ request: CommitPatchRequest, in repositoryURL: URL) {
        guard !isBusy, prepared == nil else { return }
        reviewError = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                prepared = try await GitStatusService.shared.prepareCommitPatch(request, in: repositoryURL)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    func apply(undoManager: GitUndoManager?, syncState: SyncState?, run: RepositoryOperationRunner) {
        guard let prepared, !isBusy else { return }
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
}
