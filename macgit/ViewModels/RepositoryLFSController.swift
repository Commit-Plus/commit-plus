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

    init(repository: URL) { self.repository = repository }

    func load(promptForRuntime: Bool = false) async {
        guard operation == nil else { return }
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
        do {
            review = try await GitStatusService.shared.reviewLFSTracking(pattern: pattern, literal: literal, removing: removing, in: repository)
        } catch { self.error = error.localizedDescription }
    }

    func perform(_ label: String, refresh: @escaping @MainActor () async -> Void,
                 action: @escaping @Sendable () async throws -> Void) {
        guard operation == nil else { return }
        operationLabel = label
        transferProgress = nil
        error = nil
        notice = nil
        operation = Task {
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
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            candidates = try await GitStatusService.shared.largeLFSCandidates(minimumBytes: Int64(minimumMiB) * 1_048_576, in: repository)
            if candidates.isEmpty { notice = "No untracked-by-LFS files above this threshold were found. Ignored files are excluded." }
        } catch { self.error = error.localizedDescription }
    }

    func prepareConversion(path: String) async {
        do { conversion = try await GitStatusService.shared.reviewLFSConversion(path: path, in: repository) }
        catch { self.error = error.localizedDescription }
    }

    func cancel() { operation?.cancel() }
}
