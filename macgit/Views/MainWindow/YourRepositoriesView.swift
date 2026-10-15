// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

enum RepositoryPickerListMode: String, CaseIterable {
    case plain
    case tree

    var icon: String { self == .plain ? "list.bullet" : "list.bullet.indent" }
}

struct YourRepositoriesView: View {
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject private var bookmarkController: RepositoryBookmarkController
    @ObservedObject var store: YourRepositoriesStore
    @Binding var mode: RepositoryPickerListMode
    @Binding var searchText: String
    @Binding var expandedFolders: Set<URL>
    let showBookmarkedOnly: Bool
    let sortOption: RepoPickerSortOption
    let selectedFilterTypes: Set<RepoPickerFilterType>
    let onOpen: (URL) -> Void
    @State private var message: String?
    @State private var repositoryIcons: [URL: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if store.folders.isEmpty {
                    ContentUnavailableView(
                        "No Repository Folders",
                        systemImage: "folder.badge.plus",
                        description: Text("Add one or more folders to discover Git repositories inside them.")
                    )
                } else if store.isScanning && store.repositories.isEmpty {
                    ProgressView("Scanning folders…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    ContentUnavailableView(
                        "No Repositories Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try another folder or clear the filter.")
                    )
                } else {
                    YourRepositoriesNativeList(
                        rows: rows,
                        textScale: textScale,
                        onOpen: onOpen,
                        onToggleFolder: toggleFolder,
                        onToggleStar: toggleStar,
                        onRemoveRoot: removeFolder
                    )
                }
            }
            .frame(minHeight: 180, maxHeight: .infinity)

            HStack {
                Button("Add Folder", systemImage: "plus", action: chooseFolders)
                    .buttonStyle(.bordered)
                    .sidebarPointingHandCursor()
                if store.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").foregroundStyle(.secondary)
                } else if !store.folders.isEmpty {
                    Text("\(store.repositories.count) repositories in \(store.folders.count) folders")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.caption.scaled(by: textScale))
        }
        .task(id: store.folders.map(\.path)) { await store.scan() }
        .task(id: store.repositories.map(\.url)) {
            await loadRepositoryIcons()
        }
        .alert("Your Repositories", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var filteredRepositories: [YourRepository] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.repositories.filter { repository in
            if showBookmarkedOnly && bookmarkController.bookmarkID(linkedTo: repository.url) == nil {
                return false
            }
            if !selectedFilterTypes.isEmpty {
                let type = filterType(for: repository.url)
                guard let type, selectedFilterTypes.contains(type) else { return false }
            }
            return query.isEmpty
                || repository.name.localizedCaseInsensitiveContains(query)
                || repository.url.path.localizedCaseInsensitiveContains(query)
        }
        switch sortOption {
        case .lastOpened:
            return filtered.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var rows: [YourRepositoriesNativeList.Row] {
        switch mode {
        case .plain:
            return filteredRepositories.map { repositoryRow($0) }
        case .tree:
            return treeRows()
        }
    }

    private func treeRows() -> [YourRepositoriesNativeList.Row] {
        var result: [YourRepositoriesNativeList.Row] = []
        let repositories = filteredRepositories
        for root in store.folders {
            let children = repositories.filter { $0.rootURL == root }
            guard !children.isEmpty || searchText.isEmpty else { continue }
            appendFolder(root, root: root, repositories: children, depth: 0, isRoot: true, into: &result)
        }
        return result
    }

    private func appendFolder(
        _ folder: URL,
        root: URL,
        repositories: [YourRepository],
        depth: Int,
        isRoot: Bool,
        into rows: inout [YourRepositoriesNativeList.Row]
    ) {
        let expanded = expandedFolders.contains(folder)
        rows.append(.init(
            id: "folder:\(folder.path)",
            depth: depth,
            content: .folder(folder, folder.lastPathComponent, expanded, isRoot)
        ))
        guard expanded else { return }

        let direct = repositories.filter {
            $0.url == folder || $0.url.deletingLastPathComponent() == folder
        }
        let descendants = repositories.filter {
            $0.url != folder && $0.url.deletingLastPathComponent() != folder
        }
        let childFolders = Set(descendants.compactMap { repository -> URL? in
            let relative = repository.url.path.dropFirst(folder.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let first = relative.split(separator: "/").first else { return nil }
            return folder.appendingPathComponent(String(first), isDirectory: true)
        }).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        for child in childFolders {
            appendFolder(
                child,
                root: root,
                repositories: descendants.filter { $0.url.path.hasPrefix(child.path + "/") || $0.url == child },
                depth: depth + 1,
                isRoot: false,
                into: &rows
            )
        }
        rows.append(contentsOf: direct.map { repositoryRow($0, depth: depth + 1) })
    }

    private func repositoryRow(_ repository: YourRepository, depth: Int = 0) -> YourRepositoriesNativeList.Row {
        let bookmark = bookmarkController.bookmarkID(linkedTo: repository.url) != nil
        return .init(
            id: "repo:\(repository.url.path)",
            depth: depth,
            content: .repository(repository, iconName(for: repository.url), bookmark)
        )
    }

    private func iconName(for url: URL) -> String {
        if let icon = repositoryIcons[url] { return icon }
        guard let bookmarkID = bookmarkController.bookmarkID(linkedTo: url),
              let bookmark = bookmarkController.bookmark(forID: bookmarkID) else { return "code-branch" }
        return bookmark.provider == .generic ? "code-branch" : bookmark.provider.rawValue
    }

    private func filterType(for url: URL) -> RepoPickerFilterType? {
        RepoPickerFilterType.allCases.first { $0.iconName == iconName(for: url) }
    }

    private func loadRepositoryIcons() async {
        // Attach discovery to the list data, so scrolling never restarts Git work.
        for repository in store.repositories {
            guard !Task.isCancelled else { return }
            guard repositoryIcons[repository.url] == nil else { continue }
            let origin = await GitStatusService.shared.remoteURL(remote: "origin", in: repository.url)
            var icon = determineRepoIconName(from: origin)
            if icon == "code-branch" {
                let remotes = await GitStatusService.shared.remoteURLs(in: repository.url)
                icon = remotes.map(determineRepoIconName(from:))
                    .first { $0 != "code-branch" } ?? "code-branch"
            }
            guard !Task.isCancelled else { return }
            if repositoryIcons[repository.url] != icon {
                repositoryIcons[repository.url] = icon
            }
        }
    }

    private func toggleFolder(_ url: URL) {
        if expandedFolders.contains(url) { expandedFolders.remove(url) }
        else { expandedFolders.insert(url) }
    }

    private func toggleStar(_ url: URL) {
        Task {
            if let id = bookmarkController.bookmarkID(linkedTo: url),
               let bookmark = bookmarkController.bookmark(forID: id) {
                await bookmarkController.removeBookmark(bookmark)
            } else {
                do { _ = try await bookmarkController.addBookmark(for: url) }
                catch { message = error.localizedDescription }
            }
        }
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Folders"
        panel.message = "Choose folders that contain your Git repositories."
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            switch store.addFolders(panel.urls) {
            case .added:
                expandedFolders.formUnion(panel.urls.map(\.standardizedFileURL))
            case .duplicate:
                message = "This folder has already been added."
            case .homeFolder:
                message = "Your home folder or the file system root cannot be added. Choose a more specific folder."
            }
        }
    }

    private func removeFolder(_ url: URL) {
        expandedFolders.remove(url)
        store.removeFolder(url)
    }
}
