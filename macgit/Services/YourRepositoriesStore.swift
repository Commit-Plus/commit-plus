// SPDX-License-Identifier: AGPL-3.0-or-later
import Combine
import Foundation

@MainActor
final class YourRepositoriesStore: ObservableObject {
    static let shared = YourRepositoriesStore()

    @Published private(set) var folders: [URL]
    @Published private(set) var repositories: [YourRepository] = []
    @Published private(set) var isScanning = false

    private let defaultsKey = "dev.thanhtran.macgit.yourRepositoryFolders"
    private var scanGeneration = UUID()

    private init(defaults: UserDefaults = .standard) {
        folders = (defaults.array(forKey: defaultsKey) as? [String] ?? [])
            .map { Self.canonical(URL(fileURLWithPath: $0, isDirectory: true)) }
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
        if normalized.contains(home) || normalized.contains(fileSystemRoot) { return .homeFolder }

        var added = false
        for url in normalized where !folders.contains(url) {
            folders.append(url)
            added = true
        }
        guard added else { return .duplicate }
        folders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        saveFolders()
        return .added
    }

    func removeFolder(_ url: URL) {
        let normalized = Self.canonical(url)
        folders.removeAll { $0 == normalized }
        repositories.removeAll { $0.rootURL == normalized }
        saveFolders()
    }

    func scan() async {
        let request = UUID()
        scanGeneration = request
        if repositories.isEmpty { isScanning = true }
        let roots = folders
        let scanned = await Task.detached(priority: .utility) {
            Self.scanRepositories(in: roots)
        }.value
        guard request == scanGeneration, !Task.isCancelled else { return }
        if repositories != scanned { repositories = scanned }
        isScanning = false
    }

    nonisolated static func scanRepositories(in roots: [URL]) -> [YourRepository] {
        let fileManager = FileManager.default
        var repositoriesByURL: [URL: YourRepository] = [:]

        for root in roots {
            guard !Task.isCancelled else { break }
            let normalizedRoot = root.standardizedFileURL
            guard directoryExists(normalizedRoot, fileManager: fileManager) else { continue }
            collectRepository(at: normalizedRoot, root: normalizedRoot, into: &repositoriesByURL, fileManager: fileManager)

            guard repositoriesByURL[normalizedRoot] == nil,
                  let enumerator = fileManager.enumerator(
                    at: normalizedRoot,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                  ) else { continue }

            for case let candidate as URL in enumerator {
                guard !Task.isCancelled else { break }
                guard directoryExists(candidate, fileManager: fileManager) else { continue }
                if candidate.lastPathComponent == ".git" {
                    enumerator.skipDescendants()
                    continue
                }
                if collectRepository(
                    at: candidate.standardizedFileURL,
                    root: normalizedRoot,
                    into: &repositoriesByURL,
                    fileManager: fileManager
                ) {
                    enumerator.skipDescendants()
                }
            }
        }

        return repositoriesByURL.values.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }

    @discardableResult
    private nonisolated static func collectRepository(
        at url: URL,
        root: URL,
        into repositories: inout [URL: YourRepository],
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.appendingPathComponent(".git").path) else { return false }
        if repositories[url] == nil {
            repositories[url] = YourRepository(url: url, rootURL: root)
        }
        return true
    }

    private nonisolated static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func saveFolders() {
        UserDefaults.standard.set(folders.map(\.path), forKey: defaultsKey)
    }

    private nonisolated static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
