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

import Combine
import Foundation

private struct PullRequestListCacheKey: Hashable {
    let repository: GitRepositoryIdentityKey
    let accountID: String
    let filter: PullRequestListFilter
    let page: Int
    let perPage: Int
    var diskKey: String { repository.diskKey + "." + ([accountID, "list"] + [filter.rawValue, String(page), String(perPage)]).map { Data($0.utf8).base64EncodedString() }.joined(separator: ".") }

}

private struct PullRequestDetailCacheKey: Hashable {
    let repository: GitRepositoryIdentityKey
    let accountID: String
    let number: Int
    var diskKey: String { repository.diskKey + "." + ([accountID, "detail"] + [String(number)]).map { Data($0.utf8).base64EncodedString() }.joined(separator: ".") }

}

private struct PullRequestChangesCacheKey: Hashable {
    let repository: GitRepositoryIdentityKey
    let accountID: String
    let number: Int
    var diskKey: String { repository.diskKey + "." + ([accountID, "changes"] + [String(number)]).map { Data($0.utf8).base64EncodedString() }.joined(separator: ".") }

}

private struct GitRepositoryIdentityKey: Hashable {
    let provider: GitProviderKind
    let host: String
    let owner: String
    let name: String

    var diskKey: String {
        [provider.rawValue, host, owner, name].map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
    }

    init(_ repository: GitRepositoryIdentity) {
        provider = repository.provider
        host = repository.hostURL.absoluteString
        owner = repository.owner
        name = repository.name
    }
}

@MainActor
final class PullRequestController: ObservableObject {
    @Published private(set) var items: [PullRequestSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var detailErrorMessage: String?
    @Published var stateFilter: PullRequestListFilter = .open
    @Published var createdByMeOnly = false
    @Published private(set) var currentPage = 1
    @Published private(set) var hasPreviousPage = false
    @Published private(set) var hasNextPage = false
    @Published private(set) var selectedProviderAccountID: String?
    @Published private(set) var selectedDetail: PullRequestDetail?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var selectedChanges: [PullRequestChangedFile] = []
    @Published private(set) var isLoadingChanges = false
    @Published private(set) var changesErrorMessage: String?
    @Published private(set) var createDraftSeed: PullRequestDraftSeed?
    @Published private(set) var createDraftChangedFileCount: Int?
    @Published private(set) var isLoadingCreateDraftChanges = false
    @Published private(set) var createDraftChangesErrorMessage: String?
    @Published private(set) var createDraftParticipants: [PullRequestParticipant] = []
    @Published private(set) var isLoadingCreateDraftParticipants = false
    @Published private(set) var createDraftParticipantsErrorMessage: String?
    @Published private(set) var isPerformingAction = false
    @Published private(set) var accountConnectionHost: GitProviderHost?

    private let providerAccountController: GitProviderAccountController
    private let tokenVault: GitProviderTokenVault
    private let services: [GitProviderKind: any PullRequestProviding]
    private let remoteNameProvider: (URL) async -> String?
    private let remoteURLProvider: (URL, String) async -> String?
    private let currentBranchProvider: (URL) async -> String?
    private let defaultBranchProvider: (URL) async -> String?
    private let localBranchesProvider: (URL) async -> [String]
    private let remoteBranchesProvider: (URL) async -> [String]
    private let changedFileCountProvider: (URL, String, String, String?) async throws -> Int
    private let fetchPullRequestRef: (String, String, String, URL, GitProviderCredentialResolver?) async throws -> Void
    private let checkoutBranch: (String, URL) async throws -> Void
    private let openURL: (URL) -> Bool
    private var activeRepository: GitRepositoryIdentity?
    private var activeRepositoryURL: URL?
    private var activeRemoteName: String?
    private var activeRemoteURLString: String?
    private var activeToken: GitProviderToken?
    private let pullRequestPageSize = 30
    private let listCacheTTL: TimeInterval = 120
    private let detailCacheTTL: TimeInterval = 300
    private let changesCacheTTL: TimeInterval = 300
    private let commentRefreshAttempts = 3
    private let commentRefreshDelayNanoseconds: UInt64 = 300_000_000
    private let diskCache: PullRequestDiskCache
    private var cacheMaintenance: Task<Void, Never>?
    private var accountObservation: AnyCancellable?
    private var listLoadID = UUID()
    private var detailLoadID = UUID()
    private var changesLoadID = UUID()
    private var createDraftChangesLoadID = UUID()
    private var createDraftParticipantsLoadID = UUID()

    init(
        providerAccountController: GitProviderAccountController,
        tokenVault: GitProviderTokenVault,
        services: [GitProviderKind: any PullRequestProviding],
        remoteNameProvider: @escaping (URL) async -> String? = { repositoryURL in
            let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
            return remotes.first(where: { $0 == "origin" }) ?? remotes.first
        },
        remoteURLProvider: @escaping (URL, String) async -> String? = { repositoryURL, remote in
            let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
            return remoteURL.isEmpty ? nil : remoteURL
        },
        currentBranchProvider: @escaping (URL) async -> String? = { repositoryURL in
            await GitStatusService.shared.currentBranch(in: repositoryURL)
        },
        defaultBranchProvider: @escaping (URL) async -> String? = { repositoryURL in
            let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
            guard let remote = remotes.first(where: { $0 == "origin" }) ?? remotes.first else { return nil }
            let remoteHeadRef = await GitStatusService.shared.defaultBranch(in: repositoryURL, remote: remote)
            guard let remoteHeadRef else { return nil }
            let prefix = "\(remote)/"
            if remoteHeadRef.hasPrefix(prefix) {
                return String(remoteHeadRef.dropFirst(prefix.count))
            }
            return remoteHeadRef
        },
        localBranchesProvider: @escaping (URL) async -> [String] = { repositoryURL in
            await GitStatusService.shared.cachedLocalBranches(in: repositoryURL)
        },
        remoteBranchesProvider: @escaping (URL) async -> [String] = { repositoryURL in
            let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
            let remoteBranches = await withTaskGroup(of: [String].self) { group in
                for remote in remotes {
                    group.addTask {
                        await GitStatusService.shared.cachedRemoteBranches(remote: remote, in: repositoryURL)
                    }
                }
                var result: [String] = []
                for await branches in group {
                    result.append(contentsOf: branches)
                }
                return result
            }
            return Array(Set(remoteBranches)).sorted()
        },
        changedFileCountProvider: @escaping (URL, String, String, String?) async throws -> Int = { repositoryURL, sourceBranch, targetBranch, remoteName in
            try await GitStatusService.shared.pullRequestChangedFileCount(
                sourceBranch: sourceBranch,
                targetBranch: targetBranch,
                remoteName: remoteName,
                in: repositoryURL
            )
        },
        fetchPullRequestRef: @escaping (String, String, String, URL, GitProviderCredentialResolver?) async throws -> Void = { remote, reference, localBranch, repositoryURL, credentialResolver in
            try await GitStatusService.shared.fetchPullRequestRef(
                remote: remote,
                reference: reference,
                localBranch: localBranch,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
        },
        checkoutBranch: @escaping (String, URL) async throws -> Void = { branch, repositoryURL in
            try await GitStatusService.shared.checkoutBranch(
                branch,
                inWorktree: repositoryURL,
                force: false,
                repositoryURL: repositoryURL
            )
        },
        openURL: @escaping (URL) -> Bool = { _ in false },
        diskCache: PullRequestDiskCache? = nil
    ) {
        self.providerAccountController = providerAccountController
        self.tokenVault = tokenVault
        self.services = services
        self.remoteNameProvider = remoteNameProvider
        self.remoteURLProvider = remoteURLProvider
        self.currentBranchProvider = currentBranchProvider
        self.defaultBranchProvider = defaultBranchProvider
        self.localBranchesProvider = localBranchesProvider
        self.remoteBranchesProvider = remoteBranchesProvider
        self.changedFileCountProvider = changedFileCountProvider
        self.fetchPullRequestRef = fetchPullRequestRef
        self.checkoutBranch = checkoutBranch
        self.openURL = openURL
        self.diskCache = diskCache ?? (FirebaseBootstrap.isRunningUnitTests
            ? PullRequestDiskCache(url: FileManager.default.temporaryDirectory.appending(path: "PRCacheTests-\(UUID().uuidString).sqlite"))
            : .shared)
        var previousAccounts = providerAccountController.accounts
        accountObservation = providerAccountController.$accounts.dropFirst().sink { [weak self] accounts in
            guard let self else { return }
            let removed = Set(previousAccounts.map(\.id)).subtracting(accounts.map(\.id))
            let selected = selectedProviderAccountID
            let selectedChanged = selected != nil && previousAccounts.first(where: { $0.id == selected })
                != accounts.first(where: { $0.id == selected })
            previousAccounts = accounts
            for id in removed { scheduleCacheRemoval(accountID: id) }
            if selectedChanged {
                releaseVisibleData()
                activeToken = nil
                activeRepository = nil
                selectedProviderAccountID = nil
            }
        }
    }

    var visibleItems: [PullRequestSummary] {
        items.filter { item in
            stateFilter.includes(item.state)
                && (!createdByMeOnly || item.author.username == selectedProviderAccountUsername)
        }
    }

    var selectedProviderAccountUsername: String? {
        guard let selectedProviderAccountID else { return nil }
        return providerAccountController.accounts.first { $0.id == selectedProviderAccountID }?.username
    }

    var accountConnectionProvider: GitProviderKind? {
        accountConnectionHost?.kind
    }

    var needsAccountConnectionAction: Bool {
        errorMessage == "Connect Account..." || errorMessage == "Reconnect..."
    }

    var accountConnectionActionTitle: String {
        errorMessage == "Reconnect..." ? "Reconnect" : "Connect Account"
    }

    func loadPullRequests(repositoryURL: URL, page: Int = 1, forceRefresh: Bool = false) async {
        let contextID = UUID()
        listLoadID = contextID
        activeRepositoryURL = repositoryURL
        guard let remoteName = await remoteNameProvider(repositoryURL),
              let remoteURLString = await remoteURLProvider(repositoryURL, remoteName) else {
            guard listLoadID == contextID, !Task.isCancelled else { return }
            items = []
            resetPagination()
            activeRemoteName = nil
            activeRemoteURLString = nil
            accountConnectionHost = nil
            errorMessage = "No remotes configured."
            return
        }
        guard listLoadID == contextID, !Task.isCancelled else { return }
        activeRemoteName = remoteName
        await loadPullRequests(remoteURLString: remoteURLString, page: page, forceRefresh: forceRefresh)
    }

    func loadPullRequests(
        repositoryURL: URL,
        remoteName: String,
        page: Int = 1,
        forceRefresh: Bool = false
    ) async {
        let contextID = UUID()
        listLoadID = contextID
        activeRepositoryURL = repositoryURL
        guard let remoteURLString = await remoteURLProvider(repositoryURL, remoteName) else {
            guard listLoadID == contextID, !Task.isCancelled else { return }
            items = []
            resetPagination()
            activeRemoteName = nil
            activeRemoteURLString = nil
            accountConnectionHost = nil
            errorMessage = "No remotes configured."
            return
        }
        guard listLoadID == contextID, !Task.isCancelled else { return }
        activeRemoteName = remoteName
        await loadPullRequests(remoteURLString: remoteURLString, page: page, forceRefresh: forceRefresh)
    }

    func loadPullRequests(remoteURLString: String, page: Int = 1, forceRefresh: Bool = false) async {
        let loadID = UUID()
        listLoadID = loadID
        await cacheMaintenance?.value
        guard listLoadID == loadID, !Task.isCancelled else { return }
        let cacheGeneration = await diskCache.generation()
        guard listLoadID == loadID, !Task.isCancelled else { return }
        isLoading = true
        errorMessage = nil
        accountConnectionHost = nil
        defer { if listLoadID == loadID { isLoading = false } }

        guard let remoteIdentity = GitRemoteIdentityResolver.identity(
            from: remoteURLString,
            knownGitLabHosts: connectedGitLabHosts,
            knownHosts: providerAccountController.accounts.map { GitProviderHost(kind: $0.provider, baseURL: $0.hostURL) }
        ) else {
            items = []
            resetPagination()
            selectedProviderAccountID = nil
            activeRepository = nil
            activeToken = nil
            accountConnectionHost = nil
            errorMessage = PullRequestProviderError.unsupportedProvider.localizedDescription
            return
        }

        let repository = GitRepositoryIdentity(
            provider: remoteIdentity.provider,
            hostURL: remoteIdentity.hostURL,
            owner: remoteIdentity.ownerPath,
            name: remoteIdentity.repositoryName
        )
        activeRemoteURLString = remoteURLString

        let matchingAccounts = matchingAccounts(for: repository)
        guard !matchingAccounts.isEmpty else {
            items = []
            resetPagination()
            selectedProviderAccountID = nil
            activeRepository = nil
            activeToken = nil
            accountConnectionHost = GitProviderHost(kind: repository.provider, baseURL: repository.hostURL).normalized
            errorMessage = "Connect Account..."
            return
        }

        guard let apiCredential = apiCredential(for: matchingAccounts) else {
            items = []
            resetPagination()
            selectedProviderAccountID = nil
            activeRepository = nil
            activeToken = nil
            accountConnectionHost = GitProviderHost(kind: repository.provider, baseURL: repository.hostURL).normalized
            errorMessage = matchingAccounts.contains(where: supportsProviderAPI) ? "Reconnect..." : "Connect Account..."
            return
        }
        if selectedProviderAccountID != apiCredential.account.id
            || activeRepository.map({ GitRepositoryIdentityKey($0) }) != GitRepositoryIdentityKey(repository) {
            clearSelectedDetail()
        }
        selectedProviderAccountID = apiCredential.account.id
        let token = apiCredential.token

        guard let service = services[repository.provider] else {
            items = []
            resetPagination()
            activeRepository = nil
            activeToken = nil
            accountConnectionHost = nil
            errorMessage = PullRequestProviderError.unsupportedProvider.localizedDescription
            return
        }

        activeRepository = repository
        activeToken = token
        let cacheKey = PullRequestListCacheKey(
            repository: GitRepositoryIdentityKey(repository),
            accountID: apiCredential.account.id,
            filter: stateFilter,
            page: page,
            perPage: pullRequestPageSize
        )
        if !forceRefresh,
           let cached = await diskCache.value(PullRequestListPage.self, key: cacheKey.diskKey, generation: cacheGeneration) {
            guard listLoadID == loadID, !Task.isCancelled else { return }
            apply(cached)
            accountConnectionHost = nil
            errorMessage = nil
            return
        }
        guard listLoadID == loadID, !Task.isCancelled else { return }

        do {
            let pageResult = try await service.listPullRequests(
                repository: repository,
                token: token,
                filter: cacheKey.filter,
                page: page,
                perPage: pullRequestPageSize
            )
            guard listLoadID == loadID, !Task.isCancelled else { return }
            await diskCache.save(pageResult, key: cacheKey.diskKey, accountID: cacheKey.accountID,
                                 kind: "list", ttl: listCacheTTL, generation: cacheGeneration)
            guard listLoadID == loadID, !Task.isCancelled else { return }
            apply(pageResult)
            accountConnectionHost = nil
            errorMessage = nil
        } catch let error as PullRequestProviderError {
            guard listLoadID == loadID, !Task.isCancelled else { return }
            items = []
            resetPagination()
            accountConnectionHost = nil
            errorMessage = error.localizedDescription
        } catch {
            guard listLoadID == loadID, !Task.isCancelled else { return }
            items = []
            resetPagination()
            accountConnectionHost = nil
            errorMessage = error.localizedDescription
        }
    }

    func loadPreviousPage(repositoryURL: URL) async {
        guard hasPreviousPage, currentPage > 1 else { return }
        await loadPullRequests(repositoryURL: repositoryURL, page: currentPage - 1)
    }

    func loadNextPage(repositoryURL: URL) async {
        guard hasNextPage else { return }
        await loadPullRequests(repositoryURL: repositoryURL, page: currentPage + 1)
    }

    func openInBrowser(_ summary: PullRequestSummary) {
        _ = openURL(summary.webURL)
    }

    func loadPullRequestDetail(_ summary: PullRequestSummary, forceRefresh: Bool = false) async {
        let loadID = UUID()
        detailLoadID = loadID
        await cacheMaintenance?.value
        let cacheGeneration = await diskCache.generation()
        guard detailLoadID == loadID, !Task.isCancelled else { return }
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            detailErrorMessage = "Pull request details are unavailable."
            return
        }

        isLoadingDetail = true
        detailErrorMessage = nil
        defer { if detailLoadID == loadID { isLoadingDetail = false } }

        let cacheKey = PullRequestDetailCacheKey(
            repository: GitRepositoryIdentityKey(repository),
            accountID: selectedProviderAccountID ?? "",
            number: summary.number
        )
        if !forceRefresh,
           let cached = await diskCache.value(PullRequestDetail.self, key: cacheKey.diskKey, generation: cacheGeneration) {
            guard detailLoadID == loadID, !Task.isCancelled else { return }
            selectedDetail = cached
            return
        }
        guard detailLoadID == loadID, !Task.isCancelled else { return }

        do {
            let detail = try await service.pullRequestDetail(
                repository: repository,
                token: token,
                number: summary.number
            )
            guard detailLoadID == loadID, !Task.isCancelled else { return }
            await diskCache.save(detail, key: cacheKey.diskKey, accountID: cacheKey.accountID,
                                 kind: "detail", number: cacheKey.number, ttl: detailCacheTTL, generation: cacheGeneration)
            guard detailLoadID == loadID, !Task.isCancelled else { return }
            selectedDetail = detail
        } catch {
            guard detailLoadID == loadID, !Task.isCancelled else { return }
            detailErrorMessage = error.localizedDescription
        }
    }

    func clearSelectedDetail() {
        detailLoadID = UUID()
        isLoadingDetail = false
        selectedDetail = nil
        selectedChanges = []
        changesErrorMessage = nil
        isLoadingChanges = false
        changesLoadID = UUID()
    }

    func loadPullRequestChanges(_ summary: PullRequestSummary, forceRefresh: Bool = false) async {
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            changesErrorMessage = "Pull request changes are unavailable."
            return
        }

        let loadID = UUID()
        changesLoadID = loadID
        await cacheMaintenance?.value
        let cacheGeneration = await diskCache.generation()
        guard changesLoadID == loadID, !Task.isCancelled else { return }
        isLoadingChanges = true
        changesErrorMessage = nil
        defer {
            if changesLoadID == loadID {
                isLoadingChanges = false
            }
        }

        let cacheKey = PullRequestChangesCacheKey(
            repository: GitRepositoryIdentityKey(repository),
            accountID: selectedProviderAccountID ?? "",
            number: summary.number
        )
        if !forceRefresh,
           let cached = await diskCache.value([PullRequestChangedFile].self, key: cacheKey.diskKey, generation: cacheGeneration) {
            guard changesLoadID == loadID, !Task.isCancelled,
                  selectedDetail?.summary.number == summary.number else { return }
            selectedChanges = cached
            return
        }
        guard changesLoadID == loadID, !Task.isCancelled else { return }

        do {
            let changes = try await service.pullRequestChanges(
                repository: repository,
                token: token,
                number: summary.number
            )
            guard changesLoadID == loadID, !Task.isCancelled else { return }
            await diskCache.save(changes, key: cacheKey.diskKey, accountID: cacheKey.accountID,
                                 kind: "changes", number: cacheKey.number, ttl: changesCacheTTL, generation: cacheGeneration)
            guard changesLoadID == loadID, !Task.isCancelled,
                  selectedDetail?.summary.number == summary.number else { return }
            selectedChanges = changes
        } catch {
            guard changesLoadID == loadID, !Task.isCancelled,
                  selectedDetail?.summary.number == summary.number else { return }
            changesErrorMessage = error.localizedDescription
        }
    }

    /// Loads read-only evidence for the canonical provider repository at the
    /// requested working-copy URL. Repository AI can be opened independently of
    /// the Pull Requests view, so this hydrates the existing account/repository
    /// context before reading a PR.
    func repositoryAIContext(
        number: Int?,
        repositoryURL: URL
    ) async throws -> RepositoryAIPullRequestContext {
        try await prepareRepositoryAIContext(for: repositoryURL)
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            throw RepositoryAIError.invalidResponse(errorMessage ?? "No authenticated pull request is available for this repository.")
        }
        let requestedNumber = number ?? selectedDetail?.summary.number
        guard let requestedNumber, requestedNumber > 0 else {
            throw RepositoryAIError.noRepositoryData("a selected pull request number")
        }
        return try await RepositoryAIPullRequestContextService(provider: service).load(
            repository: repository,
            token: token,
            number: requestedNumber
        )
    }

    func repositoryAIFingerprint(
        number: Int,
        repositoryURL: URL
    ) async throws -> String {
        try await prepareRepositoryAIContext(for: repositoryURL)
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            throw RepositoryAIError.invalidResponse(errorMessage ?? "No authenticated pull request is available for this repository.")
        }
        return try await RepositoryAIPullRequestContextService(provider: service).fingerprint(
            repository: repository,
            token: token,
            number: number
        )
    }

    private func prepareRepositoryAIContext(for repositoryURL: URL) async throws {
        let hasCurrentContext = activeRepositoryURL?.standardizedFileURL == repositoryURL.standardizedFileURL
            && activeRepository != nil
            && activeToken != nil
        guard !hasCurrentContext else { return }

        await loadPullRequests(repositoryURL: repositoryURL)
        guard activeRepository != nil, activeToken != nil else {
            throw RepositoryAIError.invalidResponse(errorMessage ?? "No authenticated pull request is available for this repository.")
        }
    }

    func openChangesInBrowser(_ detail: PullRequestDetail) {
        _ = openURL(detail.changesURL)
    }

    func presentCreatePullRequest(sourceBranch requestedSourceBranch: String? = nil) async {
        guard let repository = activeRepository,
              let repositoryURL = activeRepositoryURL else {
            detailErrorMessage = "Pull request creation is unavailable."
            return
        }

        let currentBranch = await currentBranchProvider(repositoryURL)
        let defaultBranch = await defaultBranchProvider(repositoryURL)
        let normalizedRequestedSource = requestedSourceBranch?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceBranch = (normalizedRequestedSource?.isEmpty == false ? normalizedRequestedSource : nil)
            ?? currentBranch
            ?? defaultBranch
        guard let sourceBranch else {
            detailErrorMessage = "No local branches are available for a pull request."
            return
        }

        createDraftSeed = PullRequestDraftSeed(
            repository: repository,
            remoteName: activeRemoteName,
            sourceBranch: sourceBranch,
            targetBranch: defaultBranch,
            suggestedTitle: suggestedTitle(for: sourceBranch)
        )
        async let participantsLoad: Void = loadCreateDraftParticipants()
        _ = await participantsLoad
    }

    func loadCreateDraftParticipants() async {
        let loadID = UUID()
        createDraftParticipantsLoadID = loadID
        createDraftParticipants = []
        createDraftParticipantsErrorMessage = nil
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            isLoadingCreateDraftParticipants = false
            return
        }

        isLoadingCreateDraftParticipants = true
        do {
            let participants = try await service.pullRequestParticipants(
                repository: repository,
                token: token
            )
            guard createDraftParticipantsLoadID == loadID else { return }
            createDraftParticipants = participants.sorted {
                $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
            }
            isLoadingCreateDraftParticipants = false
        } catch is CancellationError {
            guard createDraftParticipantsLoadID == loadID else { return }
            isLoadingCreateDraftParticipants = false
        } catch {
            guard createDraftParticipantsLoadID == loadID else { return }
            createDraftParticipantsErrorMessage = error.localizedDescription
            isLoadingCreateDraftParticipants = false
        }
    }

    func loadCreateDraftChanges(sourceBranch: String, targetBranch: String) async {
        let loadID = UUID()
        createDraftChangesLoadID = loadID
        createDraftChangedFileCount = nil
        createDraftChangesErrorMessage = nil

        guard sourceBranch != targetBranch else {
            isLoadingCreateDraftChanges = false
            createDraftChangedFileCount = 0
            return
        }
        guard let repositoryURL = activeRepositoryURL else {
            isLoadingCreateDraftChanges = false
            createDraftChangesErrorMessage = "Pull request changes are unavailable."
            return
        }

        isLoadingCreateDraftChanges = true
        do {
            let count = try await changedFileCountProvider(
                repositoryURL,
                sourceBranch,
                targetBranch,
                activeRemoteName
            )
            guard createDraftChangesLoadID == loadID else { return }
            createDraftChangedFileCount = count
            isLoadingCreateDraftChanges = false
        } catch is CancellationError {
            guard createDraftChangesLoadID == loadID else { return }
            isLoadingCreateDraftChanges = false
        } catch {
            guard createDraftChangesLoadID == loadID else { return }
            createDraftChangesErrorMessage = error.localizedDescription
            isLoadingCreateDraftChanges = false
        }
    }

    func loadCreateDraftSourceBranches(query: String) async -> [String] {
        guard let repositoryURL = activeRepositoryURL else { return [] }
        let branches = await localBranchesProvider(repositoryURL)
        return filterBranches(branches, query: query)
    }

    func loadCreateDraftTargetBranches(query: String) async -> [String] {
        guard let repositoryURL = activeRepositoryURL else { return [] }
        async let localBranches = localBranchesProvider(repositoryURL)
        async let remoteBranches = remoteBranchesProvider(repositoryURL)
        let allBranches = await Set(localBranches).union(remoteBranches)
        return filterBranches(Array(allBranches), query: query)
    }

    private func filterBranches(_ branches: [String], query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty ? branches : branches.filter {
            $0.localizedCaseInsensitiveContains(trimmed)
        }
        return filtered.filter { !$0.isEmpty }.sorted()
    }

    func resetCreateDraftChanges() {
        createDraftChangesLoadID = UUID()
        createDraftChangedFileCount = nil
        createDraftChangesErrorMessage = nil
        isLoadingCreateDraftChanges = false
    }

    func dismissCreatePullRequest() {
        createDraftChangesLoadID = UUID()
        createDraftParticipantsLoadID = UUID()
        createDraftSeed = nil
        createDraftChangedFileCount = nil
        createDraftChangesErrorMessage = nil
        isLoadingCreateDraftChanges = false
        createDraftParticipants = []
        createDraftParticipantsErrorMessage = nil
        isLoadingCreateDraftParticipants = false
    }

    func createPullRequest(_ draft: PullRequestDraft) async {
        do {
            try draft.validate()
        } catch {
            detailErrorMessage = error.localizedDescription
            return
        }
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            detailErrorMessage = "Pull request creation is unavailable."
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            var activeDraft = draft
            activeDraft.repository = repository
            let result = try await service.createPullRequest(activeDraft, token: token)
            createDraftSeed = nil
            createDraftParticipants = []
            createDraftParticipantsErrorMessage = nil
            invalidateListCache()
            if let activeRemoteURLString {
                await loadPullRequests(remoteURLString: activeRemoteURLString, page: 1, forceRefresh: true)
            }
            if !result.warnings.isEmpty {
                detailErrorMessage = "Pull request #\(result.summary.number) was created, but \(result.warnings.joined(separator: " "))"
            }
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    func comment(on pullRequest: PullRequestSummary, body: String) async {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            detailErrorMessage = "Pull request comment is required."
            return
        }
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            detailErrorMessage = "Pull request comments are unavailable."
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await service.createComment(
                body: trimmedBody,
                on: pullRequest,
                repository: repository,
                token: token
            )
            invalidateDetailCache(for: pullRequest.number)
            if selectedDetail?.summary.number == pullRequest.number {
                await refreshDetailAfterComment(pullRequest, body: trimmedBody)
            }
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    func merge(_ pullRequest: PullRequestSummary) async {
        guard pullRequest.state == .open else {
            detailErrorMessage = "Only open pull requests can be merged."
            return
        }
        guard pullRequest.mergeReadiness != .blocked else {
            detailErrorMessage = "This pull request is currently blocked from merging."
            return
        }
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            detailErrorMessage = "Pull request merging is unavailable."
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await service.mergePullRequest(
                pullRequest,
                repository: repository,
                token: token
            )
            invalidateListCache()
            invalidateDetailCache(for: pullRequest.number)
            invalidateChangesCache()
            await loadPullRequestDetail(pullRequest, forceRefresh: true)
            if let activeRemoteURLString {
                await loadPullRequests(
                    remoteURLString: activeRemoteURLString,
                    page: currentPage,
                    forceRefresh: true
                )
            }
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    private func refreshDetailAfterComment(
        _ pullRequest: PullRequestSummary,
        body: String
    ) async {
        let previousCommentIDs = Set(selectedDetail?.comments.map(\.id) ?? [])

        for attempt in 0..<commentRefreshAttempts {
            await loadPullRequestDetail(pullRequest, forceRefresh: true)

            let containsNewComment = selectedDetail?.comments.contains { comment in
                !previousCommentIDs.contains(comment.id) && comment.body == body
            } == true
            if containsNewComment || attempt == commentRefreshAttempts - 1 {
                return
            }

            try? await Task.sleep(nanoseconds: commentRefreshDelayNanoseconds)
        }
    }

    func checkout(_ pullRequest: PullRequestSummary) async {
        guard let repositoryURL = activeRepositoryURL else {
            detailErrorMessage = "Pull request checkout is unavailable."
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let localBranches = await localBranchesProvider(repositoryURL)
            if localBranches.contains(pullRequest.source.ref) {
                try await checkoutBranch(pullRequest.source.ref, repositoryURL)
                return
            }

            let branchName = "pr/\(pullRequest.number)"
            if activeRepository?.provider == .github {
                guard let activeRemoteName else {
                    throw PullRequestProviderError.providerMessage("No remotes configured.")
                }
                try await fetchPullRequestRef(
                    activeRemoteName,
                    "pull/\(pullRequest.number)/head",
                    branchName,
                    repositoryURL,
                    providerAccountController.credentialResolver()
                )
                try await checkoutBranch(branchName, repositoryURL)
                return
            }

            try await checkoutBranch(pullRequest.source.ref, repositoryURL)
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    private func matchingAccounts(for repository: GitRepositoryIdentity) -> [GitProviderAccount] {
        let repositoryHost = normalizedHost(repository.hostURL)
        return providerAccountController.accounts.filter { account in
            account.provider == repository.provider && normalizedHost(account.hostURL) == repositoryHost
        }
    }

    private func apply(_ page: PullRequestListPage) {
        items = page.items
        currentPage = page.page
        hasPreviousPage = page.hasPreviousPage
        hasNextPage = page.hasNextPage
    }

    private func invalidateListCache() {
        listLoadID = UUID()
        isLoading = false
        scheduleCacheRemoval(kind: "list")
    }

    private func invalidateDetailCache(for number: Int? = nil) {
        detailLoadID = UUID()
        isLoadingDetail = false
        scheduleCacheRemoval(kind: "detail", number: number)
    }

    private func invalidateChangesCache() {
        changesLoadID = UUID()
        isLoadingChanges = false
        scheduleCacheRemoval(kind: "changes")
    }

    private func scheduleCacheRemoval(accountID: String? = nil, kind: String? = nil, number: Int? = nil) {
        let previous = cacheMaintenance
        let cache = diskCache
        cacheMaintenance = Task {
            await previous?.value
            await cache.remove(accountID: accountID, kind: kind, number: number)
        }
    }

    func clearSessionCaches() {
        releaseVisibleData()
        scheduleCacheRemoval()
    }

    func releaseVisibleData() {
        listLoadID = UUID()
        isLoading = false
        items = []
        resetPagination()
        clearSelectedDetail()
    }

    private func apiCredential(for accounts: [GitProviderAccount]) -> (
        account: GitProviderAccount,
        token: GitProviderToken
    )? {
        let prioritizedAccounts = prioritizedAccounts(accounts)
        for account in prioritizedAccounts {
            guard supportsProviderAPI(account) else { continue }
            do {
                guard let token = try tokenVault.readToken(for: account), !token.accessToken.isEmpty else {
                    continue
                }
                return (account, token)
            } catch {
                continue
            }
        }
        return nil
    }

    private func prioritizedAccounts(_ accounts: [GitProviderAccount]) -> [GitProviderAccount] {
        guard let selectedProviderAccountID,
              let selected = accounts.first(where: { $0.id == selectedProviderAccountID }) else {
            return accounts
        }
        return [selected] + accounts.filter { $0.id != selected.id }
    }

    private func supportsProviderAPI(_ account: GitProviderAccount) -> Bool {
        account.transportProtocol == .https || account.permissions["authentication"] == "personalAccessToken" || !account.scopes.isEmpty
    }

    private func resetPagination() {
        currentPage = 1
        hasPreviousPage = false
        hasNextPage = false
    }

    private var connectedGitLabHosts: Set<String> {
        Set(providerAccountController.accounts.compactMap { account in
            guard account.provider == .gitlab else { return nil }
            return normalizedHost(account.hostURL)
        })
    }

    private func normalizedHost(_ url: URL) -> String {
        GitProviderHost.identityKey(url)
    }

    private func suggestedTitle(for branch: String) -> String {
        let branchSuffix = branch.split(separator: "/").last.map(String.init) ?? branch
        let words = branchSuffix
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { segment -> String in
                let lower = segment.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
        return words.joined(separator: " ")
    }
}
