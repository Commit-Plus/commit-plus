// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

struct HistoryRows {
    enum Change {
        case reload(preserveViewport: Bool)
        case appended(Range<Int>)
    }

    let commits: [Commit]
    let graphModel: CommitGraphModel?
    let hasMore: Bool
    let version: Int
    let change: Change
    let indexByHash: [String: Int]
}

struct HistoryScrollRequest: Equatable {
    let hash: String
    let focus: Bool
    let token: UUID
}

@Observable @MainActor
final class HistoryListModel {
    enum Phase { case initialLoading, idle, refreshing }

    var repositoryURL: URL {
        didSet {
            guard repositoryURL != oldValue else { return }
            clearCache()
            cancelSearchDebounce()
            invalidateLoad()
            publishedKey = nil
        }
    }
    var branchFilter: HistoryBranchFilter { didSet { if branchFilter != oldValue { invalidateLoad() } } }
    var onlyThisBranch: Bool {
        didSet { if onlyThisBranch != oldValue, branchFilter != .all { invalidateLoad() } }
    }
    var baseBranch: String? {
        didSet { if baseBranch != oldValue, onlyThisBranch, branchFilter != .all { invalidateLoad() } }
    }
    var selectedBranch: String?
    private(set) var activeSearchQuery = ""
    private(set) var rows = HistoryRows(
        commits: [], graphModel: nil, hasMore: true, version: 0,
        change: .reload(preserveViewport: false), indexByHash: [:]
    )
    private(set) var selection = HistoryCommitSelection()
    private(set) var selectedCommit: Commit?
    private(set) var shouldDebounceDetailSelection = false
    private(set) var headHash: String?
    private(set) var phase: Phase = .idle
    private(set) var scrollRequest: HistoryScrollRequest?
    private(set) var dragActiveHashes: Set<String> = []
    var errorMessage: String?

    @ObservationIgnored private var paging: HistoryPagingState
    @ObservationIgnored private var graphState: CommitGraphGenerationState?
    @ObservationIgnored private var graphRootHash: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var publishedKey: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var indicatorTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var displayHashes: [String] = []
    @ObservationIgnored private var branchTips: [String: String] = [:]
    @ObservationIgnored private var cache = BoundedMemoryCache<String, Snapshot>(capacity: 3)

    private struct Snapshot {
        let commits: [Commit]
        let selectedCommit: Commit?
        let hasMore: Bool
    }

    private struct Request {
        let key: String
        let generation: UUID
        let repositoryURL: URL
        let filter: HistoryBranchFilter
        let query: String
        let onlyThisBranch: Bool
        let base: String?
    }

    init(
        repositoryURL: URL,
        branchFilter: HistoryBranchFilter = .all,
        onlyThisBranch: Bool = false,
        baseBranch: String? = nil,
        selectedBranch: String? = nil,
        pageSize: Int = HistoryLoadSize.balanced.rawValue
    ) {
        self.repositoryURL = repositoryURL
        self.branchFilter = branchFilter
        self.onlyThisBranch = onlyThisBranch
        self.baseBranch = baseBranch
        self.selectedBranch = selectedBranch
        self.pageSize = max(1, pageSize)
        paging = HistoryPagingState(pageSize: max(1, pageSize))
    }

    var loadKey: String {
        // Repository identity prevents a reused screen from keeping an old .task.
        repositoryURL.absoluteString + "|" + HistoryLoadPolicy.loadKey(
            filter: branchFilter, searchQuery: activeSearchQuery, pageSize: pageSize,
            onlyThisBranch: onlyThisBranch, baseBranch: baseBranch
        )
    }

    var selectedHashesInDisplayOrder: [String] {
        selection.selectedHashes.filter { rows.indexByHash[$0] != nil }.sorted {
            (rows.indexByHash[$0] ?? 0) < (rows.indexByHash[$1] ?? 0)
        }
    }

    func load() async { await reload(preservingSelection: false) }

    func refresh() async {
        clearCache()
        await reload(preservingSelection: publishedKey == loadKey)
    }

    private func reload(preservingSelection: Bool) async {
        guard !Task.isCancelled else { return }
        invalidateLoad()
        let request = currentRequest()
        let limit = preservingSelection ? max(paging.pageSize, rows.commits.count) : paging.pageSize
        let snapshot = preservingSelection ? nil : cache.value(for: request.key)
        isLoading = true
        phase = rows.commits.isEmpty ? .initialLoading : .idle
        if !rows.commits.isEmpty {
            indicatorTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard let self, self.isCurrent(request), self.isLoading else { return }
                self.phase = .refreshing
            }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.finishLoad(request) }
            let commits: [Commit]
            if let snapshot { commits = snapshot.commits }
            else { commits = await self.historyPage(request, limit: limit, skip: 0) }
            guard self.isCurrent(request) else { return }
            let head = await self.resolveHead(commits, request: request)
            let root = await HistoryLoadPolicy.highlightRootHash(
                for: request.filter, commits: commits, repositoryURL: request.repositoryURL
            )
            guard self.isCurrent(request) else { return }
            let graph = await CommitGraphGenerator.generateIncrementalAsync(
                commits: commits, highlighting: HistoryLoadPolicy.highlighting(for: request.filter),
                headHash: head, highlightRootHash: root
            )
            guard self.isCurrent(request) else { return }
            let previousCommit = self.selectedCommit
            self.publish(commits: commits, graphResult: graph,
                         hasMore: snapshot?.hasMore ?? (commits.count == limit),
                         change: .reload(preserveViewport: preservingSelection), head: head, root: root)
            if preservingSelection {
                self.preserveSelection(pinned: previousCommit)
            } else {
                let tip = request.filter == .all && (snapshot != nil || request.query.isEmpty)
                    ? self.selectedBranch.flatMap { self.branchTips[$0] }.flatMap(self.commit) : nil
                self.select(snapshot?.selectedCommit.flatMap { self.commit($0.hash) ?? $0 } ?? tip ?? commits.first,
                            focus: false)
            }
            self.storeSnapshot()
        }
        loadTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func loadMoreIfNeeded(lastVisibleRow: Int, visibleCount: Int) {
        guard !isLoading, publishedKey == loadKey, lastVisibleRow >= 0,
              lastVisibleRow >= max(0, rows.commits.count - max(paging.pageSize, visibleCount * 3)),
              let previousState = graphState, paging.beginLoadingMore() else { return }
        let request = currentRequest()
        let oldRows = rows
        let limit = paging.pageSize
        let oldHead = headHash
        let oldRoot = graphRootHash
        pageTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == request.generation { self.paging.cancelLoadingMore(); self.pageTask = nil }
            }
            let page = await self.historyPage(request, limit: limit, skip: oldRows.commits.count)
            guard self.isCurrent(request), self.rows.version == oldRows.version else { return }
            let commits = oldRows.commits + page
            let appended = await CommitGraphGenerator.appendAsync(
                commits: page, to: previousState, allCommits: commits,
                highlighting: HistoryLoadPolicy.highlighting(for: request.filter),
                headHash: oldHead, highlightRootHash: oldRoot
            )
            let graph: CommitGraphGenerationResult
            if let appended { graph = appended }
            else {
                graph = await CommitGraphGenerator.generateIncrementalAsync(
                    commits: commits, highlighting: HistoryLoadPolicy.highlighting(for: request.filter),
                    headHash: oldHead, highlightRootHash: oldRoot
                )
            }
            guard self.isCurrent(request), self.rows.version == oldRows.version else { return }
            self.publish(commits: commits, graphResult: graph, hasMore: page.count == limit,
                         change: .appended(oldRows.commits.count..<commits.count), head: oldHead, root: oldRoot)
        }
    }

    func setSearchText(_ text: String) {
        cancelSearchDebounce()
        let query = HistoryLoadPolicy.normalizedSearchQuery(text)
        guard !query.isEmpty else { applySearchQuery(""); return }
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.applySearchQuery(query)
        }
    }

    func cancelSearchDebounce() { searchTask?.cancel(); searchTask = nil }

    private func applySearchQuery(_ query: String) {
        guard query != activeSearchQuery else { return }
        activeSearchQuery = query
        invalidateLoad()
    }

    func applyTableSelection(orderedHashes: [String], debounceDetail: Bool = false) {
        let hashes = orderedHashes.filter { rows.indexByHash[$0] != nil }
        let newSet = Set(hashes)
        let oldSet = Set(selection.selectedHashes)
        if newSet.isEmpty {
            shouldDebounceDetailSelection = false
            selection = HistoryCommitSelection()
            selectedCommit = nil
            storeSnapshot()
            return
        }
        guard newSet != oldSet else { return }
        let primary = HistoryLoadPolicy.primaryHashForTableSelection(
            oldSelection: oldSet, newSelection: newSet, previousPrimaryHash: selection.primaryHash,
            visibleHashes: displayHashes
        )
        shouldDebounceDetailSelection = debounceDetail
        selection = HistoryCommitSelection(selectedHashes: hashes, primaryHash: primary, anchorHash: primary)
        selectedCommit = primary.flatMap(commit)
        storeSnapshot()
    }

    func selectBranchTipIfPossible() {
        guard branchFilter == .all, activeSearchQuery.isEmpty, publishedKey == loadKey,
              let selectedBranch, let hash = branchTips[selectedBranch], let tip = commit(hash) else { return }
        select(tip, focus: true)
        storeSnapshot()
    }

    func clearCache() { cache.removeAll() }

    func setPageSize(_ size: Int) {
        let size = max(1, size)
        guard size != paging.pageSize else { return }
        paging = HistoryPagingState(pageSize: size)
        clearCache()
        invalidateLoad()
        // paging is ignored; changing this observed value invalidates loadKey readers.
        pageSize = size
    }

    // Observable backing value makes setting page size restart the screen's .task.
    private var pageSize: Int = HistoryLoadSize.balanced.rawValue

    func setDragActive(_ hashes: Set<String>) { dragActiveHashes = hashes }
    func consumeScrollRequest(_ token: UUID) {
        if scrollRequest?.token == token { scrollRequest = nil }
    }

    private func currentRequest() -> Request {
        Request(key: loadKey, generation: generation, repositoryURL: repositoryURL,
                filter: branchFilter, query: activeSearchQuery, onlyThisBranch: onlyThisBranch, base: baseBranch)
    }

    private func isCurrent(_ request: Request) -> Bool {
        !Task.isCancelled && generation == request.generation && loadKey == request.key
            && repositoryURL == request.repositoryURL
    }

    private func invalidateLoad() {
        generation = UUID()
        loadTask?.cancel(); loadTask = nil
        pageTask?.cancel(); pageTask = nil
        indicatorTask?.cancel(); indicatorTask = nil
        paging.cancelLoadingMore()
        isLoading = false
        phase = .idle
    }

    private func finishLoad(_ request: Request) {
        guard generation == request.generation else { return }
        indicatorTask?.cancel(); indicatorTask = nil
        loadTask = nil
        isLoading = false
        phase = .idle
    }

    private func publish(commits: [Commit], graphResult: CommitGraphGenerationResult,
                         hasMore: Bool, change: HistoryRows.Change, head: String?, root: String?) {
        var index: [String: Int] = [:]
        var tips: [String: String] = [:]
        for (offset, commit) in commits.enumerated() {
            index[commit.hash] = offset
            for ref in commit.refs {
                let name = ref.hasPrefix("HEAD -> ") ? String(ref.dropFirst(8)) : ref
                if tips[name] == nil { tips[name] = commit.hash }
            }
        }
        displayHashes = commits.map(\.hash)
        branchTips = tips
        graphState = graphResult.state
        graphRootHash = root
        headHash = head
        paging.replaceLoadedHistory(count: commits.count, hasMore: hasMore)
        publishedKey = loadKey
        rows = HistoryRows(commits: commits, graphModel: graphResult.model, hasMore: hasMore,
                           version: rows.version + 1, change: change, indexByHash: index)
        storeSnapshot()
    }

    private func commit(_ hash: String) -> Commit? {
        guard let index = rows.indexByHash[hash] else { return nil }
        return rows.commits[index]
    }

    private func select(_ commit: Commit?, focus: Bool) {
        shouldDebounceDetailSelection = false
        selectedCommit = commit
        let loadedCommit = commit.flatMap { rows.indexByHash[$0.hash] == nil ? nil : $0 }
        selection = HistoryCommitSelection(selectedHashes: loadedCommit.map { [$0.hash] } ?? [],
                                           primaryHash: loadedCommit?.hash, anchorHash: loadedCommit?.hash)
        scrollRequest = loadedCommit.map { HistoryScrollRequest(hash: $0.hash, focus: focus, token: UUID()) }
    }

    private func preserveSelection(pinned: Commit?) {
        let hashes = selectedHashesInDisplayOrder
        let primary = selection.primaryHash.flatMap(commit)
        let anchor = selection.anchorHash.flatMap { rows.indexByHash[$0] == nil ? nil : $0 }
        selection = HistoryCommitSelection(selectedHashes: hashes, primaryHash: primary?.hash,
                                           anchorHash: anchor)
        selectedCommit = primary ?? pinned
        scrollRequest = nil
    }

    private func storeSnapshot() {
        guard publishedKey == loadKey else { return }
        cache.insert(Snapshot(commits: rows.commits, selectedCommit: selectedCommit, hasMore: rows.hasMore),
                     for: loadKey)
    }

    private func resolveHead(_ commits: [Commit], request: Request) async -> String? {
        if let head = HistoryLoadPolicy.resolvedHeadHash(from: commits) { return head }
        return await GitStatusService.shared.tipHash(for: "HEAD", in: request.repositoryURL)
    }

    private func historyPage(_ request: Request, limit: Int, skip: Int) async -> [Commit] {
        let scope = HistoryLoadPolicy.historyScope(branchFilter: request.filter)
        let service = GitStatusService.shared
        if request.onlyThisBranch, request.filter != .all {
            guard let base = request.base else { return [] }
            let branch: String
            if case .ref(let ref) = scope { branch = ref } else { branch = "HEAD" }
            return await service.branchOnlyCommitHistory(branch: branch, base: base, query: request.query,
                                                        limit: limit, skip: skip, in: request.repositoryURL)
        }
        if case .ref(let ref) = scope {
            if request.query.isEmpty {
                return await service.commitHistory(branch: ref, limit: limit, skip: skip, in: request.repositoryURL)
            }
            return await service.searchCommitHistory(branch: ref, query: request.query,
                                                     limit: limit, skip: skip, in: request.repositoryURL)
        }
        let allBranches = request.filter == .all
        if request.query.isEmpty {
            return await service.commitHistory(allBranches: allBranches, limit: limit, skip: skip,
                                               in: request.repositoryURL)
        }
        return await service.searchCommitHistory(allBranches: allBranches, query: request.query,
                                                 limit: limit, skip: skip, in: request.repositoryURL)
    }
}
