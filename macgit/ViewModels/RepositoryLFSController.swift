// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

@MainActor @Observable
final class RepositoryLFSController {
    let repository: URL
    var snapshot: GitLFSSnapshot?
    var isLoading = false
    var operationLabel: String?
    var transferProgress: GitLFSTransferProgress?
    var error: String?
    var notice: String?
    var remote = ""
    var review: GitLFSTrackingReview?
    var candidates: [GitLFSCandidate] = []
    var isScanning = false
    var conversion: GitLFSConversionReview?
    var showingRuntimePrompt = false
    private var operation: Task<Void, Never>?
    private var generation = 0

    private let authorizeAction: @MainActor () async -> Bool

    init(repository: URL, authorizeAction: @escaping @MainActor () async -> Bool) {
        self.repository = repository
        self.authorizeAction = authorizeAction
    }

    func load(promptForRuntime: Bool = false) async {
        guard operation == nil, await authorizeAction() else { return }
        generation += 1
        let generation = generation
        isLoading = true
        defer { if generation == self.generation { isLoading = false } }
        await GitLFSRuntimeController.shared.refresh()
        guard GitLFSRuntimeController.shared.status?.activeRuntime != nil else {
            if promptForRuntime { showingRuntimePrompt = true }
            return
        }
        do {
            let snapshot = try await GitStatusService.shared.lfsSnapshot(in: repository)
            guard generation == self.generation, !Task.isCancelled else { return }
            self.snapshot = snapshot
            if !snapshot.remotes.contains(remote) { remote = snapshot.suggestedRemote ?? "" }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func prepareRule(pattern: String, literal: Bool, removing: Bool) async {
        guard await authorizeAction() else { return }
        do {
            review = try await GitStatusService.shared.reviewLFSTracking(pattern: pattern, literal: literal, removing: removing, in: repository)
        } catch { self.error = error.localizedDescription }
    }

    func prepareRuleRemoval(pattern: String) async throws -> GitLFSTrackingReview {
        guard await authorizeAction() else {
            throw GitError.commandFailed("Access to Git LFS is unavailable.")
        }
        try Task.checkCancellation()
        let review = try await GitStatusService.shared.reviewLFSTracking(
            pattern: pattern, literal: false, removing: true, in: repository
        )
        try Task.checkCancellation()
        return review
    }

    func removeRule(review: GitLFSTrackingReview, refresh: @escaping @MainActor () async -> Void) async throws {
        guard operation == nil, operationLabel == nil else {
            throw GitError.commandFailed("Wait for the current Git LFS operation to finish.")
        }
        operationLabel = "Removing tracking rule…"
        defer { operationLabel = nil }
        guard await authorizeAction() else {
            throw GitError.commandFailed("Access to Git LFS is unavailable.")
        }
        try Task.checkCancellation()
        do {
            try await GitStatusService.shared.applyLFSTracking(review, in: repository)
            notice = "Completed. Review any changes in File Status before committing."
            error = nil
        } catch {
            await refresh()
            await load()
            throw error
        }
        await refresh()
        await load()
    }

    func perform(_ label: String, refresh: @escaping @MainActor () async -> Void,
                 action: @escaping @Sendable () async throws -> Void) {
        guard operation == nil, operationLabel == nil else { return }
        operationLabel = label
        transferProgress = nil
        error = nil
        notice = nil
        operation = Task {
            guard await authorizeAction() else {
                operation = nil
                operationLabel = nil
                return
            }
            do { try await action(); notice = "Completed. Review any changes in File Status before committing." }
            catch { self.error = Task.isCancelled ? "Operation cancelled. Repository state has been refreshed; completed changes were retained." : error.localizedDescription }
            operation = nil
            operationLabel = nil
            transferProgress = nil
            // Refresh even when the operation partially succeeded or was cancelled.
            let refreshTask = Task { @MainActor in
                await refresh()
                await self.load()
            }
            await refreshTask.value
        }
    }

    func scanLargeFiles(minimumMiB: Int) async {
        guard !isScanning, await authorizeAction() else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            candidates = try await GitStatusService.shared.largeLFSCandidates(minimumBytes: Int64(minimumMiB) * 1_048_576, in: repository)
            if candidates.isEmpty { notice = "No untracked-by-LFS files above this threshold were found. Ignored files are excluded." }
        } catch { self.error = error.localizedDescription }
    }

    func prepareConversion(path: String) async {
        guard await authorizeAction() else { return }
        do { conversion = try await GitStatusService.shared.reviewLFSConversion(path: path, in: repository) }
        catch { self.error = error.localizedDescription }
    }

    func cancel() { operation?.cancel() }
}
