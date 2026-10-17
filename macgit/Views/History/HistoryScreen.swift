// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import Combine

struct HistoryScreen: View {
    let repositoryURL: URL
    let isActive: Bool
    let isWorkSuspended: Bool
    let selectedBranch: String?
    @Binding var branchFilter: HistoryBranchFilter
    @Binding var includeRemotes: Bool
    let dependencies: HistoryCommitActionController.Dependencies
    let selectionSink: HistoryCommitSelectionSink
    let onOpenFile: (String) -> Void
    @EnvironmentObject private var customActionStore: CustomActionStore
    @Environment(\.appTextScale) private var textScale
    @AppStorage("advanced.historyLoadSize") private var historyLoadSizeRaw = HistoryLoadSize.balanced.rawValue
    @State private var listModel: HistoryListModel
    @State private var detailModel: HistoryCommitDetailModel
    @State private var actions: HistoryCommitActionController
    @State private var onlyThisBranch = false
    @State private var baseBranch: String?
    @State private var searchText = ""
    @State private var needsRefresh = true
    @State private var historyCommitSetFingerprint: String?
    @State private var resolvedReference: String?

    init(repositoryURL: URL, isActive: Bool, isWorkSuspended: Bool = false, selectedBranch: String?, branchFilter: Binding<HistoryBranchFilter>,
         includeRemotes: Binding<Bool>, dependencies: HistoryCommitActionController.Dependencies,
         selectionSink: HistoryCommitSelectionSink, onOpenFile: @escaping (String) -> Void) {
        self.repositoryURL = repositoryURL
        self.isActive = isActive
        self.isWorkSuspended = isWorkSuspended
        self.selectedBranch = selectedBranch
        _resolvedReference = State(initialValue: selectedBranch)
        _branchFilter = branchFilter
        _includeRemotes = includeRemotes
        self.dependencies = dependencies
        self.selectionSink = selectionSink
        self.onOpenFile = onOpenFile
        let storedSize = UserDefaults.standard.integer(forKey: "advanced.historyLoadSize")
        let list = HistoryListModel(repositoryURL: repositoryURL, branchFilter: branchFilter.wrappedValue,
            selectedBranch: selectedBranch,
            pageSize: HistoryLoadSize(rawValue: storedSize)?.rawValue ?? HistoryLoadSize.balanced.rawValue)
        _listModel = State(initialValue: list)
        _detailModel = State(initialValue: HistoryCommitDetailModel(repositoryURL: repositoryURL))
        _actions = State(initialValue: HistoryCommitActionController(dependencies: dependencies))
    }

    var body: some View {
        let _ = actions.dependencies = HistoryCommitActionController.Dependencies(
            repositoryURL: repositoryURL, undoManager: dependencies.undoManager, syncState: dependencies.syncState,
            runOperation: dependencies.runOperation, requestCheckout: dependencies.requestCheckout,
            requestExplain: dependencies.requestExplain, requestBrowseRevision: dependencies.requestBrowseRevision,
            runCustomAction: dependencies.runCustomAction, headHash: { listModel.headHash })
        historyLifecycle
    }

    private var historyLayout: some View {
        VStack(spacing: 0) {
            BranchFilterBar(repositoryURL: repositoryURL, selectedFilter: $branchFilter,
                includeRemotes: $includeRemotes, onlyThisBranch: $onlyThisBranch,
                baseBranch: $baseBranch, searchText: $searchText)
            if listModel.phase == .initialLoading && listModel.rows.commits.isEmpty && listModel.selectedCommit == nil {
                ProgressView("Loading history…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if listModel.rows.commits.isEmpty && listModel.selectedCommit == nil {
                EmptyStateView(icon: "clock.arrow.circlepath",
                    message: listModel.activeSearchQuery.isEmpty ? "No commits to display" : "No matching commits",
                    detail: HistoryLoadPolicy.emptyDetail(onlyThisBranch: onlyThisBranch, filter: branchFilter,
                        baseBranch: baseBranch, searchQuery: listModel.activeSearchQuery))
            } else {
                ZStack(alignment: .top) {
                    PersistentVSplit(autosaveName: "HistoryMainSplit", minimumTopHeight: 200,
                        minimumBottomHeight: 180,
                        top: {
                            Group {
                                if listModel.rows.commits.isEmpty {
                                    if listModel.phase == .initialLoading {
                                        ProgressView("Loading history…")
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else {
                                        EmptyStateView(icon: "clock.arrow.circlepath",
                                            message: listModel.activeSearchQuery.isEmpty ? "No commits to display" : "No matching commits",
                                            detail: HistoryLoadPolicy.emptyDetail(onlyThisBranch: onlyThisBranch, filter: branchFilter,
                                                baseBranch: baseBranch, searchQuery: listModel.activeSearchQuery))
                                    }
                                } else {
                                    HistoryCommitTable(listModel: listModel, actions: actions,
                                        customActionStore: customActionStore, repositoryURL: repositoryURL,
                                        textScale: textScale)
                                }
                            }
                            .frame(minHeight: 200)
                        }, bottom: {
                            HistoryCommitDetailView(model: detailModel, repositoryURL: repositoryURL,
                                undoManager: dependencies.undoManager, syncState: dependencies.syncState,
                                runOperation: dependencies.runOperation, onOpenFile: onOpenFile).frame(minHeight: 180)
                        })
                    if listModel.phase == .refreshing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading branch history…").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule()).padding(.top, 8)
                    }
                }
            }
        }
        .id("history")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var historySelection: some View {
        historyLayout
        .onChange(of: branchFilter) { _, value in listModel.branchFilter = value }
        .onChange(of: onlyThisBranch) { _, value in listModel.onlyThisBranch = value }
        .onChange(of: baseBranch) { _, value in listModel.baseBranch = value }
        .onChange(of: selectedBranch) { _, reference in
            listModel.selectedBranch = reference
            guard let reference, listModel.selectReferenceTipIfLoaded(reference) else { return }
            resolvedReference = reference
        }
        .task(id: ReferenceSelectionRequest(reference: selectedBranch, active: isActive, suspended: isWorkSuspended)) {
            guard isActive, !isWorkSuspended else { return }
            listModel.selectedBranch = selectedBranch
            guard selectedBranch != resolvedReference else { return }
            guard let reference = selectedBranch else {
                resolvedReference = nil
                return
            }
            let selectedLoadedTip = await listModel.resolveReferenceTipIfLoaded(reference)
            guard !Task.isCancelled else { return }
            resolvedReference = reference
            if !selectedLoadedTip, branchFilter == .all { branchFilter = .branch(reference) }
        }
        .onChange(of: searchText) { _, value in listModel.setSearchText(value) }
        .onChange(of: historyLoadSizeRaw) { _, value in
            listModel.setPageSize(HistoryLoadSize(rawValue: value)?.rawValue ?? HistoryLoadSize.balanced.rawValue)
        }
        .onChange(of: listModel.selectedCommit?.hash) { _, _ in
            guard !isWorkSuspended else { return }
            detailModel.show(
                listModel.selectedCommit,
                debounce: listModel.shouldDebounceDetailSelection
            )
        }
        .onChange(of: listModel.selectedHashesInDisplayOrder) { _, hashes in selectionSink.update(hashes) }
        .task(id: HistoryLoadRequest(key: listModel.loadKey, suspended: isWorkSuspended)) {
            guard isActive, !isWorkSuspended else {
                needsRefresh = true
                return
            }
            await listModel.load()
            guard !Task.isCancelled else { return }
            historyCommitSetFingerprint = await GitStatusService.shared.historyCommitSetFingerprint(
                in: repositoryURL
            )
            guard !Task.isCancelled else { return }
            needsRefresh = false
        }
    }

    private var historyLifecycle: some View {
        historySelection
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            guard notification.userInfo?["repositoryURL"] as? URL == repositoryURL else { return }
            requestRefreshIfCommitSetChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryRemoteRefsDidRefresh)) { notification in
            guard notification.userInfo?["repositoryURL"] as? URL == repositoryURL else { return }
            requestRefreshIfCommitSetChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .advancedClearSessionCaches)) { _ in
            listModel.clearCache()
            requestRefresh()
        }
        .onChange(of: isWorkSuspended) { _, suspended in
            if suspended {
                listModel.suspendLoading()
                detailModel.suspend()
            } else if isActive {
                detailModel.show(listModel.selectedCommit, debounce: false)
                detailModel.resume()
            }
        }
        .onChange(of: isActive) { _, active in
            if active && !isWorkSuspended {
                detailModel.resume()
                selectionSink.update(listModel.selectedHashesInDisplayOrder)
                if needsRefresh { requestRefresh() }
            } else {
                detailModel.suspend()
                listModel.cancelSearchDebounce()
                selectionSink.update([])
            }
        }
        .onAppear {
            if isActive && !isWorkSuspended {
                detailModel.resume()
                selectionSink.update(listModel.selectedHashesInDisplayOrder)
            } else {
                detailModel.suspend()
            }
            listModel.setSearchText(searchText)
        }
        .onDisappear {
            detailModel.suspend()
            listModel.cancelSearchDebounce()
            selectionSink.update([])
        }
        .historyActionPresentations(actions)
        .alert("Error", isPresented: Binding(
            get: { listModel.errorMessage != nil },
            set: { if !$0 { listModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { listModel.errorMessage = nil }
        } message: { Text(listModel.errorMessage ?? "") }
    }

    private struct ReferenceSelectionRequest: Equatable {
        let reference: String?
        let active: Bool
        let suspended: Bool
    }

    private struct HistoryLoadRequest: Equatable {
        let key: String
        let suspended: Bool
    }

    private func requestRefresh() {
        needsRefresh = true
        guard isActive, !isWorkSuspended else { return }
        Task {
            await listModel.refresh()
            guard !Task.isCancelled else { return }
            needsRefresh = false
        }
    }

    private func requestRefreshIfCommitSetChanged() {
        Task {
            let fingerprint = await GitStatusService.shared.historyCommitSetFingerprint(in: repositoryURL)
            guard !Task.isCancelled else { return }
            guard historyCommitSetFingerprint != fingerprint else {
                if isActive && !isWorkSuspended {
                    await listModel.refreshRebaseAvailability()
                } else {
                    needsRefresh = true
                }
                return
            }
            historyCommitSetFingerprint = fingerprint
            needsRefresh = true
            if isActive { requestRefresh() }
        }
    }
}
