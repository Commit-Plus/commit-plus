// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

@MainActor @Observable
final class RevisionBrowserController {
    let repositoryURL: URL
    let revision: String
    var lfsCredentialResolver: GitProviderCredentialResolver?
    private(set) var snapshot: RevisionBrowserSnapshot?
    private(set) var children: [String: [RevisionTreeEntry]] = [:]
    private(set) var expanded: Set<String> = []
    private(set) var loadingFolders: Set<String> = []
    private(set) var folderErrors: [String: String] = [:]
    private(set) var selectedEntry: RevisionTreeEntry?
    /// Set when `reveal(path:)` selects an entry, so the tree can scroll it into view.
    private(set) var revealRequest: (path: String, token: UUID)?
    private(set) var preview: RevisionFilePreview?
    private(set) var previewError: String?
    private(set) var isLoadingPreview = false
    private(set) var error: String?
    private(set) var isLoading = false
    @ObservationIgnored private let service: any RevisionBrowserServing
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var previewID = UUID()
    @ObservationIgnored private var folderTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?
    @ObservationIgnored private(set) var previewTask: Task<Void, Never>?

    init(repositoryURL: URL, revision: String, service: any RevisionBrowserServing = GitStatusService.shared) {
        self.repositoryURL = repositoryURL
        self.revision = revision
        self.service = service
    }

    var visibleEntries: [RevisionTreeEntry] {
        var result: [RevisionTreeEntry] = []
        func append(_ path: String) {
            for entry in children[path] ?? [] {
                result.append(entry)
                if expanded.contains(entry.path) { append(entry.path) }
            }
        }
        append("")
        return result
    }

    func load() {
        cancel()
        children = [:]
        expanded = []
        folderErrors = [:]
        snapshot = nil
        selectedEntry = nil
        preview = nil
        previewError = nil
        error = nil
        isLoading = true
        let id = generation
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await service.browserSnapshot(revision: revision, in: repositoryURL)
                let entries = try await service.browserEntries(treeID: resolved.commitID, parentPath: "", in: repositoryURL)
                guard generation == id, !Task.isCancelled else { return }
                snapshot = resolved
                children[""] = entries
                isLoading = false
            } catch {
                guard generation == id, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func toggle(_ entry: RevisionTreeEntry) {
        guard entry.isDirectory else { return }
        if expanded.contains(entry.path) {
            expanded.remove(entry.path)
            return
        }
        expanded.insert(entry.path)
        guard children[entry.path] == nil, folderTasks[entry.path] == nil else { return }
        folderErrors[entry.path] = nil
        loadingFolders.insert(entry.path)
        let id = generation
        folderTasks[entry.path] = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == id {
                    folderTasks[entry.path] = nil
                    loadingFolders.remove(entry.path)
                }
            }
            do {
                let entries = try await service.browserEntries(treeID: entry.objectID, parentPath: entry.path, in: repositoryURL)
                guard generation == id, !Task.isCancelled else { return }
                // Bound the complete window's tree cache, not just individual folders.
                guard children.values.reduce(0, { $0 + $1.count }) + entries.count <= 50_000 else {
                    throw GitError.commandFailed("Tree limit reached (50,000 entries). Reopen the browser to browse other folders.")
                }
                children[entry.path] = entries
            } catch {
                guard generation == id, !Task.isCancelled else { return }
                folderErrors[entry.path] = error.localizedDescription
            }
        }
    }

    func select(_ entry: RevisionTreeEntry) {
        previewTask?.cancel()
        previewID = UUID()
        selectedEntry = entry
        preview = nil
        previewError = nil
        isLoadingPreview = false
        guard !entry.isDirectory else { return }
        let id = previewID
        let generation = generation
        isLoadingPreview = true
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await service.browserPreview(entry: entry, in: repositoryURL)
                guard self.generation == generation, previewID == id, !Task.isCancelled else { return }
                preview = loaded
                isLoadingPreview = false
            } catch {
                guard self.generation == generation, previewID == id, !Task.isCancelled else { return }
                previewError = error.localizedDescription
                isLoadingPreview = false
            }
        }
    }

    /// Expands the folders leading to `path` and selects it. Returns false when the
    /// revision has no such entry or the browser was reloaded meanwhile.
    @discardableResult
    func reveal(path: String) async -> Bool {
        await loadTask?.value
        guard !Task.isCancelled else { return false }
        let id = generation
        let components = path.split(separator: "/").map(String.init)
        var parent = ""
        for (index, name) in components.enumerated() {
            let current = parent.isEmpty ? name : parent + "/" + name
            guard let entry = children[parent]?.first(where: { $0.path == current }) else { return false }
            if index == components.count - 1 {
                select(entry)
                revealRequest = (current, UUID())
                return true
            }
            guard entry.isDirectory else { return false }
            if !expanded.contains(current) { toggle(entry) }
            if let task = folderTasks[current] { await task.value }
            guard generation == id, !Task.isCancelled else { return false }
            parent = current
        }
        return false
    }

    func downloadLFSPreview(remote: String) {
        guard let entry = selectedEntry, let snapshot, preview?.lfsPointer != nil else { return }
        previewTask?.cancel()
        let id = previewID
        previewError = nil
        isLoadingPreview = true
        previewTask = Task {
            do {
                try await GitStatusService.shared.downloadLFSPreview(path: entry.path, revision: snapshot.commitID, remote: remote, in: repositoryURL, credentialResolver: lfsCredentialResolver)
                let loaded = try await service.browserPreview(entry: entry, in: repositoryURL)
                guard id == previewID, !Task.isCancelled else { return }
                preview = loaded
            } catch {
                guard id == previewID, !Task.isCancelled else { return }
                previewError = error.localizedDescription
            }
            if id == previewID { isLoadingPreview = false }
        }
    }

    func folderTask(for path: String) -> Task<Void, Never>? { folderTasks[path] }

    func cancel() {
        generation = UUID()
        previewID = UUID()
        loadTask?.cancel()
        previewTask?.cancel()
        for task in folderTasks.values { task.cancel() }
        folderTasks = [:]
        loadingFolders = []
        isLoading = false
        isLoadingPreview = false
    }

    func releaseResources() {
        cancel()
        snapshot = nil
        children.removeAll()
        expanded.removeAll()
        folderErrors.removeAll()
        selectedEntry = nil
        preview = nil
        previewError = nil
    }
}
