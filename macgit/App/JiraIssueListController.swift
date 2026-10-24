// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

protocol JiraIssueFilterStoring {
    func filter(forRepositoryKey key: String) async -> JiraIssueFilter?
    func save(_ filter: JiraIssueFilter, forRepositoryKey key: String) async
}

/// Remembers each repository's Jira filter on this Mac. Search text is never stored.
final class LocalJiraIssueFilterStore: JiraIssueFilterStoring {
    static let collection = "jiraIssueFilters"
    private let dataStore: LocalDataStore

    init(dataStore: LocalDataStore? = nil) {
        self.dataStore = dataStore ?? .shared
    }

    func filter(forRepositoryKey key: String) async -> JiraIssueFilter? {
        try? await dataStore.readValue(JiraIssueFilter.self, in: Self.collection, id: key)
    }

    func save(_ filter: JiraIssueFilter, forRepositoryKey key: String) async {
        _ = try? await dataStore.transaction { transaction in
            if filter.isDefault {
                transaction.remove(in: Self.collection, id: key)
            } else {
                try transaction.set(filter, in: Self.collection, id: key)
            }
        }
    }
}

struct JiraProjectOption: Hashable, Identifiable {
    var key: String
    var name: String

    var id: String { key }
}

/// The Jira issue list for one repository window.
@MainActor
final class JiraIssueListController: ObservableObject {
    @Published private(set) var items: [JiraIssue] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedList = false
    @Published private(set) var error: JiraError?
    @Published private(set) var nextPageToken: String?
    /// Whether the user has any assigned issues at all; checked only when a filtered list is empty.
    @Published private(set) var hasAnyAssignedIssues = true
    @Published private(set) var filter = JiraIssueFilter.default
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }
    @Published private(set) var sprintOptions: [JiraSprintRef] = []
    @Published private(set) var projectOptions: [JiraProjectOption] = []
    @Published private(set) var issueTypeOptions: [String] = []

    private let connectionController: JiraConnectionController
    private let filterStore: JiraIssueFilterStoring
    private let repositoryKey: String
    private let searchDebounce: Duration
    private var hasRestoredFilter = false
    private var isActive = false
    private var generation = 0
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var loadedConnectionID: String?
    private var knownSprints: [Int: JiraSprintRef] = [:]
    private var knownProjects: [String: String] = [:]
    private var knownIssueTypes: Set<String> = []
    private var connectionObservation: AnyCancellable?

    private struct ConnectionState: Equatable {
        let id: String
        let needsReconnect: Bool
    }

    init(
        repositoryURL: URL,
        connectionController: JiraConnectionController,
        filterStore: JiraIssueFilterStoring = LocalJiraIssueFilterStore(),
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.connectionController = connectionController
        self.filterStore = filterStore
        self.repositoryKey = repositoryURL.standardizedFileURL.path
        self.searchDebounce = searchDebounce
        // Reconnecting keeps the connection id and only clears `needsReconnect`, so observe both.
        // A transition to `needsReconnect` is already handled by `handle(_:)`.
        connectionObservation = connectionController.$connection
            .map { $0.map { ConnectionState(id: $0.id, needsReconnect: $0.needsReconnect) } }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] state in
                guard state?.needsReconnect != true else { return }
                Task { @MainActor in self?.connectionDidChange() }
            }
    }

    var connection: JiraConnection? { connectionController.connection }

    var supportsSprints: Bool { connection?.supportsSprints ?? false }

    var isFiltered: Bool { !filter.isDefault || !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Called while the Jira screen is shown and access is allowed. The first call restores the filter and loads.
    func activate() async {
        isActive = true
        if !hasRestoredFilter {
            hasRestoredFilter = true
            if let stored = await filterStore.filter(forRepositoryKey: repositoryKey) {
                filter = stored
                rememberSelection(of: stored)
            }
        }
        if !hasLoadedList || loadedConnectionID != connection?.id {
            reload()
        }
    }

    func deactivate() {
        isActive = false
    }

    func refresh() {
        reload()
    }

    func updateFilter(_ update: (inout JiraIssueFilter) -> Void) {
        var updated = filter
        update(&updated)
        guard updated != filter else { return }
        filter = updated
        rememberSelection(of: updated)
        let filterStore = filterStore
        let repositoryKey = repositoryKey
        Task { await filterStore.save(updated, forRepositoryKey: repositoryKey) }
        reload()
    }

    func resetFilters() {
        searchTask?.cancel()
        if !searchText.isEmpty {
            // Avoid a second, debounced reload from the didSet.
            searchText = ""
            searchTask?.cancel()
        }
        if filter.isDefault {
            reload()
        } else {
            updateFilter { $0 = .default }
        }
    }

    func loadMore() {
        guard let nextPageToken, !isLoading, !isLoadingMore, error == nil else { return }
        guard let connection, let credential = connectionController.credential() else { return }
        let generation = generation
        let query = currentFilterWithSearch
        isLoadingMore = true
        loadTask = Task {
            defer { if generation == self.generation { isLoadingMore = false } }
            do {
                let page = try await search(query, connection: connection, credential: credential, pageToken: nextPageToken)
                guard generation == self.generation else { return }
                items += page.issues.filter { issue in !items.contains { $0.id == issue.id } }
                self.nextPageToken = page.nextPageToken
                learnOptions(from: page.issues)
            } catch {
                guard generation == self.generation, !(error is CancellationError) else { return }
                await handle(error)
            }
        }
    }

    // MARK: - Loading

    private var currentFilterWithSearch: JiraIssueFilter {
        var query = filter
        query.searchText = searchText
        return query
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let delay = searchDebounce
        searchTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    private func reload() {
        loadTask?.cancel()
        generation += 1
        let generation = generation
        guard let connection else {
            items = []
            nextPageToken = nil
            error = nil
            isLoading = false
            isLoadingMore = false
            loadedConnectionID = nil
            return
        }
        guard let credential = connectionController.credential() else {
            isLoading = false
            error = .needsReconnect
            return
        }
        let query = currentFilterWithSearch
        let probeNeeded = query != Self.allAssignedIssues
        isLoading = true
        isLoadingMore = false
        loadTask = Task {
            do {
                let page = try await search(query, connection: connection, credential: credential, pageToken: nil)
                guard generation == self.generation else { return }
                var hasAny = true
                if page.issues.isEmpty, probeNeeded {
                    hasAny = try await hasAssignedIssues(connection: connection, credential: credential)
                    guard generation == self.generation else { return }
                }
                items = page.issues
                nextPageToken = page.nextPageToken
                hasAnyAssignedIssues = hasAny
                error = nil
                hasLoadedList = true
                loadedConnectionID = connection.id
                learnOptions(from: page.issues)
            } catch {
                guard generation == self.generation, !(error is CancellationError) else { return }
                await handle(error)
                hasLoadedList = true
                loadedConnectionID = connection.id
            }
            if generation == self.generation { isLoading = false }
        }
    }

    private func search(
        _ query: JiraIssueFilter,
        connection: JiraConnection,
        credential: JiraCredential,
        pageToken: String?
    ) async throws -> JiraIssuePage {
        let client = connectionController.client
        let jql = JiraJQLBuilder.jql(for: query, supportsSprints: connection.supportsSprints)
        do {
            return try await client.searchIssues(
                baseURL: connection.apiBaseURL,
                credential: credential,
                jql: jql,
                sprintFieldID: connection.sprintFieldID,
                pageToken: pageToken
            )
        } catch JiraError.invalidQuery where JiraJQLBuilder.issueKey(in: query.searchText) != nil {
            // Jira rejects `key = X-1` when project X does not exist; fall back to text search.
            return try await client.searchIssues(
                baseURL: connection.apiBaseURL,
                credential: credential,
                jql: JiraJQLBuilder.jql(for: query, supportsSprints: connection.supportsSprints, includeKeyClause: false),
                sprintFieldID: connection.sprintFieldID,
                pageToken: pageToken
            )
        }
    }

    private static let allAssignedIssues: JiraIssueFilter = {
        var filter = JiraIssueFilter()
        filter.sprintScope = .any
        filter.statusCategories = []
        return filter
    }()

    private func hasAssignedIssues(connection: JiraConnection, credential: JiraCredential) async throws -> Bool {
        let page = try await search(Self.allAssignedIssues, connection: connection, credential: credential, pageToken: nil)
        learnOptions(from: page.issues)
        return !page.issues.isEmpty
    }

    private func handle(_ error: Error) async {
        let jiraError = error as? JiraError ?? .unreachable
        self.error = jiraError
        isLoading = false
        isLoadingMore = false
        if jiraError == .needsReconnect {
            await connectionController.markNeedsReconnect()
        }
    }

    private func connectionDidChange() {
        items = []
        nextPageToken = nil
        error = nil
        hasLoadedList = false
        loadedConnectionID = nil
        knownSprints = [:]
        knownProjects = [:]
        knownIssueTypes = []
        rememberSelection(of: filter)
        if isActive { reload() }
    }

    // MARK: - Filter options

    private func rememberSelection(of filter: JiraIssueFilter) {
        if case .sprint(let id, let name) = filter.sprintScope, knownSprints[id] == nil {
            knownSprints[id] = JiraSprintRef(id: id, name: name, state: "")
        }
        for key in filter.projectKeys where knownProjects[key] == nil {
            knownProjects[key] = key
        }
        knownIssueTypes.formUnion(filter.issueTypeNames)
        publishOptions()
    }

    private func learnOptions(from issues: [JiraIssue]) {
        for issue in issues {
            for sprint in issue.sprints { knownSprints[sprint.id] = sprint }
            if !issue.projectKey.isEmpty { knownProjects[issue.projectKey] = issue.projectName }
            if !issue.issueTypeName.isEmpty { knownIssueTypes.insert(issue.issueTypeName) }
        }
        publishOptions()
    }

    private func publishOptions() {
        func rank(_ sprint: JiraSprintRef) -> Int {
            switch sprint.state {
            case "active": 0
            case "future": 1
            default: 2
            }
        }
        sprintOptions = knownSprints.values.sorted {
            rank($0) != rank($1) ? rank($0) < rank($1) : $0.id > $1.id
        }
        projectOptions = knownProjects
            .map { JiraProjectOption(key: $0.key, name: $0.value) }
            .sorted { $0.key < $1.key }
        issueTypeOptions = knownIssueTypes.sorted()
    }
}
