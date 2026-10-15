// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

@MainActor
final class YourRepositoriesStore: ObservableObject {
    static let shared = YourRepositoriesStore()

    @Published private(set) var folders: [URL]
    @Published private(set) var repositories: [YourRepository] = []
    @Published private(set) var isScanning = false

    private var observation: AnyCancellable?
    private var scanTask: Task<Void, Never>?
    private var scanningRoots: [URL] = []
    private var lastScan: Date?
    private let catalog: RepositoryCatalogStore

    init(catalog injectedCatalog: RepositoryCatalogStore? = nil) {
        let catalog = injectedCatalog ?? .shared
        self.catalog = catalog
        folders = []
        observation = catalog.$snapshot.sink { [weak self] state in
            guard let self else { return }
            let roots = state.roots.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            let folders = roots.map { URL(fileURLWithPath: $0.path, isDirectory: true) }
            var seen: Set<UUID> = []
            let repositories = roots.flatMap { root in
                state.memberships.filter { $0.rootID == root.id }.compactMap { membership -> YourRepository? in
                    guard seen.insert(membership.repositoryID).inserted,
                          let record = state.repositories.first(where: { $0.id == membership.repositoryID }) else { return nil }
                    return YourRepository(url: URL(fileURLWithPath: record.path), rootURL: URL(fileURLWithPath: root.path, isDirectory: true))
                }
            }.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            if self.folders != folders { self.folders = folders }
            if self.repositories != repositories { self.repositories = repositories }
        }
    }

    enum AddResult {
        case added
        case duplicate
        case homeFolder
    }

    func addFolders(_ urls: [URL]) -> AddResult {
        let home = Self.canonical(FileManager.default.homeDirectoryForCurrentUser)
        let fileSystemRoot = URL(fileURLWithPath: "/", isDirectory: true)
        let normalized = urls.map(Self.canonical)
        if normalized.contains(where: { $0.path == home.path || $0.path == fileSystemRoot.path }) { return .homeFolder }

        let existingPaths = Set(folders.map(\.path))
        let added = normalized.filter { !existingPaths.contains($0.path) }
        guard !added.isEmpty else { return .duplicate }
        catalog.addRoots(added)
        return .added
    }

    func removeFolder(_ url: URL) {
        catalog.removeRoot(url)
    }

    func scan(force: Bool = false) async {
        await catalog.ready()
        let roots = folders
        if let scanTask, scanningRoots == roots { await scanTask.value; return }
        if !force, scanningRoots == roots, let lastScan, Date.now.timeIntervalSince(lastScan) < 30 { return }
        scanTask?.cancel()
        scanningRoots = roots
        isScanning = true
        let task = Task { [weak self, catalog] in
            for root in roots {
                guard !Task.isCancelled else { return }
                let worker = Task.detached(priority: .utility) { Self.scanRoot(root) }
                let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                await catalog.reconcile(root: root, repositories: result.urls, error: result.error)
            }
            guard !Task.isCancelled else { return }
            self?.isScanning = false
            self?.lastScan = .now
            self?.scanTask = nil
        }
        scanTask = task
        await task.value
    }

    nonisolated static func scanRepositories(in roots: [URL]) -> [YourRepository] {
        var repositoriesByURL: [URL: YourRepository] = [:]
        for root in roots {
            guard !Task.isCancelled else { break }
            for url in scanRoot(root).urls {
                if repositoriesByURL[url] == nil {
                    repositoriesByURL[url] = YourRepository(url: url, rootURL: root.standardizedFileURL)
                }
            }
        }

        return repositoriesByURL.values.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }

    nonisolated static func scanRoot(_ root: URL) -> (urls: [URL], error: String?) {
        let manager = FileManager.default
        do {
            _ = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            var errorMessage: String?
            let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants]) { _, error in
                errorMessage = error.localizedDescription
                return true
            }
            var urls: [URL] = []
            if manager.fileExists(atPath: root.appendingPathComponent(".git").path) { return ([root], nil) }
            guard let enumerator else { return ([], "Could not enumerate folder.") }
            for case let url as URL in enumerator {
                guard !Task.isCancelled else { return ([], "Scan cancelled.") }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isDirectory == true else { continue }
                if url.lastPathComponent == ".git" { enumerator.skipDescendants(); continue }
                if manager.fileExists(atPath: url.appendingPathComponent(".git").path) {
                    urls.append(url.standardizedFileURL)
                    enumerator.skipDescendants()
                }
            }
            return (urls, errorMessage)
        } catch { return ([], error.localizedDescription) }
    }

    private nonisolated static func canonical(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.resolvingSymlinksInPath().path, isDirectory: true)
    }
}
