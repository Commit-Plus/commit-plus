// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

protocol HostedIssuePreferenceStoring {
    func remoteName(forRepositoryKey key: String) async -> String?
    func saveRemoteName(_ name: String, forRepositoryKey key: String) async
    func filter(forRepositoryKey key: String, remote: String) async -> HostedIssueFilter?
    func save(_ filter: HostedIssueFilter, forRepositoryKey key: String, remote: String) async
}

/// Remembers each repository's chosen issue remote and per-remote filter on this Mac.
/// Search text is never stored.
final class LocalHostedIssuePreferenceStore: HostedIssuePreferenceStoring {
    static let remoteCollection = "hostedIssueRemotes"
    static let filterCollection = "hostedIssueFilters"
    private let dataStore: LocalDataStore

    private struct StoredRemote: Codable {
        var name: String
    }

    init(dataStore: LocalDataStore? = nil) {
        self.dataStore = dataStore ?? .shared
    }

    func remoteName(forRepositoryKey key: String) async -> String? {
        try? await dataStore.readValue(StoredRemote.self, in: Self.remoteCollection, id: key)?.name
    }

    func saveRemoteName(_ name: String, forRepositoryKey key: String) async {
        _ = try? await dataStore.transaction { transaction in
            try transaction.set(StoredRemote(name: name), in: Self.remoteCollection, id: key)
        }
    }

    func filter(forRepositoryKey key: String, remote: String) async -> HostedIssueFilter? {
        try? await dataStore.readValue(HostedIssueFilter.self, in: Self.filterCollection, id: Self.filterID(key, remote))
    }

    func save(_ filter: HostedIssueFilter, forRepositoryKey key: String, remote: String) async {
        let id = Self.filterID(key, remote)
        _ = try? await dataStore.transaction { transaction in
            if filter.isDefault {
                transaction.remove(in: Self.filterCollection, id: id)
            } else {
                try transaction.set(filter, in: Self.filterCollection, id: id)
            }
        }
    }

    private static func filterID(_ key: String, _ remote: String) -> String {
        key + "\n" + remote
    }
}

/// A remote whose provider has an issue tracker Commit+ supports.
struct HostedIssueRemote: Equatable, Identifiable {
    var name: String
    var provider: HostedIssueProvider
    var repository: GitRepositoryIdentity

    var id: String { name }
}

/// Why the list cannot load with a provider account, and which host to connect.
enum HostedIssueAccountProblem: Equatable {
    case noAccount(GitProviderHost)
    case reconnect(GitProviderHost)
}

/// The hosted issue screen for one repository window.
@MainActor
final class HostedIssueController: ObservableObject {
    static let listCacheTTL: TimeInterval = 60
    static let detailCacheTTL: TimeInterval = 300

    @Published private(set) var remotes: [HostedIssueRemote] = []
    @Published private(set) var selectedRemote: HostedIssueRemote?
    @Published private(set) var hasDiscoveredRemotes = false
    @Published private(set) var items: [HostedIssueSummary] = []
    @Published private(set) var next: HostedIssueCursor?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedList = false
    @Published private(set) var error: HostedIssueError?
    @Published private(set) var accountProblem: HostedIssueAccountProblem?
    @Published private(set) var filter = HostedIssueFilter.default
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }
    @Published private(set) var selectedIssueNumber: Int?
    @Published private(set) var detail: HostedIssueDetail?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var detailError: HostedIssueError?
    @Published private(set) var isWriting = false
    @Published private(set) var writeError: HostedIssueError?
    @Published private(set) var workItemTypes: [String] = []

    /// Re-checks plan access before a write; set by the window that owns the controller.
    var authorizeWrite: () async -> Bool = { true }

    var provider: HostedIssueProvider? { selectedRemote?.provider }
    var isFiltered: Bool { !filter.isDefault || !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private let repositoryURL: URL
    private let repositoryKey: String
    private let credentialResolver: GitProviderAPICredentialResolver
    private let services: [HostedIssueProvider: any HostedIssueProviding]
    private let preferenceStore: HostedIssuePreferenceStoring
    private let remoteNamesProvider: (URL) async -> [String]
    private let remoteURLProvider: (URL, String) async -> String?
    private let searchDebounce: Duration
    private let now: () -> Date

    private var isActive = false
    private var restoredRemoteName: String??
    private var generation = 0
    private var detailGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var lastLoadedAt: Date?
    private var loadedKey: String?
    private var listCache: [String: (page: HostedIssuePage, loadedAt: Date)] = [:]
    private var detailCache: [String: (detail: HostedIssueDetail, loadedAt: Date)] = [:]
    private var accountID: String?
    private var observers: [AnyCancellable] = []

    init(
        repositoryURL: URL,
        credentialResolver: GitProviderAPICredentialResolver,
        services: [HostedIssueProvider: any HostedIssueProviding],
        preferenceStore: HostedIssuePreferenceStoring = LocalHostedIssuePreferenceStore(),
        remoteNamesProvider: @escaping (URL) async -> [String] = { await GitStatusService.shared.remotes(in: $0) },
        remoteURLProvider: @escaping (URL, String) async -> String? = { repositoryURL, remote in
            let url = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
            return url.isEmpty ? nil : url
        },
        searchDebounce: Duration = .milliseconds(400),
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.repositoryURL = repositoryURL
        self.repositoryKey = repositoryURL.standardizedFileURL.path
        self.credentialResolver = credentialResolver
        self.services = services
        self.preferenceStore = preferenceStore
        self.remoteNamesProvider = remoteNamesProvider
        self.remoteURLProvider = remoteURLProvider
        self.searchDebounce = searchDebounce
        self.now = now
        for name in [Notification.Name.repositoryRemoteRefsDidRefresh, .repositoryDidChange] {
            notificationCenter.publisher(for: name)
                .sink { [weak self] notification in
                    // Other windows post for their own repositories.
                    guard let url = notification.userInfo?["repositoryURL"] as? URL,
                          url.standardizedFileURL == repositoryURL.standardizedFileURL else { return }
                    Task { @MainActor in await self?.discoverRemotes() }
                }
                .store(in: &observers)
        }
    }

    // MARK: - Remotes

    /// Finds remotes with a supported tracker: `origin` first, then the rest in Git's order.
    func discoverRemotes() async {
        let names = await remoteNamesProvider(repositoryURL)
        var found: [HostedIssueRemote] = []
        for name in names {
            guard let url = await remoteURLProvider(repositoryURL, name),
                  let repository = credentialResolver.repository(forRemoteURL: url) else { continue }
            found.append(HostedIssueRemote(name: name, provider: HostedIssueProvider(repository.provider), repository: repository))
        }
        found = found.filter { $0.name == "origin" } + found.filter { $0.name != "origin" }
        if restoredRemoteName == nil {
            restoredRemoteName = .some(await preferenceStore.remoteName(forRepositoryKey: repositoryKey))
        }
        let stored: String? = restoredRemoteName ?? nil
        let preferred = selectedRemote?.name ?? stored
        let selection = found.first { $0.name == preferred } ?? found.first
        remotes = found
        hasDiscoveredRemotes = true
        guard selection != selectedRemote else { return }
        await applyRemote(selection)
    }

    func selectRemote(named name: String) {
        guard let remote = remotes.first(where: { $0.name == name }), remote != selectedRemote else { return }
        let preferenceStore = preferenceStore
        let repositoryKey = repositoryKey
        Task {
            await preferenceStore.saveRemoteName(name, forRepositoryKey: repositoryKey)
            await applyRemote(remote)
        }
    }

    private func applyRemote(_ remote: HostedIssueRemote?) async {
        selectedRemote = remote
        filter = .default
        if let remote {
            filter = await preferenceStore.filter(forRepositoryKey: repositoryKey, remote: remote.name) ?? .default
        }
        guard remote == selectedRemote else { return }
        items = []
        next = nil
        hasLoadedList = false
        workItemTypes = []
        clearSelection()
        if isActive { reload(useCache: true) }
    }

    // MARK: - Screen lifecycle

    /// Called while the screen is shown and access is allowed.
    func activate() async {
        // Discover first so choosing the initial remote does not start a second load.
        if !hasDiscoveredRemotes { await discoverRemotes() }
        isActive = true
        let stale = lastLoadedAt.map { now().timeIntervalSince($0) > Self.listCacheTTL } ?? true
        if !hasLoadedList || stale { reload(useCache: !stale) }
    }

    func deactivate() {
        isActive = false
    }

    /// Reloads the list and the open issue; Refresh is the way to bypass both caches.
    func refresh() {
        detailCache.removeAll()
        reload(useCache: false)
        if let number = selectedIssueNumber { loadDetail(number) }
    }

    func updateFilter(_ update: (inout HostedIssueFilter) -> Void) {
        var updated = filter
        update(&updated)
        guard updated != filter, let remote = selectedRemote else { return }
        filter = updated
        let preferenceStore = preferenceStore
        let repositoryKey = repositoryKey
        Task { await preferenceStore.save(updated, forRepositoryKey: repositoryKey, remote: remote.name) }
        reload(useCache: true)
    }

    func resetFilters() {
        searchTask?.cancel()
        if !searchText.isEmpty {
            searchText = ""
            searchTask?.cancel()
        }
        if filter.isDefault { reload(useCache: false) } else { updateFilter { $0 = .default } }
    }

    // MARK: - Loading

    private struct Context {
        var remote: HostedIssueRemote
        var service: any HostedIssueProviding
        var account: GitProviderAccount
        var token: GitProviderToken
    }

    private func context() -> Context? {
        guard let remote = selectedRemote, let service = services[remote.provider] else { return nil }
        let accounts = credentialResolver.matchingAccounts(for: remote.repository)
        let host = GitProviderHost(kind: remote.repository.provider, baseURL: remote.repository.hostURL).normalized
        guard !accounts.isEmpty else {
            accountProblem = .noAccount(host)
            return nil
        }
        guard let credential = credentialResolver.credential(for: accounts, preferredAccountID: accountID) else {
            accountProblem = accounts.contains(where: GitProviderAPICredentialResolver.supportsProviderAPI)
                ? .reconnect(host) : .noAccount(host)
            return nil
        }
        accountProblem = nil
        accountID = credential.account.id
        return Context(remote: remote, service: service, account: credential.account, token: credential.token)
    }

    private func cacheKey(_ context: Context, search: String) -> String {
        [context.remote.name, context.account.id, filter.state.rawValue, filter.relationship.rawValue, search].joined(separator: "\n")
    }

    private func reload(useCache: Bool, keeping pinned: HostedIssueSummary? = nil) {
        loadTask?.cancel()
        generation += 1
        let generation = generation
        guard let context = context() else {
            items = []
            next = nil
            error = nil
            isLoading = false
            isLoadingMore = false
            return
        }
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = cacheKey(context, search: search)
        if useCache, pinned == nil, let cached = listCache[key], now().timeIntervalSince(cached.loadedAt) <= Self.listCacheTTL {
            apply(cached.page, key: key, loadedAt: cached.loadedAt, pinned: nil)
            return
        }
        let filter = filter
        isLoading = true
        isLoadingMore = false
        loadTask = Task {
            defer { if generation == self.generation { isLoading = false } }
            do {
                let page = try await context.service.listIssues(
                    repository: context.remote.repository, account: context.account, token: context.token,
                    filter: filter, search: search, cursor: nil
                )
                guard generation == self.generation else { return }
                let loadedAt = now()
                listCache[key] = (page, loadedAt)
                apply(page, key: key, loadedAt: loadedAt, pinned: pinned)
            } catch {
                guard generation == self.generation, !(error is CancellationError) else { return }
                self.error = Self.issueError(error)
            }
        }
    }

    private func apply(_ page: HostedIssuePage, key: String, loadedAt: Date, pinned: HostedIssueSummary?) {
        var items = page.items
        // A just-written issue stays visible until the next refresh even if it left the filter.
        if let pinned {
            if let index = items.firstIndex(where: { $0.number == pinned.number }) {
                items[index] = pinned
            } else {
                let oldIndex = self.items.firstIndex { $0.number == pinned.number } ?? 0
                items.insert(pinned, at: min(oldIndex, items.count))
            }
        }
        self.items = items
        next = page.next
        error = nil
        hasLoadedList = true
        loadedKey = key
        lastLoadedAt = loadedAt
    }

    func loadMore() {
        guard let cursor = next, !isLoading, !isLoadingMore, error == nil, let context = context() else { return }
        let generation = generation
        let filter = filter
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoadingMore = true
        loadTask = Task {
            defer { if generation == self.generation { isLoadingMore = false } }
            do {
                let page = try await context.service.listIssues(
                    repository: context.remote.repository, account: context.account, token: context.token,
                    filter: filter, search: search, cursor: cursor
                )
                guard generation == self.generation else { return }
                items += page.items.filter { issue in !items.contains { $0.number == issue.number } }
                next = page.next
            } catch {
                guard generation == self.generation, !(error is CancellationError) else { return }
                self.error = Self.issueError(error)
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let delay = searchDebounce
        searchTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            reload(useCache: true)
        }
    }

    // MARK: - Detail

    func select(_ number: Int?) {
        guard number != selectedIssueNumber else { return }
        detailGeneration += 1
        selectedIssueNumber = number
        writeError = nil
        detail = nil
        detailError = nil
        isLoadingDetail = false
        guard let number else { return }
        // Going back to an issue seen in the last few minutes shows it without a request.
        if let key = detailKey(number), let cached = detailCache[key],
           now().timeIntervalSince(cached.loadedAt) <= Self.detailCacheTTL {
            detail = cached.detail
            return
        }
        loadDetail(number)
    }

    private func detailKey(_ number: Int) -> String? {
        guard let remote = selectedRemote else { return nil }
        return [remote.name, accountID ?? "", String(number)].joined(separator: "\n")
    }

    private func storeDetail(_ detail: HostedIssueDetail, number: Int) {
        guard let key = detailKey(number) else { return }
        detailCache[key] = (detail, now())
    }

    private func clearSelection() {
        detailGeneration += 1
        selectedIssueNumber = nil
        detail = nil
        detailError = nil
        writeError = nil
        isLoadingDetail = false
    }

    private func loadDetail(_ number: Int) {
        detailGeneration += 1
        let generation = detailGeneration
        guard let context = context() else { return }
        isLoadingDetail = true
        Task {
            defer { if generation == detailGeneration { isLoadingDetail = false } }
            do {
                let detail = try await context.service.issueDetail(number: number, repository: context.remote.repository, token: context.token)
                guard generation == detailGeneration else { return }
                storeDetail(detail, number: number)
                self.detail = detail
                detailError = nil
            } catch {
                guard generation == detailGeneration, !(error is CancellationError) else { return }
                detailError = Self.issueError(error)
            }
        }
    }

    func loadWorkItemTypes() async {
        guard provider?.supportsWorkItemTypes == true, workItemTypes.isEmpty, let context = context() else { return }
        workItemTypes = (try? await context.service.workItemTypes(repository: context.remote.repository, token: context.token)) ?? []
    }

    // MARK: - Writes

    /// Creates an issue and selects it. Returns whether it succeeded so the sheet can close.
    @discardableResult
    func createIssue(_ draft: HostedIssueDraft) async -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        var draft = draft
        draft.title = title
        guard let summary = await write({ context in
            try await context.service.createIssue(draft, repository: context.remote.repository, token: context.token)
        }) else { return false }
        selectedIssueNumber = summary.number
        detail = nil
        loadDetail(summary.number)
        reload(useCache: false, keeping: summary)
        return true
    }

    /// Posts a comment on the selected issue. Returns whether it succeeded so the composer can clear.
    @discardableResult
    func addComment(_ body: String) async -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let number = selectedIssueNumber else { return false }
        guard await write({ context in
            try await context.service.addComment(text, number: number, repository: context.remote.repository, token: context.token)
        }) != nil else { return false }
        await reloadAfterWrite(number)
        return true
    }

    func setState(_ state: HostedIssueState) async {
        guard let number = selectedIssueNumber else { return }
        guard await write({ context in
            try await context.service.setState(state, number: number, repository: context.remote.repository, token: context.token)
        }) != nil else { return }
        await reloadAfterWrite(number)
    }

    private func write<Result>(_ operation: (Context) async throws -> Result) async -> Result? {
        guard !isWriting else { return nil }
        writeError = nil
        guard await authorizeWrite(), let context = context() else { return nil }
        isWriting = true
        defer { isWriting = false }
        do {
            return try await operation(context)
        } catch {
            writeError = Self.issueError(error)
            return nil
        }
    }

    private func reloadAfterWrite(_ number: Int) async {
        guard let context = context() else { return }
        detailGeneration += 1
        let generation = detailGeneration
        do {
            let detail = try await context.service.issueDetail(number: number, repository: context.remote.repository, token: context.token)
            storeDetail(detail, number: number)
            guard generation == detailGeneration, selectedIssueNumber == number else { return }
            self.detail = detail
            reload(useCache: false, keeping: detail.summary)
        } catch {
            guard generation == detailGeneration else { return }
            detailError = Self.issueError(error)
            reload(useCache: false)
        }
    }

    func clearWriteError() {
        writeError = nil
    }

    static func issueError(_ error: Error) -> HostedIssueError {
        if let error = error as? HostedIssueError { return error }
        if error is DecodingError {
            return .providerMessage("The provider returned a response Commit+ could not read.")
        }
        return .providerMessage(error.localizedDescription)
    }
}
