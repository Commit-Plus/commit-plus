// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

/// Backs the file History window: commits that touched one file and the diff of the selected one.
@MainActor @Observable
final class FileHistoryController {
    let repositoryURL: URL
    let path: String
    let revision: String
    private(set) var entries: [FileHistoryEntry] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var diff: (id: String, hunks: [DiffHunk])?
    var selectedID: String? {
        didSet {
            guard oldValue != selectedID else { return }
            loadDiff()
        }
    }
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var diffTask: Task<Void, Never>?

    init(repositoryURL: URL, path: String, revision: String) {
        self.repositoryURL = repositoryURL
        self.path = path
        self.revision = revision
    }

    var selectedEntry: FileHistoryEntry? { entries.first { $0.id == selectedID } }

    func load() {
        cancel()
        isLoading = true
        error = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await GitStatusService.shared.fileHistory(path: path, revision: revision, in: repositoryURL)
                guard !Task.isCancelled else { return }
                entries = loaded
                isLoading = false
                if selectedEntry == nil { selectedID = loaded.first?.id }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        diffTask?.cancel()
        isLoading = false
    }

    private func loadDiff() {
        diffTask?.cancel()
        diff = nil
        guard let entry = selectedEntry else { return }
        diffTask = Task { [weak self] in
            guard let self else { return }
            let hunks = try? await GitStatusService.shared.commitDiff(for: entry.path, oldPath: entry.oldPath,
                in: entry.commit.hash, in: repositoryURL)
            guard !Task.isCancelled, selectedID == entry.id else { return }
            diff = (entry.id, hunks ?? [])
        }
    }
}
