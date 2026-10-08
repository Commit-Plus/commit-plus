// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import Combine

struct HistoryScreen: View {
    let repositoryURL: URL
    let selectedBranch: String?
    @Binding var branchFilter: HistoryBranchFilter
    @Binding var includeRemotes: Bool
    let dependencies: HistoryCommitActionController.Dependencies
    let selectionSink: HistoryCommitSelectionSink
    @EnvironmentObject private var customActionStore: CustomActionStore
    @Environment(\.appTextScale) private var textScale
    @AppStorage("advanced.historyLoadSize") private var historyLoadSizeRaw = HistoryLoadSize.balanced.rawValue
    @State private var listModel: HistoryListModel
    @State private var detailModel: HistoryCommitDetailModel
    @State private var actions: HistoryCommitActionController
    @State private var onlyThisBranch = false
    @State private var baseBranch: String?
    @State private var searchText = ""

    init(repositoryURL: URL, selectedBranch: String?, branchFilter: Binding<HistoryBranchFilter>,
         includeRemotes: Binding<Bool>, dependencies: HistoryCommitActionController.Dependencies,
         selectionSink: HistoryCommitSelectionSink) {
        self.repositoryURL = repositoryURL
        self.selectedBranch = selectedBranch
        _branchFilter = branchFilter
        _includeRemotes = includeRemotes
        self.dependencies = dependencies
        self.selectionSink = selectionSink
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
                                runOperation: dependencies.runOperation).frame(minHeight: 180)
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
        .onChange(of: branchFilter) { _, value in listModel.branchFilter = value }
        .onChange(of: onlyThisBranch) { _, value in listModel.onlyThisBranch = value }
        .onChange(of: baseBranch) { _, value in listModel.baseBranch = value }
        .onChange(of: selectedBranch) { _, value in
            listModel.selectedBranch = value
            listModel.selectBranchTipIfPossible()
        }
        .onChange(of: searchText) { _, value in listModel.setSearchText(value) }
        .onChange(of: historyLoadSizeRaw) { _, value in
            listModel.setPageSize(HistoryLoadSize(rawValue: value)?.rawValue ?? HistoryLoadSize.balanced.rawValue)
        }
        .onChange(of: listModel.selectedCommit?.hash) { _, _ in
            detailModel.show(
                listModel.selectedCommit,
                debounce: listModel.shouldDebounceDetailSelection
            )
        }
        .onChange(of: listModel.selectedHashesInDisplayOrder) { _, hashes in selectionSink.update(hashes) }
        .task(id: listModel.loadKey) { await listModel.load() }
        .onReceive(Publishers.Merge(
            NotificationCenter.default.publisher(for: .repositoryDidChange),
            NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh)
        )) { notification in
            guard notification.userInfo?["repositoryURL"] as? URL == repositoryURL else { return }
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .advancedClearSessionCaches)) { _ in refresh() }
        .onAppear {
            detailModel.resume()
            selectionSink.update(listModel.selectedHashesInDisplayOrder)
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

    private func refresh() {
        listModel.clearCache()
        Task { await listModel.refresh() }
    }
}
