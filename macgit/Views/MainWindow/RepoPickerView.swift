//
//  RepoPickerView.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

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
import SwiftUI

func determineRepoIconName(from remoteURLString: String) -> String {
    let lower = remoteURLString.lowercased()
    if lower.contains("github.com") || lower.contains("github") {
        return "github"
    } else if lower.contains("gitlab.com") || lower.contains("gitlab") {
        return "gitlab"
    } else if lower.contains("bitbucket.org") || lower.contains("bitbucket") {
        return "bitbucket"
    } else {
        return "code-branch"
    }
}

enum RepoPickerSortOption: String, CaseIterable, Identifiable {
    case lastOpened = "Last Opened"
    case name = "Name"

    var id: String { rawValue }
}

enum RepoPickerFilterType: String, CaseIterable, Identifiable {
    case github = "GitHub"
    case gitlab = "GitLab"
    case bitbucket = "Bitbucket"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .github: return "github"
        case .gitlab: return "gitlab"
        case .bitbucket: return "bitbucket"
        }
    }
}

enum RepoPickerTab: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case yours = "Your Repos"

    var id: Self { self }
}

struct RepoPickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTextScale) private var textScale
    @EnvironmentObject private var bookmarkController: RepositoryBookmarkController
    @ObservedObject private var store = RecentRepositoriesStore.shared
    @ObservedObject private var yourRepositoriesStore = YourRepositoriesStore.shared
    @ObservedObject private var catalog = RepositoryCatalogStore.shared
    @State private var showingCloneSheet = false
    @State private var showingFolderManager = false
    @State private var folderToRemove: URL?
    @State private var bookmarkToClone: RepositoryBookmark?
    @State private var bookmarkToRepair: RepositoryBookmark?
    @State private var bookmarkRepairFolder: URL?
    @State private var bookmarkRefreshGeneration = 0
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var searchText = ""
    @AppStorage("dev.thanhtran.macgit.repositoryPicker.sortOption") private var sortOption: RepoPickerSortOption = .lastOpened
    @State private var selectedFilterTypes: Set<RepoPickerFilterType> = []
    @AppStorage("dev.thanhtran.macgit.repositoryPicker.showBookmarkedOnly") private var showBookmarkedOnly = false
    @AppStorage("dev.thanhtran.macgit.repositoryPicker.selectedTab") private var selectedTab: RepoPickerTab = .recent
    @AppStorage("dev.thanhtran.macgit.repositoryPicker.listMode") private var repositoryListMode: RepositoryPickerListMode = .plain
    @AppStorage("dev.thanhtran.macgit.repositoryPicker.expandedPaths") private var expandedPathsStorage = ""
    @AppStorage("dev.thanhtran.macgit.repositoryPicker.providerFilters") private var providerFiltersStorage = ""
    @State private var expandedRepositoryFolders: Set<URL> = []
    @State private var repoIcons: [URL: String] = [:]
    @State private var loadingRepoIcons: Set<URL> = []
    @State private var rowStates: [URL: RepoPickerRowState] = [:]
    @State private var missingRepository: RecentRepository?
    @State private var showingMissingRepositoryAlert = false
    @State private var localPreview: URL?

    let title: String
    let showsApplicationIcon: Bool
    let isDashboardSidebar: Bool
    var showCloneSheetInitially: Bool
    var onRepositoryOpened: (URL) -> Void
    var onRepositoryViewed: ((URL) -> Void)?
    var selectedRepositoryURL: URL?

    init(
        title: String = "Choose a Repository",
        showsApplicationIcon: Bool = false,
        isDashboardSidebar: Bool = false,
        showCloneSheetInitially: Bool = false,
        onRepositoryViewed: ((URL) -> Void)? = nil,
        selectedRepositoryURL: URL? = nil,
        onRepositoryOpened: @escaping (URL) -> Void
    ) {
        self.title = title
        self.isDashboardSidebar = isDashboardSidebar
        self.showsApplicationIcon = showsApplicationIcon
        self.showCloneSheetInitially = showCloneSheetInitially
        self.onRepositoryOpened = onRepositoryOpened
        self.onRepositoryViewed = onRepositoryViewed
        self.selectedRepositoryURL = selectedRepositoryURL
    }

    private var visibleRepositories: [RecentRepository] {
        let recentURLs = Set(store.repositories.map(\.url.path))
        let bookmarkedLocalRepositories = bookmarkController.bookmarks.compactMap { bookmark -> RecentRepository? in
            guard let localURL = bookmarkController.localURL(for: bookmark),
                  !recentURLs.contains(localURL.path) else {
                return nil
            }
            var repository = RecentRepository(url: localURL, lastOpened: bookmark.updatedAt)
            repository.name = bookmark.name
            return repository
        }
        let scanned = yourRepositoriesStore.repositories.map { repository -> RecentRepository in
            let record = catalog.record(for: repository.url)
            return RecentRepository(url: repository.url, lastOpened: record?.lastOpened ?? .distantPast, id: record?.id ?? UUID())
        }
        let visible = Self.visibleRepositories(
            from: selectedTab == .recent ? store.repositories + bookmarkedLocalRepositories : scanned,
            searchText: searchText,
            sortOption: sortOption,
            selectedFilterTypes: selectedFilterTypes,
            repoIcons: resolvedIcons,
            rowStates: rowStates
        )
        guard showBookmarkedOnly else { return visible }
        return visible.filter { bookmarkID(for: $0.url) != nil }
    }

    private var resolvedIcons: [URL: String] {
        var icons = Dictionary(uniqueKeysWithValues: catalog.snapshot.repositories.map { (URL(fileURLWithPath: $0.path), $0.provider) })
        icons.merge(repoIcons) { _, new in new }
        return icons
    }

    private func bookmarkID(for url: URL) -> String? {
        if let id = bookmarkController.bookmarkID(linkedTo: url) { return id }
        if let key = catalog.record(for: url)?.bookmarkKey {
            return bookmarkController.bookmarks.first { $0.canonicalKey == key }?.id
        }
        return nil
    }

    private var visibleUnlinkedBookmarks: [RepositoryBookmark] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bookmarkController.bookmarks
            .filter { bookmarkController.localURL(for: $0) == nil }
            .filter { bookmark in
                guard query.isEmpty == false else { return true }
                return [
                    bookmark.name,
                    bookmark.ownerPath,
                    bookmark.host,
                    bookmark.remoteURL.absoluteString
                ]
                    .joined(separator: " ")
                    .lowercased()
                    .contains(query)
            }
            .filter { bookmark in
                guard !selectedFilterTypes.isEmpty else { return true }
                let filterType: RepoPickerFilterType?
                switch bookmark.provider {
                case .github:
                    filterType = .github
                case .gitlab:
                    filterType = .gitlab
                case .bitbucket:
                    filterType = .bitbucket
                case .generic:
                    filterType = nil
                }
                return filterType.map(selectedFilterTypes.contains) ?? false
            }
            .sorted {
                switch sortOption {
                case .lastOpened:
                    $0.updatedAt > $1.updatedAt
                case .name:
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
    }

    var body: some View {
        pickerLayout
        .task(id: showCloneSheetInitially) {
            if showCloneSheetInitially {
                showingCloneSheet = true
            }
        }
        .task(id: [store.repositories.map(\.url.path), bookmarkController.bookmarks.map(\.canonicalKey), [String(bookmarkRefreshGeneration)]]) {
            let localURLs = store.repositories.map(\.url)
                + bookmarkController.bookmarks.compactMap { bookmarkController.localURL(for: $0) }
            await bookmarkController.linkMatchingBookmarks(to: localURLs)
        }
        .task(id: [store.repositories.map(\.url.path), bookmarkController.bookmarks.compactMap {
            bookmarkController.localURL(for: $0)?.path
        }, yourRepositoriesStore.repositories.map(\.url.path), [String(bookmarkRefreshGeneration)]]) {
            await refreshRecentRepositoryPresentations()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            bookmarkRefreshGeneration += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh)) { _ in bookmarkRefreshGeneration += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { _ in bookmarkRefreshGeneration += 1 }
        .task { restorePickerSettings() }
        .onChange(of: expandedRepositoryFolders) { _, folders in persistExpandedFolders(folders) }
        .onChange(of: selectedFilterTypes) { _, filters in persistProviderFilters(filters) }
        .onChange(of: expandedPathsStorage) { _, _ in restorePickerSettings(force: true) }
        .onChange(of: providerFiltersStorage) { _, _ in restorePickerSettings(force: true) }
        .task(id: yourRepositoriesStore.folders.map(\.path)) { await yourRepositoriesStore.scan() }
        .task(id: bookmarkRefreshGeneration) {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            await yourRepositoriesStore.scan()
        }
        .onChange(of: catalog.errorMessage) { _, error in
            if let error { errorMessage = error; showingError = true }
        }
        .replacingSheet(isPresented: Binding(get: { localPreview != nil }, set: { if !$0 { localPreview = nil } })) {
            if let localPreview {
                RepositoryDetailView(repositoryURL: localPreview, onClose: { self.localPreview = nil }, onOpen: onRepositoryOpened)
                    .frame(minWidth: 700, minHeight: 600)
            }
        }
    }

    private var pickerLayout: some View {
        VStack(spacing: 18) {
            pickerHeader
            repositoryTabs
            controlBar
            repositoryContent
            if !isDashboardSidebar { Spacer(minLength: 0) }
        }
        .frame(minWidth: isDashboardSidebar ? 300 : 500, maxWidth: isDashboardSidebar ? .infinity : 700, minHeight: isDashboardSidebar ? 0 : 520, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(isDashboardSidebar ? 18 : 24)
        .background(isDashboardSidebar && colorScheme == .light ? Color(red: 0.97, green: 0.98, blue: 0.99) : Color.clear)
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .alert("Repository Moved or Deleted", isPresented: $showingMissingRepositoryAlert, presenting: missingRepository, actions: { repo in
            Button("Remove", role: .destructive) {
                if let bookmarkID = bookmarkController.bookmarkID(linkedTo: repo.url),
                   let bookmark = bookmarkController.bookmark(forID: bookmarkID) {
                    Task { await bookmarkController.unlinkLocalFolder(for: bookmark) }
                }
                store.remove(repo)
                missingRepository = nil
            }

            Button("Change folder") {
                chooseReplacementFolder(for: repo)
            }

            Button("Cancel", role: .cancel) {
                missingRepository = nil
            }
        }, message: { repo in
            Text("\"\(repo.name)\" is no longer available at \(repo.url.path).")
        })
        .replacingSheet(isPresented: $showingCloneSheet) {
            CloneSheetView(onClone: { url in
                showingCloneSheet = false
                store.add(url)
                onRepositoryOpened(url)
            })
        }
        .replacingSheet(item: $bookmarkToClone) { bookmark in
            CloneSheetView(
                initialRemoteURL: bookmark.remoteURL.absoluteString,
                initialRepositoryName: bookmark.name,
                onClone: { url in
                    bookmarkToClone = nil
                    linkBookmark(bookmark, to: url)
                    store.add(url)
                    onRepositoryOpened(url)
                }
            )
        }
        .replacingSheet(item: $bookmarkToRepair) { bookmark in
            RepositoryBookmarkRepairSheet(bookmark: bookmark, initialRepositoryURL: bookmarkRepairFolder) { url in
                store.add(url)
                bookmarkRefreshGeneration += 1
            }
        }
        .onChange(of: bookmarkController.errorMessage) { _, newValue in
            guard let newValue else { return }
            errorMessage = "Could not save or sync the repository bookmark. \(newValue)"
            showingError = true
            bookmarkController.clearError()
        }
    }

    @ViewBuilder
    private var pickerHeader: some View {
        if isDashboardSidebar { dashboardActions }
        else { headerSection }
    }

    @ViewBuilder
    private var repositoryContent: some View {
        if selectedTab == .recent {
            if bookmarkController.hasPendingChanges { bookmarkSyncStatus }
        }
        repositoryListSection
    }

    private var bookmarkSyncStatus: some View {
        HStack {
            Text(bookmarkController.canSyncPendingChanges
                 ? "Bookmark changes are saved locally and waiting to sync."
                 : "Bookmark changes are saved locally. Sign in to sync them.")
                .font(.caption.scaled(by: textScale))
                .foregroundStyle(.secondary)
            Spacer()
            if bookmarkController.canSyncPendingChanges {
                Button("Retry Sync") {
                    Task { await bookmarkController.retryPendingChanges() }
                }
                .disabled(bookmarkController.isRetryingSync || !bookmarkController.syncingBookmarkIDs.isEmpty)
            }
        }
    }

    private var repositoryTabs: some View {
        Picker("Repository source", selection: $selectedTab) {
            ForEach(RepoPickerTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: isDashboardSidebar ? .infinity : 360)
    }

    private var folderManagementButtons: some View {
        HStack {
            Button("Add Folder", systemImage: "plus", action: chooseRepositoryFolders)
                .buttonStyle(.bordered).sidebarPointingHandCursor()
            Button("Manage Folders") { showingFolderManager = true }
                .buttonStyle(.bordered).sidebarPointingHandCursor()
        }.fixedSize()
    }

    private var folderScanStatus: some View {
        HStack {
            if yourRepositoriesStore.isScanning { ProgressView().controlSize(.small) }
            else { Text("\(yourRepositoriesStore.repositories.count) repositories").font(.caption).foregroundStyle(.secondary) }
            Button("Rescan", systemImage: "arrow.clockwise") { Task { await yourRepositoriesStore.scan(force: true) } }
                .labelStyle(.iconOnly).disabled(yourRepositoriesStore.isScanning)
        }.fixedSize()
    }

    private var repositoryListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Repositories")
                .font(.headline.scaled(by: textScale))
            sharedRepositoriesContent
            if selectedTab == .yours {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        folderManagementButtons
                        Spacer(minLength: 12)
                        folderScanStatus
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        folderManagementButtons
                        HStack { Spacer(); folderScanStatus }
                    }
                }
                ForEach(catalog.snapshot.roots.filter { $0.error != nil }) { root in
                    Text("\(root.path): \(root.error ?? "")").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .padding(18)
        .sheet(isPresented: $showingFolderManager) {
            RepositoryFoldersSheet(store: yourRepositoriesStore)
        }
        .alert("Remove Folder?", isPresented: Binding(get: { folderToRemove != nil }, set: { if !$0 { folderToRemove = nil } }), presenting: folderToRemove) { folder in
            Button("Remove Folder", role: .destructive) {
                yourRepositoriesStore.removeFolder(folder)
                folderToRemove = nil
            }
            Button("Cancel", role: .cancel) { folderToRemove = nil }
        } message: { folder in
            Text("Remove \(folder.path) from the scan list? The folder and its files will remain on your Mac.")
        }
        .frame(maxWidth: .infinity, maxHeight: isDashboardSidebar ? .infinity : 320, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if isDashboardSidebar && colorScheme == .light {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.14))
            }
        }
    }

    private func chooseRepositoryFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Folders"
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            switch yourRepositoriesStore.addFolders(panel.urls) {
            case .added:
                expandedRepositoryFolders.formUnion(panel.urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() })
            case .duplicate:
                errorMessage = "This folder has already been added."; showingError = true
            case .homeFolder:
                errorMessage = "Choose a more specific folder. Home and the file system root cannot be added."; showingError = true
            }
        }
    }

    private func expandAllRepositoryFolders() {
        var folders = Set(yourRepositoriesStore.folders)
        for row in RecentRepositoryTree.rows(repositories: visibleRepositories, expandedFolders: [], expandAll: true, roots: selectedTab == .yours ? yourRepositoriesStore.folders : []) {
            if case .folder(let folder, _) = row.content { folders.insert(folder) }
        }
        for repository in yourRepositoriesStore.repositories {
            var folder = repository.url.deletingLastPathComponent()
            while folder.path.count >= repository.rootURL.path.count {
                folders.insert(folder)
                guard folder != repository.rootURL else { break }
                folder.deleteLastPathComponent()
            }
        }
        expandedRepositoryFolders = folders
    }

    private func collapseAllRepositoryFolders() {
        expandedRepositoryFolders.removeAll()
    }

    private func refreshRecentRepositoryPresentations() async {
        let urls = store.repositories.map(\.url)
            + bookmarkController.bookmarks.compactMap { bookmarkController.localURL(for: $0) }
            + yourRepositoriesStore.repositories.map(\.url)
        var loadedURLs: Set<URL> = []
        for url in urls where loadedURLs.insert(url).inserted {
            guard !Task.isCancelled else { return }
            let repository = RecentRepository(url: url, lastOpened: .now)
            await loadRepositoryIcon(for: repository)
            guard !Task.isCancelled else { return }
            await loadRowPresentation(for: repository)
        }
    }

    private func restorePickerSettings(force: Bool = false) {
        if (force || expandedRepositoryFolders.isEmpty),
           let data = Data(base64Encoded: expandedPathsStorage),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            expandedRepositoryFolders = Set(paths.map { URL(fileURLWithPath: $0, isDirectory: true) })
        }
        if force || selectedFilterTypes.isEmpty {
            selectedFilterTypes = Set(providerFiltersStorage.split(separator: ",").compactMap {
                RepoPickerFilterType(rawValue: String($0))
            })
        }
    }

    private func persistExpandedFolders(_ folders: Set<URL>) {
        guard let data = try? JSONEncoder().encode(folders.map(\.path).sorted()) else { return }
        expandedPathsStorage = data.base64EncodedString()
    }

    private func persistProviderFilters(_ filters: Set<RepoPickerFilterType>) {
        providerFiltersStorage = filters.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func linkBookmark(_ bookmark: RepositoryBookmark, to url: URL) {
        Task {
            do { try await bookmarkController.link(bookmark, to: url) }
            catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    static func visibleRepositories(
        from repositories: [RecentRepository],
        searchText: String,
        sortOption: RepoPickerSortOption,
        selectedFilterTypes: Set<RepoPickerFilterType>,
        repoIcons: [URL: String],
        rowStates: [URL: RepoPickerRowState]
    ) -> [RecentRepository] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seenURLs: Set<String> = []
        let filtered = repositories.filter { repo in
            guard seenURLs.insert(repo.url.standardizedFileURL.path).inserted else { return false }
            if !query.isEmpty {
                let haystack = [
                    repo.name,
                    repo.url.path,
                    rowStates[repo.url]?.currentBranch ?? ""
                ]
                    .joined(separator: " ")
                    .lowercased()

                guard haystack.contains(query) else { return false }
            }

            if !selectedFilterTypes.isEmpty {
                let iconName = repoIcons[repo.url] ?? "code-branch"
                let type = RepoPickerFilterType.allCases.first { $0.iconName == iconName }
                guard let type = type, selectedFilterTypes.contains(type) else { return false }
            }

            return true
        }

        switch sortOption {
        case .lastOpened:
            return filtered.sorted { $0.lastOpened > $1.lastOpened }
        case .name:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var dashboardActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Group {
                    Image("commitplus-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                }
                Text("Commit+")
                    .font(.title2.bold().scaled(by: textScale))
                    .foregroundStyle(.blue)
            }
            .padding(.bottom, 8)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    dashboardActionButtons
                }
                VStack(spacing: 6) {
                    dashboardActionButtons
                }
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var dashboardActionButtons: some View {
        Button(action: openExistingRepository) {
            Label("Open", systemImage: "folder")
                .font(.body.scaled(by: textScale))
                .fixedSize()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .sidebarPointingHandCursor()
        .help("Open Repository")
        Button { showingCloneSheet = true } label: {
            Label("Clone", systemImage: "arrow.down.circle")
                .font(.body.scaled(by: textScale))
                .fixedSize()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .sidebarPointingHandCursor()
        .help("Clone Repository")
        Button(action: createRepository) {
            Label("Create Repository", systemImage: "plus.rectangle.on.folder")
                .font(.body.scaled(by: textScale))
                .fixedSize()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .sidebarPointingHandCursor()
    }

    private func createRepository() {
        let panel = NSSavePanel()
        panel.title = "Create Repository"
        panel.message = "Choose a name and location for a new Git repository."
        panel.nameFieldStringValue = "Untitled Repository"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let url = panel.url else { return }
            Task {
                do {
                    try await GitStatusService.shared.createEmptyRepository(at: url)
                    store.add(url)
                    onRepositoryOpened(url)
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                if showsApplicationIcon {
                    Image("commitplus-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.scaled(by: textScale))
                        .fontWeight(.semibold)
                    Text("Open an existing repository or clone a new one")
                        .font(.title3.scaled(by: textScale))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                Button(action: openExistingRepository) {
                    Label("Open Repository", systemImage: "folder")
                        .font(.headline.scaled(by: textScale))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .sidebarPointingHandCursor()
                .controlSize(.large)
                .frame(width: 200)

                Button(action: { showingCloneSheet = true }) {
                    Label("Clone Repository", systemImage: "arrow.down.circle")
                        .font(.headline.scaled(by: textScale))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .sidebarPointingHandCursor()
                .controlSize(.large)
                .frame(width: 200)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            TextField("Filter repositories", text: $searchText)
                .font(.body.scaled(by: textScale))
                .textFieldStyle(.roundedBorder)
                .disabled(selectedTab == .recent
                    ? store.repositories.isEmpty && bookmarkController.bookmarks.isEmpty
                    : yourRepositoriesStore.repositories.isEmpty)

            Button {
                showBookmarkedOnly.toggle()
            } label: {
                Image(systemName: showBookmarkedOnly ? "star.fill" : "star")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .sidebarPointingHandCursor()
            .help(showBookmarkedOnly ? "Show all repositories" : "Show bookmarked repositories only")
            .accessibilityLabel(showBookmarkedOnly ? "Show all repositories" : "Show bookmarked repositories only")

            Menu {
                Section("Sort") {
                    Picker("", selection: $sortOption) {
                        ForEach(RepoPickerSortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Filter by Type") {
                    ForEach(RepoPickerFilterType.allCases) { type in
                        Toggle(isOn: Binding(
                            get: { selectedFilterTypes.contains(type) },
                            set: { isOn in
                                if isOn {
                                    selectedFilterTypes.insert(type)
                                } else {
                                    selectedFilterTypes.remove(type)
                                }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(nsImage: menuIconImage(for: type.iconName))
                                Text(type.rawValue)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .sidebarPointingHandCursor()
            .disabled(selectedTab == .recent
                ? store.repositories.isEmpty && bookmarkController.bookmarks.isEmpty
                : yourRepositoriesStore.repositories.isEmpty)

            if repositoryListMode == .tree {
                Button("Expand All", systemImage: "chevron.down.2", action: expandAllRepositoryFolders)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .sidebarPointingHandCursor()
                    .help("Expand all folders")
                Button("Collapse All", systemImage: "chevron.up.2", action: collapseAllRepositoryFolders)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .sidebarPointingHandCursor()
                    .help("Collapse all folders")
            }

            Button {
                repositoryListMode = repositoryListMode == .plain ? .tree : .plain
            } label: {
                Image(systemName: repositoryListMode.icon)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .sidebarPointingHandCursor()
            .help(repositoryListMode == .plain ? "Show as tree" : "Show as plain list")
            .accessibilityLabel(repositoryListMode == .plain ? "Show as tree" : "Show as plain list")
        }
    }

    @ViewBuilder
    private var sharedRepositoriesContent: some View {
        let items = repositoryListItems
        if !catalog.isReady {
            ProgressView("Loading repositories…").frame(maxWidth: .infinity, minHeight: 180)
        } else if selectedTab == .yours && yourRepositoriesStore.folders.isEmpty {
            ContentUnavailableView("No Repository Folders", systemImage: "folder.badge.plus", description: Text("Add folders to discover your Git repositories."))
                .frame(minHeight: 180)
        } else if items.isEmpty {
            ContentUnavailableView(
                showBookmarkedOnly ? "No Bookmarked Repositories" : "No Repositories Found",
                systemImage: showBookmarkedOnly ? "star" : "clock.arrow.circlepath",
                description: Text("Open a repository, add a folder, or clear the filters.")
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
        } else {
            RepositoryPickerNativeList(rows: items, textScale: textScale, dark: colorScheme == .dark) { item in
                repositoryListContent(item)
                    .environmentObject(bookmarkController)
                    .environment(\.appTextScale, textScale)
                    .environment(\.colorScheme, colorScheme)
            }
            .frame(minHeight: 180, maxHeight: isDashboardSidebar ? .infinity : 320)
        }
    }

    private var repositoryListItems: [RepositoryPickerListItem] {
        let repositories = visibleRepositories
        let icons = resolvedIcons
        func item(_ repository: RecentRepository, depth: Int) -> RepositoryPickerListItem {
            let id = bookmarkID(for: repository.url)
            return .init(id: "repo:\(repository.url.path)", depth: depth, repository: repository,
                         state: rowStates[repository.url], icon: icons[repository.url] ?? "code-branch",
                         starred: id != nil, syncing: id.map(bookmarkController.syncingBookmarkIDs.contains) ?? false,
                         selected: selectedRepositoryURL == repository.url,
                         warnings: bookmarkController.bookmarksNeedingAttention(at: repository.url))
        }
        var result: [RepositoryPickerListItem] = selectedTab == .recent ? visibleUnlinkedBookmarks.map {
            .init(id: "bookmark:\($0.id)", bookmark: $0)
        } : []
        if repositoryListMode == .plain {
            result += repositories.map { item($0, depth: 0) }
        } else {
            let tree = RecentRepositoryTree.rows(repositories: repositories, expandedFolders: expandedRepositoryFolders,
                                                roots: selectedTab == .yours ? yourRepositoriesStore.folders : [])
            result += tree.map { row in
                switch row.content {
                case .folder(let folder, let count):
                    return .init(id: row.id, depth: row.depth, folder: folder, count: count, expanded: expandedRepositoryFolders.contains(folder))
                case .repository(let repository): return item(repository, depth: row.depth)
                }
            }
        }
        return result
    }

    @ViewBuilder
    private func repositoryListContent(_ item: RepositoryPickerListItem) -> some View {
        VStack(spacing: 0) {
            if let folder = item.folder {
                recentFolderRow(folder, count: item.count)
                    .contextMenu {
                        if yourRepositoriesStore.folders.contains(folder) {
                            Button("Remove Folder") { folderToRemove = folder }
                        }
                    }
            } else if let repository = item.repository {
                repoRow(repository, iconName: item.icon)
                    .background(item.selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                Divider().padding(.leading, 46)
            } else if let bookmark = item.bookmark {
                unlinkedBookmarkRow(bookmark)
                Divider().padding(.leading, 46)
            }
        }.padding(.leading, CGFloat(item.depth) * 16)
    }

    private func recentFolderRow(_ folder: URL, count: Int) -> some View {
        Button {
            if expandedRepositoryFolders.contains(folder) { expandedRepositoryFolders.remove(folder) }
            else { expandedRepositoryFolders.insert(folder) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: expandedRepositoryFolders.contains(folder) ? "chevron.down" : "chevron.right")
                    .frame(width: 12)
                Image(systemName: "folder.fill").foregroundStyle(.blue)
                Text(folder.lastPathComponent).lineLimit(1)
                Text("\(count)").foregroundStyle(.secondary)
                Spacer()
            }
            .font(.body.weight(.medium).scaled(by: textScale))
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(folder.path)
    }

    private func repoRow(_ repo: RecentRepository, iconName: String = "code-branch") -> some View {
        RepoPickerHoverRow {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button(action: {
                        openRecentRepository(repo)
                    }) {
                        repoRowContent(repo, iconName: iconName)
                    }
                    .buttonStyle(.plain)
                    .sidebarPointingHandCursor()

                    VStack(alignment: .trailing, spacing: 5) {
                        HStack(spacing: 12) {
                            Button("View", systemImage: "eye") {
                                if let onRepositoryViewed { onRepositoryViewed(repo.url) }
                                else { localPreview = repo.url }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("View repository details")
                            .sidebarPointingHandCursor()
                            bookmarkButton(for: repo)
                        }
                        Text(repo.lastOpened == .distantPast ? "Not opened" : timeAgoString(from: repo.lastOpened))
                            .font(.caption.scaled(by: textScale))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .help(repo.lastOpened == .distantPast ? "Not opened" : repo.lastOpened.formatted())
                    }
                    .padding(.trailing, 4)
                }
                ForEach(bookmarkController.bookmarksNeedingAttention(at: repo.url)) { bookmark in
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Bookmark URL no longer matches this folder's remotes.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(bookmark.remoteURL.absoluteString)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(bookmark.remoteURL.absoluteString)
                        HStack {
                            Button("Update Bookmark…") { repairBookmark(bookmark, folder: repo.url) }
                            Button("Remove Bookmark") {
                                Task { await bookmarkController.removeBookmark(bookmark) }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.caption.scaled(by: textScale))
                    .padding(.leading, 46)
                    .padding(.bottom, 8)
                }
            }
        }
        .contextMenu {
            ForEach(bookmarkController.bookmarks.filter { bookmarkController.localURL(for: $0) == repo.url }) { bookmark in
                Button("Update Bookmark: \(bookmark.name)…") { repairBookmark(bookmark, folder: repo.url) }
            }
            Button("Remove from Recents", role: .destructive) {
                store.remove(repo)
            }
        }
    }

    @ViewBuilder
    private func bookmarkButton(for repo: RecentRepository) -> some View {
        let bookmarkID = bookmarkID(for: repo.url)
        Button {
            Task {
                if let bookmarkID,
                   let bookmark = bookmarkController.bookmark(forID: bookmarkID) {
                    await bookmarkController.removeBookmark(bookmark)
                } else {
                    do {
                        _ = try await bookmarkController.addBookmark(for: repo.url)
                    } catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        } label: {
            Group {
                if let bookmarkID,
                   bookmarkController.syncingBookmarkIDs.contains(bookmarkID) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: bookmarkID == nil ? "star" : "star.fill")
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .sidebarPointingHandCursor()
        .help(bookmarkID == nil ? "Bookmark repository" : "Remove bookmark")
        .accessibilityLabel(bookmarkID == nil ? "Bookmark repository" : "Remove bookmark")
    }

    private func unlinkedBookmarkRow(_ bookmark: RepositoryBookmark) -> some View {
        RepoPickerHoverRow {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    RepositoryProviderIcon(name: bookmark.provider == .generic ? "code-branch" : bookmark.provider.rawValue)
                        .frame(width: 18, height: 18)
                        .frame(width: 34, height: 34)
                        .background(
                            Color(nsColor: .windowBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .accessibilityLabel("Repository provider")

                    VStack(alignment: .leading, spacing: 3) {
                        Text(bookmark.name)
                            .font(.body.weight(.medium).scaled(by: textScale))
                        Text(bookmark.remoteURL.absoluteString)
                            .font(.caption.scaled(by: textScale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Clone") {
                        bookmarkToClone = bookmark
                    }
                    .buttonStyle(.borderedProminent)
                    .sidebarPointingHandCursor()

                    Button(isDashboardSidebar ? "Link" : "Link Folder") {
                        chooseFolderToLink(bookmark)
                    }
                    .buttonStyle(.bordered)
                    .sidebarPointingHandCursor()

                    Button("Remove bookmark", systemImage: "star.fill") {
                        Task {
                            await bookmarkController.removeBookmark(bookmark)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .sidebarPointingHandCursor()
                    .help("Remove bookmark")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("Not linked on this Mac. Renamed or moved?", systemImage: "link")
                        .foregroundStyle(.secondary)
                    Button("Update Bookmark…") { repairBookmark(bookmark) }
                        .buttonStyle(.borderless)
                        .sidebarPointingHandCursor()
                }
                .font(.caption.scaled(by: textScale))
                .padding(.leading, 46)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
        }
    }

    private func openRecentRepository(_ repo: RecentRepository) {
        guard isValidGitRepository(at: repo.url) else {
            repoIcons[repo.url] = "code-branch"
            loadingRepoIcons.remove(repo.url)
            rowStates[repo.url] = RepoPickerRowState(
                currentBranch: nil,
                changedFileCount: nil,
                behindCount: nil,
                aheadCount: nil,
                isMissing: true,
                isLoading: false
            )
            missingRepository = repo
            showingMissingRepositoryAlert = true
            return
        }

        store.add(repo.url)
        onRepositoryOpened(repo.url)
    }

    private func repoRowContent(_ repo: RecentRepository, iconName: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if loadingRepoIcons.contains(repo.url) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    RepositoryProviderIcon(name: iconName)
                        .frame(width: 18, height: 18)
                }
            }
                .frame(width: 34, height: 34)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(loadingRepoIcons.contains(repo.url) ? "Detecting repository provider" : "Repository provider")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.body.weight(.medium).scaled(by: textScale))
                        .lineLimit(1)
                        .layoutPriority(1)

                    rowStatusView(for: repo)

                    Spacer(minLength: 0)
                }

                Text(repo.url.path)
                    .font(.caption.scaled(by: textScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowStatusView(for repo: RecentRepository) -> some View {
        let rowState = rowStates[repo.url]

        if rowState?.isMissing == true {
            Text("Repository moved or deleted")
                .font(.caption.weight(.semibold).scaled(by: textScale))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange, in: Capsule())
                .help("Repository moved or deleted")
        } else if let rowState {
            HStack(spacing: 6) {
                if let branch = rowState.currentBranch, !branch.isEmpty {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption.weight(.medium).scaled(by: textScale))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .frame(maxWidth: isDashboardSidebar ? 104 : 160)
                        .help(branch)
                }

                if let changedFileCount = rowState.changedFileCount {
                    RepoPickerCountBadge(icon: "pencil", label: "Changed files", count: changedFileCount, tint: .yellow)
                }
                if let behindCount = rowState.behindCount {
                    RepoPickerCountBadge(icon: "arrow.down.to.line", label: "Behind", count: behindCount, tint: .purple)
                }
                if let aheadCount = rowState.aheadCount {
                    RepoPickerCountBadge(icon: "arrow.up.to.line", label: "Ahead", count: aheadCount, tint: .green)
                }
                if rowState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @MainActor
    private func loadRowPresentation(for repo: RecentRepository) async {
        guard !Task.isCancelled else { return }
        if rowStates[repo.url] == nil {
            rowStates[repo.url] = RepoPickerRowState(
                currentBranch: nil,
                isMissing: false,
                isLoading: true
            )
        }

        let repoPath = repo.url.path
        let gitMetadataPath = repo.url.appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: repoPath),
              FileManager.default.fileExists(atPath: gitMetadataPath) else {
            let state = RepoPickerRowState(
                currentBranch: nil,
                isMissing: true,
                isLoading: false
            )
            if rowStates[repo.url] != state {
                rowStates[repo.url] = state
            }
            return
        }

        let snapshot = await GitStatusService.shared.repoPickerStatus(in: repo.url)

        guard !Task.isCancelled else { return }

        let state = RepoPickerRowState(
            currentBranch: snapshot.currentBranch,
            changedFileCount: snapshot.changedFileCount,
            behindCount: snapshot.behindCount,
            aheadCount: snapshot.aheadCount,
            isMissing: false,
            isLoading: false
        )
        if rowStates[repo.url] != state {
            rowStates[repo.url] = state
        }
    }

    @MainActor
    private func loadRepositoryIcon(for repo: RecentRepository) async {
        guard !Task.isCancelled else { return }
        defer {
            if loadingRepoIcons.contains(repo.url) {
                loadingRepoIcons.remove(repo.url)
            }
        }
        if resolvedIcons[repo.url] == nil {
            loadingRepoIcons.insert(repo.url)
        }

        let repoPath = repo.url.path
        let gitMetadataPath = repo.url.appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: repoPath),
              FileManager.default.fileExists(atPath: gitMetadataPath) else {
            if repoIcons[repo.url] != "code-branch" {
                repoIcons[repo.url] = "code-branch"
            }
            return
        }

        let remoteURL = await GitStatusService.shared.remoteURL(remote: "origin", in: repo.url)
        guard !Task.isCancelled else { return }

        var icon = determineRepoIconName(from: remoteURL)
        var identity = RepositoryBookmarkIdentity.resolve(remoteURLString: remoteURL)
        if icon == "code-branch" {
            let urls = await GitStatusService.shared.remoteURLs(in: repo.url)
            if let recognized = urls.first(where: { determineRepoIconName(from: $0) != "code-branch" }) {
                icon = determineRepoIconName(from: recognized)
                identity = RepositoryBookmarkIdentity.resolve(remoteURLString: recognized)
            }
        }
        guard !Task.isCancelled else { return }
        catalog.setProvider(icon, bookmarkKey: identity?.canonicalKey, for: repo.url)
        if repoIcons[repo.url] != icon {
            repoIcons[repo.url] = icon
        }
    }

    private func chooseReplacementFolder(for repo: RecentRepository) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select the new location for \(repo.name)"
            panel.prompt = "Change Folder"

            panel.beginSheetModal(for: NSApp.keyWindow!) { result in
                missingRepository = nil

                guard result == .OK, let url = panel.url else {
                    return
                }

                guard isValidGitRepository(at: url) else {
                    errorMessage = "The selected folder does not contain a .git directory."
                    showingError = true
                    return
                }

                if let bookmarkID = bookmarkController.bookmarkID(linkedTo: repo.url),
                   let bookmark = bookmarkController.bookmark(forID: bookmarkID) {
                    Task {
                        do {
                            try await bookmarkController.validateAndLink(bookmark, to: url)
                            catalog.relink(repo.url, to: url)
                            onRepositoryOpened(url)
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                } else {
                    catalog.relink(repo.url, to: url)
                    onRepositoryOpened(url)
                }
            }
        }
    }

    private func chooseFolderToLink(_ bookmark: RepositoryBookmark) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the local folder for \(bookmark.name)"
        panel.prompt = "Link Folder"

        guard let window = NSApp.keyWindow else {
            return
        }
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let url = panel.url else {
                return
            }
            guard isValidGitRepository(at: url) else {
                errorMessage = "The selected folder does not contain a .git directory."
                showingError = true
                return
            }

            Task {
                do {
                    try await bookmarkController.validateAndLink(bookmark, to: url)
                    store.add(url)
                    onRepositoryOpened(url)
                } catch RepositoryBookmarkError.folderDoesNotMatch {
                    repairBookmark(bookmark, folder: url)
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func repairBookmark(_ bookmark: RepositoryBookmark, folder: URL? = nil) {
        bookmarkRepairFolder = folder
        bookmarkToRepair = bookmark
    }

    private func isValidGitRepository(at url: URL) -> Bool {
        let gitPath = url.appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: url.path)
            && FileManager.default.fileExists(atPath: gitPath)
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        let minute: TimeInterval = 60
        let hour: TimeInterval = 60 * minute
        let day: TimeInterval = 24 * hour

        if interval < 1 {
            return "just now"
        } else if interval < minute {
            return "\(Int(interval))s ago"
        } else if interval < hour {
            let minutes = Int(interval / minute)
            return "\(minutes)m ago"
        } else if interval < day {
            let hours = Int(interval / hour)
            return "\(hours)h ago"
        } else if interval < 7 * day {
            return "\(Int(interval / day))d ago"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func menuIconImage(for iconName: String) -> NSImage {
        guard let original = NSImage(named: NSImage.Name(iconName)) else {
            return NSImage()
        }
        let size = NSSize(width: 14, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            original.draw(in: rect, from: NSRect(origin: .zero, size: original.size), operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    private func openExistingRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Git repository folder"
        panel.prompt = "Open"

        panel.beginSheetModal(for: NSApp.keyWindow!) { result in
            if result == .OK, let url = panel.url {
                if isValidGitRepository(at: url) {
                    store.add(url)
                    onRepositoryOpened(url)
                } else {
                    errorMessage = "The selected folder does not contain a .git directory."
                    showingError = true
                }
            }
        }
    }
}

private struct RepoPickerCountBadge: View {
    @Environment(\.appTextScale) private var textScale
    let icon: String
    let label: String
    let count: Int
    let tint: Color

    var body: some View {
        Group {
            if count > 0 {
                Label(String(count), systemImage: icon)
                    .font(.system(size: 10, weight: .semibold).scaled(by: textScale))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.2), in: Capsule())
                    .help("\(label): \(count)")
                    .accessibilityLabel("\(label): \(count)")
                    .fixedSize()
            }
        }
    }
}

struct CloneSheetView: View {
    @Environment(\.gitLFSCredentialResolver) private var lfsCredentialResolver
    @Environment(\.dismiss) private var dismiss
    @State private var discoveredAccountID: String?
    @State private var remoteURL: String
    @State private var destinationPath = ""
    @State private var repositoryName: String
    @State private var repositoryNameWasEdited = false
    @State private var checkoutBranch = ""
    @State private var remoteBranches: [String] = []
    @State private var isLoadingRemoteBranches = false
    @State private var remoteBranchLoadError: String?
    @State private var recurseSubmodules = false
    @State private var downloadLFSContent = true
    @State private var clonedRepository: URL?
    @State private var lfsRuntime = GitLFSRuntimeController.shared
    @State private var advancedOptionsExpanded = false
    @State private var showingDestinationPicker = false
    @State private var isCloning = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var repoIconName: String = "code-branch"

    private static let labelWidth: CGFloat = 120
    private static let controlHeight: CGFloat = 30
    private static let trailingControlWidth: CGFloat = 52

    var onClone: (URL) -> Void

    init(
        initialRemoteURL: String = "",
        initialRepositoryName: String = "",
        onClone: @escaping (URL) -> Void
    ) {
        _remoteURL = State(initialValue: initialRemoteURL)
        _repositoryName = State(
            initialValue: initialRepositoryName.isEmpty
                ? Self.defaultRepositoryName(from: initialRemoteURL)
                : initialRepositoryName
        )
        self.onClone = onClone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Clone a repository")
                .font(.largeTitle)
                .bold()

            if let resolver = lfsCredentialResolver {
                GitProviderRepositoryBrowser(resolver: resolver) { url, accountID in
                    discoveredAccountID = accountID
                    remoteURL = url
                }
                    .disabled(isCloning)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Source URL:")
                        .frame(width: Self.labelWidth, alignment: .trailing)

                    TextField("https://github.com/user/repo.git", text: remoteURLBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: Self.controlHeight)

                    Image(repoIconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .frame(width: Self.trailingControlWidth, height: Self.controlHeight)
                        .accessibilityLabel("Repository provider")
                }
                .onChange(of: remoteURL) { _, newValue in
                    repoIconName = determineRepoIconName(from: newValue)
                    guard !repositoryNameWasEdited else { return }
                    repositoryName = Self.defaultRepositoryName(from: newValue)
                }

                HStack(alignment: .center, spacing: 12) {
                    Text("Destination Path:")
                        .frame(width: Self.labelWidth, alignment: .trailing)

                    TextField("/Users/you/Project", text: $destinationPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: Self.controlHeight)

                    Button("Choose destination folder", systemImage: "ellipsis") {
                        showingDestinationPicker = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(width: Self.trailingControlWidth, height: Self.controlHeight)
                    .help("Choose destination folder")
                    .disabled(isCloning)
                }

                HStack(alignment: .center, spacing: 12) {
                    Text("Name:")
                        .frame(width: Self.labelWidth, alignment: .trailing)

                    TextField("repository-name", text: repositoryNameBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: Self.controlHeight)

                    Color.clear
                        .frame(width: Self.trailingControlWidth, height: Self.controlHeight)
                }

                Button(action: toggleAdvancedOptions) {
                    Label {
                        Text("Advanced Options")
                            .font(.headline)
                    } icon: {
                        Image(systemName: advancedOptionsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.bold())
                            .frame(width: 14)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.leading, Self.labelWidth + 12)

                if advancedOptionsExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Checkout branch:")
                                .frame(width: Self.labelWidth, alignment: .trailing)

                            Picker("", selection: $checkoutBranch) {
                                ForEach(branchPickerOptions, id: \.branch) { option in
                                    Text(option.title).tag(option.branch)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(height: Self.controlHeight)
                            .disabled(isBranchPickerDisabled)

                            Color.clear
                                .frame(width: Self.trailingControlWidth, height: Self.controlHeight)
                        }

                        Toggle("Download LFS content", isOn: $downloadLFSContent)
                            .padding(.leading, Self.labelWidth + 12)
                        Toggle("Recurse submodules", isOn: $recurseSubmodules)
                            .padding(.leading, Self.labelWidth + 12)
                    }
                    .transition(.opacity)
                }
            }

            HStack {
                if lfsRuntime.isInstalling {
                    ProgressView("Downloading Git LFS…").controlSize(.small)
                    Button("Cancel Download", role: .cancel) { lfsRuntime.cancel() }
                } else {
                    Label(repositoryStatusText, systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCloning)

                Button(action: performClone) {
                    if isCloning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Clone")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canClone)
            }
        }
        .padding(30)
        .frame(minWidth: 680)
        .task(id: [trimmedRemoteURL, discoveredAccountID ?? ""]) {
            await loadRemoteBranches(for: trimmedRemoteURL)
        }
        .alert("Error", isPresented: $showingError, actions: {
            if let clonedRepository {
                if lfsRuntime.status?.activeRuntime == nil {
                    Button("Download Git LFS & Continue") { finishLFSClone(downloadRuntime: true) }
                } else {
                    Button("Retry LFS Download") { finishLFSClone(downloadRuntime: false) }
                }
                Button("Open Cloned Repository") { onClone(clonedRepository); dismiss() }
            }
            Button("OK", role: .cancel) {}
        }, message: {
            Text((errorMessage ?? "An unknown error occurred") + (clonedRepository != nil && lfsRuntime.status?.activeRuntime == nil ? "\n\nDownload a private copy: " + lfsRuntime.downloadDescription : ""))
        })
        .onChange(of: showingDestinationPicker) { _, newValue in
            if newValue {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.message = "Select a destination folder"
                panel.prompt = "Select"

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    panel.beginSheetModal(for: NSApp.keyWindow!) { result in
                        showingDestinationPicker = false
                        if result == .OK, let url = panel.url {
                            destinationPath = url.path
                        }
                    }
                }
            }
        }
    }

    private var cloneCredentialResolver: GitProviderCredentialResolver? {
        guard var resolver = lfsCredentialResolver else { return nil }
        if let discoveredAccountID, let identity = resolver.remoteIdentity(for: remoteURL),
           resolver.matchingAccounts(for: remoteURL).contains(where: { $0.id == discoveredAccountID }) {
            resolver.preferredAccountIDsByRemoteIdentity[GitProviderAccountPreferenceKey.make(for: identity)] = discoveredAccountID
        }
        return resolver
    }

    private var canClone: Bool {
        !isCloning
            && !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repositoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var repositoryStatusText: String {
        remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Enter a Git repository URL"
            : "This is a Git repository"
    }

    private var trimmedRemoteURL: String {
        remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var branchPickerOptions: [(title: String, branch: String)] {
        if trimmedRemoteURL.isEmpty {
            return [("Source URL not found", "")]
        }

        if isLoadingRemoteBranches {
            return [("Loading branches...", checkoutBranch)]
        }

        if remoteBranchLoadError != nil {
            return [("Remote branches not found", "")]
        }

        guard !remoteBranches.isEmpty else {
            return [("No remote branches found", "")]
        }

        return [("Default branch", "")]
            + remoteBranches.map { ("origin/\($0)", $0) }
    }

    private var isBranchPickerDisabled: Bool {
        trimmedRemoteURL.isEmpty
            || isLoadingRemoteBranches
            || remoteBranchLoadError != nil
            || remoteBranches.isEmpty
            || isCloning
    }

    private var remoteURLBinding: Binding<String> {
        Binding(
            get: { remoteURL },
            set: { newValue in
                discoveredAccountID = nil
                remoteURL = newValue
            }
        )
    }

    private var repositoryNameBinding: Binding<String> {
        Binding(
            get: { repositoryName },
            set: { newValue in
                repositoryName = newValue
                repositoryNameWasEdited = true
            }
        )
    }

    private func toggleAdvancedOptions() {
        advancedOptionsExpanded.toggle()
    }

    private func loadRemoteBranches(for sourceURL: String) async {
        remoteBranchLoadError = nil
        remoteBranches = []

        guard !sourceURL.isEmpty else {
            checkoutBranch = ""
            isLoadingRemoteBranches = false
            return
        }

        isLoadingRemoteBranches = true

        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            let branches = try await GitStatusService.shared.remoteBranches(remoteURL: sourceURL, credentialResolver: cloneCredentialResolver)
            guard !Task.isCancelled else { return }
            remoteBranches = branches
            remoteBranchLoadError = nil
            if !branches.contains(checkoutBranch) {
                checkoutBranch = ""
            }
        } catch is CancellationError {
            return
        } catch {
            remoteBranches = []
            remoteBranchLoadError = error.localizedDescription
            checkoutBranch = ""
        }

        isLoadingRemoteBranches = false
    }

    private func performClone() {
        let trimmedRemoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedRemoteURL.isEmpty else {
            errorMessage = "Please enter a Git repository URL."
            showingError = true
            return
        }

        guard let finalURL = Self.finalCloneURL(destinationPath: destinationPath, repositoryName: repositoryName) else {
            errorMessage = "Please enter a valid destination path and repository name."
            showingError = true
            return
        }

        if FileManager.default.fileExists(atPath: finalURL.path) {
            errorMessage = "A folder named \"\(finalURL.lastPathComponent)\" already exists at the destination."
            showingError = true
            return
        }

        isCloning = true

        Task {
            do {
                try await GitStatusService.shared.cloneRepository(
                    remoteURL: trimmedRemoteURL,
                    to: finalURL,
                    checkoutBranch: checkoutBranch,
                    recurseSubmodules: recurseSubmodules,
                    downloadLFSContent: downloadLFSContent,
                    credentialResolver: cloneCredentialResolver
                )

                await MainActor.run {
                    onClone(finalURL)
                    dismiss()
                }
            } catch {
                await lfsRuntime.refresh()
                await MainActor.run {
                    clonedRepository = (error as? GitLFSCloneRecoveryError)?.repository
                    errorMessage = error.localizedDescription
                    showingError = true
                    isCloning = false
                }
            }
        }
    }

    private func finishLFSClone(downloadRuntime: Bool) {
        guard let repository = clonedRepository else { return }
        isCloning = true
        Task {
            let installed = downloadRuntime ? await lfsRuntime.install() : true
            do {
                guard installed else { throw GitError.commandFailed(lfsRuntime.error ?? "Git LFS installation was cancelled.") }
                guard lfsRuntime.status?.activeRuntime != nil else {
                    throw GitError.commandFailed(lfsRuntime.error ?? "Git LFS installation was cancelled.")
                }
                try await GitStatusService.shared.finishLFSClone(in: repository, credentialResolver: cloneCredentialResolver)
                onClone(repository)
                dismiss()
            } catch {
                errorMessage = GitLFSErrorMessage.sanitized(error.localizedDescription)
                showingError = true
                isCloning = false
            }
        }
    }

    static func defaultRepositoryName(from remoteURL: String) -> String {
        var trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if let components = URLComponents(string: trimmed),
           let lastComponent = components.url?.deletingPathExtension().lastPathComponent,
           !lastComponent.isEmpty {
            return lastComponent
        }

        if let lastPathComponent = trimmed.split(separator: "/").last {
            let name = removingGitSuffix(from: String(lastPathComponent))
            if let colonIndex = name.lastIndex(of: ":") {
                return String(name[name.index(after: colonIndex)...])
            }
            return name
        }

        return ""
    }

    static func finalCloneURL(destinationPath: String, repositoryName: String) -> URL? {
        let trimmedDestination = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDestination.isEmpty,
              !trimmedName.isEmpty,
              trimmedName != ".",
              trimmedName != "..",
              !trimmedName.contains("/") else {
            return nil
        }

        return URL(fileURLWithPath: trimmedDestination, isDirectory: true)
            .appendingPathComponent(trimmedName, isDirectory: true)
    }

    private static func removingGitSuffix(from name: String) -> String {
        name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }
}
