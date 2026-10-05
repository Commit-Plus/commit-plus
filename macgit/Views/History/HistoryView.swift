//
//  HistoryView.swift
//  macgit
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
import Combine
import SwiftUI

struct HistoryView: View {
    @Environment(\.appTextScale) private var textScale
    private struct SquashSheetPresentation: Identifiable {
        let id = UUID()
        let commits: [Commit]
        let message: String
    }

    let repositoryURL: URL
    let selectedBranch: String?
    let undoManager: GitUndoManager?
    var syncState: SyncState? = nil
    let onRunRepositoryOperation: RepositoryOperationRunner
    let onRequestCheckout: (String, Bool) -> Void
    let onRequestExplainCommit: (Commit) -> Void
    let onRequestBrowseRevision: (Commit) -> Void
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var customActionStore: CustomActionStore
    var onCustomActionSelectionChanged: ([String]) -> Void = { _ in }
    var onRunCustomAction: (UUID, [String]) -> Void = { _, _ in }
    
    @State private var commits: [Commit] = []
    @State private var graphModel: CommitGraphModel? = nil
    @State private var graphGenerationState: CommitGraphGenerationState? = nil
    @State private var commitSelection = HistoryCommitSelection()
    @State private var activeDragCommitHashes: Set<String> = []
    @State private var activeCommitDragPayload: GitDragPayload?
    @State private var suppressedCommitClickHash: String?
    @State private var dragClickSuppressionTask: Task<Void, Never>?
    @State private var dragCompletionMonitorTask: Task<Void, Never>?
    @State private var selectedCommit: Commit? = nil
    @State private var showingCommitInfo = false
    @State private var commitPatchController = CommitPatchController()
    @State private var commitPatchReasons: [String: String] = [:]
    @State private var commitPatchEligibilityLoaded = false
    @State private var commitPatchEligibilityError: String?
    @State private var fullFilePreview: CommitFilePreviewRequest?
    @State private var previewAvailableSize = CGSize(width: 1000, height: 700)
    @State private var fullCommitMessage: String?
    @State private var isLoadingFullCommitMessage = false
    @State private var fullCommitMessageLoadID = UUID()
    @State private var commitLineCounts: [String: FileLineChangeCount] = [:]
    @State private var fileChanges: [CommitFileChange] = []
    @State private var selectedFile: CommitFileChange? = nil
    @State private var diffHunks: [DiffHunk] = []
    @State private var diffCommitHash: String?
    @State private var diffFilePath: String?
    @State private var commitFilesLoadID = UUID()
    @State private var diffLoadID = UUID()
    @AppStorage("history.tableColumns") private var tableColumnCustomization = TableColumnCustomization<HistoryTableRow>()
    @State private var tableSelection: Set<String> = []
    @State private var isRestoringTableSelection = false
    @State private var tableScrollCoordinator = HistoryTableScrollCoordinator()
    @AppStorage("advanced.historyLoadSize") private var historyLoadSizeRaw = 120
    @State private var isLoading = false
    @State private var isRefreshingHistory = false
    @State private var refreshIndicatorTask: Task<Void, Never>? = nil
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var scrollTarget: String? = nil
    @State private var paging = HistoryPagingState(pageSize: 120)
    @State private var historyCache = BoundedMemoryCache<String, HistorySnapshot>(capacity: 3)
    @State private var historySearchText = ""
    @State private var debouncedHistorySearchText = ""
    @State private var historyOnlyThisBranch = false
    @State private var historyBaseBranch: String?
    @State private var historySearchDebounceTask: Task<Void, Never>? = nil
    
    // MARK: - Context menu confirmation / sheet state
    @State private var showingResetConfirmation = false
    @State private var showingRevertConfirmation = false
    @State private var showingTagSheet = false
    @State private var showingBranchSheet = false
    @State private var tagNameInput = ""
    @State private var branchNameInput = ""
    @State private var checkoutNewBranch = true
    @State private var pendingCommit: Commit? = nil
    
    // MARK: - Checkout confirmation state
    @State private var showingCheckoutConfirmation = false
    @State private var discardLocalChanges = false
    @State private var hasUncommittedChanges = false
    @State private var resetMode: ResetMode = .mixed
    @State private var currentBranchName: String = ""
    
    // MARK: - Merge / Rebase confirmation state
    @State private var showingMergeConfirmation = false
    @State private var showingRebaseConfirmation = false
    @State private var mergeCommitImmediately = true
    @State private var mergeIncludeMessages = true
    @State private var squashSheetPresentation: SquashSheetPresentation?
    @State private var currentHeadHash: String?
    
    init(
        repositoryURL: URL,
        selectedBranch: String? = nil,
        undoManager: GitUndoManager? = nil,
        syncState: SyncState? = nil,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner = { _, operation in
            Task { await operation() }
        },
        onRequestCheckout: @escaping (String, Bool) -> Void = { _, _ in },
        onRequestExplainCommit: @escaping (Commit) -> Void = { _ in },
        onRequestBrowseRevision: @escaping (Commit) -> Void = { _ in },
        onCustomActionSelectionChanged: @escaping ([String]) -> Void = { _ in },
        onRunCustomAction: @escaping (UUID, [String]) -> Void = { _, _ in }
    ) {
        self.repositoryURL = repositoryURL
        self.selectedBranch = selectedBranch
        self.undoManager = undoManager
        self.syncState = syncState
        self.onRunRepositoryOperation = onRunRepositoryOperation
        self.onRequestCheckout = onRequestCheckout
        self.onRequestExplainCommit = onRequestExplainCommit
        self.onRequestBrowseRevision = onRequestBrowseRevision
        self.onCustomActionSelectionChanged = onCustomActionSelectionChanged
        self.onRunCustomAction = onRunCustomAction
        let storedPageSize = UserDefaults.standard.integer(forKey: "advanced.historyLoadSize")
        self._paging = State(
            initialValue: HistoryPagingState(
                pageSize: HistoryLoadSize(rawValue: storedPageSize)?.rawValue
                    ?? HistoryLoadSize.balanced.rawValue
            )
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            BranchFilterBar(
                repositoryURL: repositoryURL,
                selectedFilter: $appState.historyBranchFilter,
                includeRemotes: $appState.historyIncludeRemotes,
                onlyThisBranch: $historyOnlyThisBranch,
                baseBranch: $historyBaseBranch,
                searchText: $historySearchText
            )
            
            if isLoading && commits.isEmpty {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commits.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    message: activeHistorySearchQuery.isEmpty ? "No commits to display" : "No matching commits",
                    detail: historyEmptyDetail
                )
            } else {
                ZStack(alignment: .top) {
                    PersistentVSplit(
                        autosaveName: "HistoryMainSplit",
                        minimumTopHeight: 200,
                        minimumBottomHeight: 180,
                        top: { commitGraphList.frame(minHeight: 200) },
                        bottom: { commitDetailPanel.frame(minHeight: 180) }
                    )

                    if isRefreshingHistory {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading branch history…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                    }
                }
            }
        }
        .id("history")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedCommit) { _, newCommit in
            showingCommitInfo = false
            fullCommitMessage = nil
            isLoadingFullCommitMessage = false
            Task {
                await loadFileChanges(for: newCommit)
            }
        }
        .onChange(of: selectedFile) { _, newFile in
            Task {
                await loadDiff(for: newFile, in: selectedCommit)
            }
        }
        .onChange(of: selectedBranch) { _, newBranch in
            guard appState.historyBranchFilter == .all, let newBranch else { return }
            selectBranchTip(newBranch)
            Task {
                await tableScrollCoordinator.focusTableWhenReady()
            }
        }
        .onChange(of: historySearchText) { _, newValue in
            scheduleHistorySearchDebounce(for: newValue)
        }
        .onChange(of: historyLoadSizeRaw) { _, newValue in
            let pageSize = HistoryLoadSize(rawValue: newValue)?.rawValue
                ?? HistoryLoadSize.balanced.rawValue
            paging = HistoryPagingState(pageSize: pageSize)
            historyCache.removeAll()
        }
        .onAppear {
            tableScrollCoordinator.startContextClickMonitoring { row in
                guard commits.indices.contains(row) else { return }
                let commit = commits[row]
                guard !tableSelection.contains(commit.hash) else { return }
                commitSelection = HistoryCommitSelection(
                    selectedHashes: [commit.hash],
                    primaryHash: commit.hash,
                    anchorHash: commit.hash
                )
                selectedCommit = commit
                tableSelection = [commit.hash]
            }
        }
        .onDisappear {
            tableScrollCoordinator.stopContextClickMonitoring()
            historySearchDebounceTask?.cancel()
            dragClickSuppressionTask?.cancel()
            dragCompletionMonitorTask?.cancel()
            activeDragCommitHashes.removeAll()
        }
        .task(id: historyLoadKey) {
            await loadHistory(reset: true)
        }
        .onReceive(Publishers.Merge(
            NotificationCenter.default.publisher(for: .repositoryDidChange),
            NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh)
        )) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL,
               url == repositoryURL {
                historyCache.removeAll()
                Task {
                    await loadHistory(reset: true, preservingSelectionAndScroll: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .advancedClearSessionCaches)) { _ in
            historyCache.removeAll()
            Task {
                await loadHistory(reset: true, preservingSelectionAndScroll: true)
            }
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { size in
            previewAvailableSize = size
        }
        .replacingSheet(item: $fullFilePreview) { request in
            CommitFilePreviewSheet(request: request, availableSize: previewAvailableSize)
        }
        .replacingSheet(isPresented: $showingResetConfirmation) {
            resetSheet
        }
        .alert("Reverse this commit?", isPresented: $showingRevertConfirmation, actions: {
            Button("Cancel", role: .cancel) {}
            Button("Revert") {
                Task {
                    await performRevert()
                }
            }
        }, message: {
            Text("This will create a new commit that undoes the changes in \(pendingCommit?.shortHash ?? "").")
        })
        .replacingSheet(isPresented: $showingTagSheet) {
            tagSheet
        }
        .replacingSheet(isPresented: $showingBranchSheet) {
            branchSheet
        }
        .replacingSheet(isPresented: $showingMergeConfirmation) {
            mergeConfirmationSheet
        }
        .replacingSheet(isPresented: $showingRebaseConfirmation) {
            rebaseConfirmationSheet
        }
        .replacingSheet(item: $commitPatchController.prepared) { _ in
            // Read the live review after each resolution, not the sheet's initial item snapshot.
            if let prepared = commitPatchController.prepared {
                CommitPatchReviewSheet(prepared: prepared, isBusy: commitPatchController.isBusy,
                    errorMessage: commitPatchController.reviewError,
                    onCancel: { commitPatchController.prepared = nil },
                    onApply: {
                        commitPatchController.apply(undoManager: undoManager, syncState: syncState, run: onRunRepositoryOperation)
                    },
                    onOpenConflict: { commitPatchController.openConflict($0) })
                    .disabled(commitPatchController.isResolving)
                    .onDisappear { commitPatchController.closeConflict() }
            }
        }
        .alert("Selected changes", isPresented: $commitPatchController.showingError) {
            Button("OK", role: .cancel) {}
        } message: { Text(commitPatchController.errorMessage) }
        .replacingSheet(item: $squashSheetPresentation) { presentation in
            SquashCommitsSheet(
                commits: presentation.commits,
                initialMessage: presentation.message,
                onCancel: {
                    squashSheetPresentation = nil
                },
                onConfirm: { message in
                    let commits = presentation.commits
                    onRunRepositoryOperation("Squashing \(commits.count) commits...") {
                        await performSquash(commits: commits, message: message)
                    }
                }
            )
        }
        .replacingSheet(isPresented: $showingCheckoutConfirmation) {
            checkoutConfirmationSheet
        }
    }
    
    // MARK: - Sheets
    
    private var tagSheet: some View {
        VStack(spacing: 16) {
            Text("Create Tag")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Tag name:")
                    .font(.system(size: 13))
                TextField("Enter tag name...", text: $tagNameInput)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingTagSheet = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create Tag") {
                    onRunRepositoryOperation("Creating tag \(tagNameInput)...") {
                        await performCreateTag()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 320, idealWidth: 360)
    }
    
    private var branchSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Branch")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("From commit:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(pendingCommit?.shortHash ?? "") : \(pendingCommit?.message ?? "")")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Branch name:")
                    .font(.system(size: 13))
                TextField("Enter branch name...", text: $branchNameInput)
                    .textFieldStyle(.roundedBorder)
            }
            
            Toggle("Checkout new branch", isOn: $checkoutNewBranch)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingBranchSheet = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create Branch") {
                    onRunRepositoryOperation("Creating branch \(branchNameInput)...") {
                        await performCreateBranch()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
    
    private var resetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reset to this commit?")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("This will reset '")
                        .font(.system(size: 13))
                    Text(currentBranchName.isEmpty ? "current branch" : currentBranchName)
                        .font(.system(size: 13, weight: .bold))
                    Text("' to:")
                        .font(.system(size: 13))
                }
                Text("\(pendingCommit?.shortHash ?? "") : \(pendingCommit?.message ?? "")")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Reset mode:")
                    .font(.system(size: 13))
                
                Picker("", selection: $resetMode) {
                    Text("Soft – keep all local changes").tag(ResetMode.soft)
                    Text("Mixed – keep working copy but reset index").tag(ResetMode.mixed)
                    Text("Hard – discard all working copy changes").tag(ResetMode.hard)
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 12))
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingResetConfirmation = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Reset", role: .destructive) {
                    onRunRepositoryOperation("Resetting HEAD...") {
                        await performReset()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
    
    private var mergeConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Merge")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Are you sure you want to merge into your current branch?")
                .font(.system(size: 13))
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Commit merged changes immediately", isOn: $mergeCommitImmediately)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Toggle("Include messages from commits being merged in merge commit", isOn: $mergeIncludeMessages)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingMergeConfirmation = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("OK") {
                    onRunRepositoryOperation("Merging commit...") {
                        await performMerge()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 460)
    }
    
    private var rebaseConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Rebase")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Are you sure you want to rebase your current changes on to '\(pendingCommit?.shortHash ?? "")'?")
                .font(.system(size: 13))
            
            Text("Make sure your changes have not been pushed to anyone else.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingRebaseConfirmation = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("OK") {
                    onRunRepositoryOperation("Rebasing onto commit...") {
                        await performRebase()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }

    private var checkoutConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm change working copy")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Are you sure you want to checkout '\(pendingCommit?.shortHash ?? "")'?")
                .font(.system(size: 13))
            
            Text("Doing so will make your working copy a 'detached HEAD', which means you won't be on a branch anymore. If you want to commit after this you'll probably want to either checkout a branch again, or create a new branch. Is this ok?")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            if hasUncommittedChanges {
                Toggle("Discard local changes", isOn: $discardLocalChanges)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingCheckoutConfirmation = false
                    hasUncommittedChanges = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("OK") {
                    onRunRepositoryOperation("Checking out commit...") {
                        await performCheckoutCommit()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
    
    // MARK: - Top Panel
    
    private var commitGraphList: some View {
        Group {
            if let graphModel {
                // Fixed initial hints only; the native coordinator owns all
                // saved widths; viewport changes leave column widths unchanged.
                Table(
                    of: HistoryTableRow.self,
                    selection: commitTableSelection,
                    columnCustomization: $tableColumnCustomization
                ) {
                    TableColumn("Graph") { (row: HistoryTableRow) in
                        historyGraphTableCell(row, graphModel: graphModel)
                    }
                    .width(min: 60, ideal: 200, max: .infinity)
                    .customizationID("graph")
                    .disabledCustomizationBehavior([.reorder, .visibility])

                    TableColumn("Message") { (row: HistoryTableRow) in
                        historyMessageTableCell(row, graphModel: graphModel)
                    }
                    .width(
                        min: 120,
                        ideal: 400,
                        max: .infinity
                    )
                    .customizationID("message")
                    .disabledCustomizationBehavior([.reorder, .visibility])

                    TableColumn("Author") { (row: HistoryTableRow) in
                        historyAuthorTableCell(row)
                    }
                    .width(
                        min: 140,
                        ideal: 180,
                        max: .infinity
                    )
                    .customizationID("author")

                    TableColumn("Date") { (row: HistoryTableRow) in
                        historyDateTableCell(row)
                    }
                    .width(
                        min: 100,
                        ideal: 140,
                        max: .infinity
                    )
                    .alignment(.leading)
                    .customizationID("date")

                    TableColumn("Commit") { (row: HistoryTableRow) in
                        historyCommitTableCell(row)
                    }
                    .width(
                        min: 72,
                        ideal: 80,
                        max: .infinity
                    )
                    .alignment(.leading)
                    .customizationID("commit")
                } rows: {
                    ForEach(commits) { commit in
                        TableRow(HistoryTableRow.commit(commit))
                            .draggable(makeCommitDragPayload(startingAt: commit))
                    }
                    if paging.hasMore {
                        TableRow(HistoryTableRow.loading)
                    }
                }
                .tableStyle(.bordered)
                .alternatingRowBackgrounds(.enabled)
                .controlSize(.small)
                .contextMenu(forSelectionType: String.self) { selectedHashes in
                    let commitHashes = selectedHashes.intersection(Set(commits.map(\.hash)))
                    if !commitHashes.isEmpty, tableScrollCoordinator.allowsContextMenu {
                        commitContextMenu(for: commitHashes)
                    }
                } primaryAction: { selectedHashes in
                    handleCommitTablePrimaryAction(selectedHashes)
                }
                .onChange(of: tableSelection) { oldSelection, newSelection in
                    applyTableSelection(from: oldSelection, to: newSelection)
                    onCustomActionSelectionChanged(commits.map(\.hash).filter(newSelection.contains))
                }
                .task(id: scrollTarget) {
                    guard let scrollTarget,
                          let row = commits.firstIndex(where: { $0.hash == scrollTarget }) else {
                        return
                    }
                    await tableScrollCoordinator.scrollToRowWhenReady(row)
                    if self.scrollTarget == scrollTarget {
                        self.scrollTarget = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func historyGraphTableCell(_ row: HistoryTableRow, graphModel: CommitGraphModel) -> some View {
        if let commit = row.commit {
            commitInteractionCell(for: commit) {
                BranchGraphRowCanvas(
                    model: graphModel,
                    rowIndex: graphModel.rowIndexByHash[commit.hash] ?? 0
                )
                .opacity(activeDragCommitHashes.contains(commit.hash) ? 0.4 : 1)
            }
        }
    }

    @ViewBuilder
    private func historyMessageTableCell(_ row: HistoryTableRow, graphModel: CommitGraphModel) -> some View {
        if let commit = row.commit {
            commitInteractionCell(for: commit) {
                GeometryReader { geometry in
                    HistoryCommitMessageCell(
                        commit: commit,
                        graphColorIndex: graphModel.commitMetadata[commit.hash]?.colorIndex,
                        isDragActive: activeDragCommitHashes.contains(commit.hash),
                        scrollCoordinator: tableScrollCoordinator,
                        onAppear: {
                            handleHistoryCommitCellAppearance()
                        }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                }
                .clipped()
            }
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading older commits…")
                    .font(.caption.scaled(by: textScale))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .onAppear {
                handleHistoryCommitCellAppearance()
            }
        }
    }

    @ViewBuilder
    private func historyAuthorTableCell(_ row: HistoryTableRow) -> some View {
        if let commit = row.commit {
            commitInteractionCell(for: commit) {
                Text("\(commit.author) <\(commit.email)>")
                    .font(.callout.scaled(by: textScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("\(commit.author) <\(commit.email)>")
            }
        }
    }

    @ViewBuilder
    private func historyDateTableCell(_ row: HistoryTableRow) -> some View {
        if let commit = row.commit {
            commitInteractionCell(for: commit) {
                Text(
                    commit.date,
                    format: .dateTime
                        .hour()
                        .minute()
                        .day()
                        .month(.abbreviated)
                        .year()
                )
                .font(.callout.scaled(by: textScale))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func historyCommitTableCell(_ row: HistoryTableRow) -> some View {
        if let commit = row.commit {
            commitInteractionCell(for: commit) {
                Text(commit.shortHash)
                    .font(.callout.monospaced().scaled(by: textScale))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(commit.hash)
            }
        }
    }

    // MARK: - Bottom Panel
    
    private var commitDetailPanel: some View {
        Group {
            if let commit = selectedCommit {
                VStack(spacing: 0) {
                    // Commit info header
                    commitInfoHeader(for: commit)
                    if commitPatchController.isPreparing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Checking and merging selected changes…").font(.callout.scaled(by: textScale))
                            Spacer()
                            Button("Cancel") { commitPatchController.cancelPreparation() }
                        }
                        .padding(10)
                    }
                    
                    PersistentHSplit(
                        autosaveName: "HistoryDetailSplit",
                        minimumLeftWidth: 220,
                        minimumRightWidth: 300,
                        left: {
                            CommitFileListView(changes: fileChanges, lineCounts: commitLineCounts, selectedFile: $selectedFile,
                                onPreview: { file in
                                    fullFilePreview = CommitFilePreviewRequest(
                                        repositoryURL: repositoryURL, commitHash: commit.hash, file: file)
                                },
                                onPatch: { files, direction in
                                    commitPatchController.prepare(CommitPatchRequest(commit: commit.hash,
                                        files: files, direction: direction, lines: nil,
                                        scope: "\(files.count) selected file(s)"), in: repositoryURL)
                                },
                                patchDisabledReason: { files in commitPatchDisabledReason(for: files) })
                                .frame(minWidth: 220)
                        },
                        right: {
                            commitDiffViewer
                                .frame(minWidth: 300)
                        }
                    )
                }
            } else {
                EmptyStateView(
                    icon: "doc.text",
                    message: "Select a commit",
                    detail: "Click a commit above to see its changes"
                )
            }
        }
    }
    
    private func commitInfoHeader(for commit: Commit) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(displayCommitMessage(commit.message))
                    .font(.system(size: 13, weight: .semibold).scaled(by: textScale))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(commit.author)
                        .font(.system(size: 11).scaled(by: textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("•")
                        .font(.system(size: 11).scaled(by: textScale))
                        .foregroundStyle(.tertiary)
                    Text(commit.email)
                        .font(.system(size: 11).scaled(by: textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("•")
                        .font(.system(size: 11).scaled(by: textScale))
                        .foregroundStyle(.tertiary)
                    Text(commit.date, format: .dateTime.year().month().day().hour().minute())
                        .font(.system(size: 11).scaled(by: textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("•")
                        .font(.system(size: 11).scaled(by: textScale))
                        .foregroundStyle(.tertiary)
                    Text(commit.hash)
                        .font(.system(size: 11, design: .monospaced).scaled(by: textScale))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()

            Button("Show commit details", systemImage: "info.circle") {
                showCommitInfo(for: commit)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .padding(.trailing, 8)
            .help("Show full commit message and details")
            .accessibilityLabel("Show full commit message and details")
            .onContinuousHover(perform: updateCommitInfoCursor)
            .popover(isPresented: $showingCommitInfo, arrowEdge: .bottom) {
                CommitInfoPopoverView(
                    commit: commit,
                    fullMessage: fullCommitMessage,
                    isLoadingMessage: isLoadingFullCommitMessage,
                    onCopyMessage: {
                        copyToPasteboard(fullCommitMessage ?? commit.message)
                    },
                    onCopyHash: {
                        copyToPasteboard(commit.hash)
                    }
                )
            }
            
            if !commit.refs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(commit.refs.prefix(5), id: \.self) { ref in
                        RefLabel(text: ref)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private func displayCommitMessage(_ message: String) -> String {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "<empty message>"
            : message
    }

    private func updateCommitInfoCursor(_ phase: HoverPhase) {
        switch phase {
        case .active:
            NSCursor.pointingHand.set()
        case .ended:
            NSCursor.arrow.set()
        }
    }

    private var commitDiffViewer: some View {
        Group {
            if let file = selectedFile {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.primary)
                            .font(.system(size: 14, weight: .medium))
                        Text(file.path)
                            .font(.system(size: 13, weight: .semibold).scaled(by: textScale))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.separator)
                            .frame(height: 0.5)
                    }
                    
                    DiffView(
                        hunks: diffHunks,
                        file: nil,
                        repositoryURL: repositoryURL,
                        undoManager: nil,
                        onRefresh: {},
                        onError: { _ in },
                        filePath: file.path,
                        gitRef: selectedCommit.map(\.hash),
                        onCommitPatch: { lines, direction, scope in
                            guard let commit = selectedCommit,
                                  diffCommitHash == commit.hash, diffFilePath == file.path else { return }
                            commitPatchController.prepare(CommitPatchRequest(commit: commit.hash,
                                files: [file], direction: direction,
                                lines: Set(lines.map(CommitPatchRequest.Line.init)), scope: scope), in: repositoryURL)
                        },
                        commitPatchDisabledReason: commitPatchDisabledReason(for: [file])
                            ?? (diffCommitHash == selectedCommit?.hash && diffFilePath == file.path ? nil : "Loading commit diff…")
                    )
                }
            } else {
                EmptyStateView(
                    icon: "doc.text",
                    message: "Select a file",
                    detail: "Click a file on the left to see its diff"
                )
            }
        }
    }

    private func showCommitInfo(for commit: Commit) {
        let loadID = UUID()
        fullCommitMessageLoadID = loadID
        fullCommitMessage = nil
        isLoadingFullCommitMessage = true
        showingCommitInfo = true

        Task {
            let message = await GitStatusService.shared.fullCommitMessage(
                for: commit.hash,
                in: repositoryURL
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard fullCommitMessageLoadID == loadID,
                      selectedCommit?.hash == commit.hash else {
                    return
                }
                fullCommitMessage = message
                isLoadingFullCommitMessage = false
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
    
    // MARK: - Context Menu
    
    private func commitContextMenu(for selectedHashes: Set<String>) -> some View {
        let contextCommits = commits.filter { selectedHashes.contains($0.hash) }
        let singleCommit = contextCommits.count == 1 ? contextCommits[0] : nil
        let primaryCommit = selectedCommit.flatMap { selectedHashes.contains($0.hash) ? $0 : nil }
            ?? singleCommit
            ?? contextCommits.first
        let cherryPickCommits = Self.cherryPickCommits(from: contextCommits)
        let canCherryPick = !cherryPickCommits.isEmpty
            && cherryPickCommits.allSatisfy { !$0.isMerge }
        let squashCommits = contextCommits
        let canSquashCommits = Self.canSquashCommits(
            squashCommits,
            selectedHashes: squashCommits.map(\.hash),
            headHash: currentHeadHash
        )

        return Group {
            Button("Show Repository at Revision", systemImage: "folder") {
                guard let singleCommit else { return }
                onRequestBrowseRevision(singleCommit)
            }
            .disabled(singleCommit == nil)

            Button("Checkout Commit", systemImage: "arrow.right.to.line") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                discardLocalChanges = false
                showingCheckoutConfirmation = true
            }
            .disabled(singleCommit == nil)

            Button(
                contextCommits.count > 1 ? "Cherry Pick \(contextCommits.count) Commits" : "Cherry Pick",
                systemImage: "arrow.down.doc"
            ) {
                onRunRepositoryOperation(
                    cherryPickCommits.count == 1
                        ? "Cherry-picking \(cherryPickCommits[0].hash.prefix(7))..."
                        : "Cherry-picking \(cherryPickCommits.count) commits..."
                ) {
                    await performCherryPick(cherryPickCommits)
                }
            }
            .disabled(!canCherryPick)

            Button("AI Explain This Commit", systemImage: "sparkles") {
                guard let primaryCommit else { return }
                onRequestExplainCommit(primaryCommit)
            }
            .disabled(primaryCommit == nil)
            
            Divider()
            
            Button("Merge...", systemImage: "arrow.triangle.merge") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                mergeCommitImmediately = true
                mergeIncludeMessages = true
                showingMergeConfirmation = true
            }
            .disabled(singleCommit == nil)

            Button("Rebase...", systemImage: "arrow.triangle.swap") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                showingRebaseConfirmation = true
            }
            .disabled(singleCommit == nil)

            Divider()

            Button("Squash Commits", systemImage: "rectangle.compress.vertical") {
                squashSheetPresentation = SquashSheetPresentation(
                    commits: squashCommits,
                    message: squashCommits.map(\.message).joined(separator: "\n")
                )
            }
            .disabled(!canSquashCommits)
            
            Divider()
            
            Button("Tag...", systemImage: "tag") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                tagNameInput = ""
                showingTagSheet = true
            }
            .disabled(singleCommit == nil)

            Button("Branch...", systemImage: "arrow.triangle.branch") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                branchNameInput = ""
                checkoutNewBranch = true
                showingBranchSheet = true
            }
            .disabled(singleCommit == nil)
            
            Divider()
            
            Button("Reset to this commit", systemImage: "arrow.counterclockwise") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                resetMode = .mixed
                Task {
                    let branch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
                    await MainActor.run {
                        currentBranchName = branch
                        showingResetConfirmation = true
                    }
                }
            }
            .disabled(singleCommit == nil)

            Button("Reverse commit...", systemImage: "arrow.uturn.backward") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                showingRevertConfirmation = true
            }
            .disabled(singleCommit == nil)

            Divider()

            Menu("Custom Actions") {
                let hashes = contextCommits.map(\.hash)
                CustomActionMenuContent(
                    store: customActionStore,
                    surface: .selectedCommits,
                    context: CustomActionInvocationContext(
                        repositoryURL: repositoryURL,
                        filePaths: [],
                        commitHashes: hashes
                    ),
                    onRun: { id, _ in onRunCustomAction(id, hashes) }
                )
            }
            
            Divider()
            
            Button(
                contextCommits.count > 1 ? "Copy Hashes" : "Copy Hash",
                systemImage: "doc.on.doc"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    contextCommits.map(\.hash).joined(separator: "\n"),
                    forType: .string
                )
            }
            .disabled(contextCommits.isEmpty)

            Button(
                contextCommits.count > 1 ? "Copy Messages" : "Copy Message",
                systemImage: "doc.on.doc"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    contextCommits.map(\.message).joined(separator: "\n"),
                    forType: .string
                )
            }
            .disabled(contextCommits.isEmpty)
        }
    }
    
    // MARK: - Data Loading

    private func loadHistory(
        reset: Bool,
        preservingSelectionAndScroll: Bool = false
    ) async {
        let cacheKey = historyLoadKey
        if reset, let cached = historyCache.value(for: cacheKey) {
            isLoading = true
            defer { isLoading = false }
            let cachedHeadHash: String?
            if let resolvedHeadHash = Self.resolvedHeadHash(from: cached.commits) {
                cachedHeadHash = resolvedHeadHash
            } else {
                cachedHeadHash = await GitStatusService.shared.tipHash(
                    for: "HEAD",
                    in: repositoryURL
                )
            }
            let cachedHighlightRootHash = await Self.highlightRootHash(
                for: appState.historyBranchFilter,
                commits: cached.commits,
                repositoryURL: repositoryURL
            )
            let cachedGraphResult = await CommitGraphGenerator.generateIncrementalAsync(
                commits: cached.commits,
                highlighting: Self.highlighting(for: appState.historyBranchFilter),
                headHash: cachedHeadHash,
                highlightRootHash: cachedHighlightRootHash
            )
            guard historyLoadKey == cacheKey else { return }
            applyCachedSnapshot(
                cached,
                graphResult: cachedGraphResult,
                headHash: cachedHeadHash
            )
            return
        }

        let preservedWindow = await MainActor.run { () -> (startIndex: Int, count: Int)? in
            guard reset, preservingSelectionAndScroll else { return nil }
            return (paging.startIndex, max(paging.pageSize, paging.loadedCount))
        }

        isLoading = true
        defer { isLoading = false }
        if reset {
            await MainActor.run {
                paging.reset()
                scrollTarget = nil
                cancelHistoryRefreshIndicator()
                if commits.isEmpty {
                    graphModel = nil
                    graphGenerationState = nil
                    selectedCommit = nil
                    tableSelection = []
                    fileChanges = []
                    selectedFile = nil
                    diffHunks = []
                } else {
                    scheduleHistoryRefreshIndicator()
                }
            }
        }
        let scope = Self.historyScope(branchFilter: appState.historyBranchFilter)
        let skip = await MainActor.run {
            preservedWindow?.startIndex ?? paging.olderPageStartIndex
        }
        let pageSize = await MainActor.run { paging.pageSize }
        let loadLimit = preservedWindow?.count ?? pageSize
        let searchQuery = activeHistorySearchQuery
        let newCommits = await historyPage(
            scope: scope,
            searchQuery: searchQuery,
            limit: loadLimit,
            skip: skip
        )
        guard !Task.isCancelled, historyLoadKey == cacheKey else { return }

        let newSelectedCommit: Commit?
        let newScrollTarget: String?
        switch scope {
        case .ref:
            newSelectedCommit = newCommits.first
            newScrollTarget = newCommits.first?.hash
        case .allBranches:
            if searchQuery.isEmpty,
               let selectedBranch,
               let tipCommit = Self.tipCommit(for: selectedBranch, in: newCommits) {
                newSelectedCommit = tipCommit
                newScrollTarget = tipCommit.hash
            } else {
                newSelectedCommit = newCommits.first
                newScrollTarget = newCommits.first?.hash
            }
        case .currentBranch:
            newSelectedCommit = newCommits.first
            newScrollTarget = newCommits.first?.hash
        }

        let loadedWindow = await MainActor.run {
            let originalHashes = commits.map(\.hash)
            let combinedCommits = (reset || skip == 0)
                ? newCommits
                : commits + newCommits
            return (
                originalHashes: originalHashes,
                displayedCommits: combinedCommits
            )
        }
        let originalHashes = loadedWindow.originalHashes
        let loadedCommits = loadedWindow.displayedCommits
        let headHash: String?
        if let decoratedHead = Self.resolvedHeadHash(from: loadedCommits) {
            headHash = decoratedHead
        } else {
            headHash = await GitStatusService.shared.tipHash(
                for: "HEAD",
                in: repositoryURL
            )
        }
        await MainActor.run {
            currentHeadHash = headHash
        }
        let highlightRootHash = await Self.highlightRootHash(
            for: appState.historyBranchFilter,
            commits: loadedCommits,
            repositoryURL: repositoryURL
        )
        let highlighting = Self.highlighting(for: appState.historyBranchFilter)
        let previousGraphState = await MainActor.run { graphGenerationState }
        let incrementalGraphResult: CommitGraphGenerationResult?
        if !reset, let previousGraphState {
            incrementalGraphResult = await CommitGraphGenerator.appendAsync(
                commits: newCommits,
                to: previousGraphState,
                allCommits: loadedCommits,
                highlighting: highlighting,
                headHash: headHash,
                highlightRootHash: highlightRootHash
            )
        } else {
            incrementalGraphResult = nil
        }
        let newGraphResult: CommitGraphGenerationResult
        if let incrementalGraphResult {
            newGraphResult = incrementalGraphResult
        } else {
            newGraphResult = await CommitGraphGenerator.generateIncrementalAsync(
                commits: loadedCommits,
                highlighting: highlighting,
                headHash: headHash,
                highlightRootHash: highlightRootHash
            )
        }

        // Older pages only append rows. Keep their existing indices and let
        // the native table continue scrolling without a viewport correction.
        let viewportAnchor = await MainActor.run {
            preservingSelectionAndScroll
                ? tableScrollCoordinator.viewportAnchor(commitHashes: originalHashes)
                : nil
        }
        await MainActor.run {
            guard !Task.isCancelled,
                  historyLoadKey == cacheKey,
                  commits.map(\.hash) == originalHashes else { return }
            let pinnedSelectedCommit = selectedCommit
            let shouldPreserveTableSelection =
                (preservingSelectionAndScroll || !reset)
                && !commitSelection.selectedHashes.isEmpty
            if shouldPreserveTableSelection {
                isRestoringTableSelection = true
            }
            commits = loadedCommits
            graphModel = newGraphResult.model
            graphGenerationState = newGraphResult.state
            let visibleHashes = loadedCommits.map(\.hash)
            if reset && !preservingSelectionAndScroll {
                // A branch change must select that branch's tip, even when the
                // previously selected commit is also reachable from the new branch.
                commitSelection = HistoryCommitSelection()
            }
            let shouldSelectDefaultCommit =
                (reset && !preservingSelectionAndScroll)
                || commitSelection.selectedHashes.isEmpty
            if shouldSelectDefaultCommit, let newSelectedCommit {
                commitSelection.select(
                    newSelectedCommit.hash,
                    modifiers: [],
                    visibleHashes: visibleHashes
                )
            }
            let loadedSelectedCommit = Self.commit(
                withHash: commitSelection.primaryHash,
                in: loadedCommits
            )
            selectedCommit = loadedSelectedCommit
                ?? pinnedSelectedCommit.flatMap { pinned in
                    pinned.hash == commitSelection.primaryHash ? pinned : nil
                }
            tableSelection = Set(commitSelection.selectedHashes).intersection(visibleHashes)
            if reset && !preservingSelectionAndScroll {
                scrollTarget = Self.reloadTargetHash(
                    reset: true,
                    selectedCommitHash: selectedCommit?.hash,
                    newScrollTarget: newScrollTarget
                )
            }
            if reset {
                paging.replaceWindow(
                    startIndex: preservedWindow?.startIndex ?? 0,
                    count: newCommits.count,
                    hasMore: newCommits.count == loadLimit
                )
            } else {
                paging.finishLoadingMore(loaded: newCommits.count)
            }
            cancelHistoryRefreshIndicator()

            historyCache.insert(HistorySnapshot(
                commits: loadedCommits,
                selectedCommit: selectedCommit,
                startIndex: paging.startIndex,
                hasMore: paging.hasMore
            ), for: cacheKey)

            // Appending a page also updates the native Table's rows and can
            // transiently clear its selection, just like a background refresh.
            if shouldPreserveTableSelection {
                restoreSelectionIfTableClearsAfterReload(
                    commitSelection,
                    in: loadedCommits,
                    loadKey: cacheKey
                )
            }

            if let viewportAnchor {
                Task { @MainActor in
                    await Task.yield()
                    await tableScrollCoordinator.restoreViewportAnchor(
                        viewportAnchor,
                        commitHashes: loadedCommits.map(\.hash)
                    )
                }
            }
        }
    }

    private func restoreSelectionIfTableClearsAfterReload(
        _ selection: HistoryCommitSelection,
        in reloadedCommits: [Commit],
        loadKey: String
    ) {
        Task { @MainActor in
            await Task.yield()
            guard historyLoadKey == loadKey,
                  commits.map(\.hash) == reloadedCommits.map(\.hash) else {
                isRestoringTableSelection = false
                return
            }

            guard tableSelection.isEmpty else {
                isRestoringTableSelection = false
                return
            }

            let visibleHashes = reloadedCommits.map(\.hash)
            let visibleSelection = Set(selection.selectedHashes).intersection(visibleHashes)
            guard !visibleSelection.isEmpty else {
                isRestoringTableSelection = false
                return
            }

            commitSelection = selection
            if let loadedSelectedCommit = Self.commit(
                withHash: selection.primaryHash,
                in: reloadedCommits
            ) {
                selectedCommit = loadedSelectedCommit
            }
            tableSelection = visibleSelection
            isRestoringTableSelection = false
        }
    }

    static func canSquashCommits(
        _ selectedCommits: [Commit],
        selectedHashes: [String],
        headHash: String?
    ) -> Bool {
        guard selectedCommits.count >= 2,
              selectedCommits.count == selectedHashes.count,
              selectedCommits.first?.hash == headHash,
              selectedCommits.allSatisfy({ !$0.isMerge }) else {
            return false
        }

        return zip(selectedCommits, selectedCommits.dropFirst()).allSatisfy { newer, older in
            newer.parents.first == older.hash
        }
    }

    private func applyCachedSnapshot(
        _ snapshot: HistorySnapshot,
        graphResult cachedGraphResult: CommitGraphGenerationResult,
        headHash: String?
    ) {
        let preferredCommit = appState.historyBranchFilter == .all
            ? selectedBranch.flatMap { Self.tipCommit(for: $0, in: snapshot.commits) }
            : nil
        let snapshotSelection = preferredCommit ?? snapshot.selectedCommit

        cancelHistoryRefreshIndicator()
        paging.replaceWindow(
            startIndex: snapshot.startIndex,
            count: snapshot.commits.count,
            hasMore: snapshot.hasMore
        )
        scrollTarget = snapshot.commits.contains(where: { $0.hash == snapshotSelection?.hash })
            ? snapshotSelection?.hash
            : nil
        currentHeadHash = headHash

        commits = snapshot.commits
        graphModel = cachedGraphResult.model
        graphGenerationState = cachedGraphResult.state

        let visibleHashes = snapshot.commits.map(\.hash)
        if let cachedHash = snapshotSelection?.hash,
           snapshot.commits.contains(where: { $0.hash == cachedHash }) {
            commitSelection.select(cachedHash, modifiers: [], visibleHashes: visibleHashes)
        } else if let cachedCommit = snapshotSelection {
            commitSelection = HistoryCommitSelection(
                selectedHashes: [cachedCommit.hash],
                primaryHash: cachedCommit.hash,
                anchorHash: cachedCommit.hash
            )
        } else if commitSelection.selectedHashes.isEmpty, let first = snapshot.commits.first {
            commitSelection.select(first.hash, modifiers: [], visibleHashes: visibleHashes)
        }
        selectedCommit = Self.commit(withHash: commitSelection.primaryHash, in: snapshot.commits)
            ?? snapshotSelection
        tableSelection = Set(commitSelection.selectedHashes).intersection(visibleHashes)

        isLoading = false
        isRefreshingHistory = false
    }

    private func loadOlderHistoryIfNeeded() async {
        let shouldLoad = await MainActor.run {
            guard !isLoading else { return false }
            return paging.beginLoadingMore()
        }
        guard shouldLoad else { return }
        await loadHistory(reset: false)
    }

    private func loadNewerHistoryIfNeeded() async {
        let loadKey = historyLoadKey
        let request = await MainActor.run { () -> (startIndex: Int, count: Int, hadOlderCommits: Bool)? in
            guard !isLoading, paging.beginLoadingNewer() else { return nil }
            isLoading = true
            let startIndex = max(0, paging.startIndex - paging.pageSize)
            return (
                startIndex,
                paging.startIndex - startIndex,
                paging.hasMore
            )
        }
        guard let request else { return }
        defer {
            isLoading = false
            paging.cancelLoadingMore()
        }

        let scope = Self.historyScope(branchFilter: appState.historyBranchFilter)
        let searchQuery = activeHistorySearchQuery
        let newerCommits = await historyPage(
            scope: scope,
            searchQuery: searchQuery,
            limit: request.count,
            skip: request.startIndex
        )
        guard !Task.isCancelled, historyLoadKey == loadKey, !newerCommits.isEmpty else { return }

        let currentCommits = await MainActor.run { commits }
        var seenHashes = Set<String>()
        let combinedCommits = (newerCommits + currentCommits).filter {
            seenHashes.insert($0.hash).inserted
        }
        let loadedCommits = combinedCommits
        let headHash: String?
        if let resolvedHeadHash = Self.resolvedHeadHash(from: loadedCommits) {
            headHash = resolvedHeadHash
        } else {
            headHash = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        }
        let highlightRootHash = await Self.highlightRootHash(
            for: appState.historyBranchFilter,
            commits: loadedCommits,
            repositoryURL: repositoryURL
        )
        let newGraphResult = await CommitGraphGenerator.generateIncrementalAsync(
            commits: loadedCommits,
            highlighting: Self.highlighting(for: appState.historyBranchFilter),
            headHash: headHash,
            highlightRootHash: highlightRootHash
        )
        let viewportAnchor = await MainActor.run {
            tableScrollCoordinator.viewportAnchor(commitHashes: commits.map(\.hash))
        }

        await MainActor.run {
            guard !Task.isCancelled, historyLoadKey == loadKey else { return }
            let pinnedSelectedCommit = selectedCommit
            commits = loadedCommits
            graphModel = newGraphResult.model
            graphGenerationState = newGraphResult.state
            currentHeadHash = headHash

            let visibleHashes = loadedCommits.map(\.hash)
            let loadedSelectedCommit = Self.commit(
                withHash: commitSelection.primaryHash,
                in: loadedCommits
            )
            selectedCommit = loadedSelectedCommit
                ?? pinnedSelectedCommit.flatMap { pinned in
                    pinned.hash == commitSelection.primaryHash ? pinned : nil
                }
            tableSelection = Set(commitSelection.selectedHashes).intersection(visibleHashes)
            paging.replaceWindow(
                startIndex: request.startIndex,
                count: loadedCommits.count,
                hasMore: request.hadOlderCommits
            )

            historyCache.insert(HistorySnapshot(
                commits: loadedCommits,
                selectedCommit: selectedCommit,
                startIndex: paging.startIndex,
                hasMore: paging.hasMore
            ), for: historyLoadKey)

            if let viewportAnchor {
                Task { @MainActor in
                    await Task.yield()
                    await tableScrollCoordinator.restoreViewportAnchor(
                        viewportAnchor,
                        commitHashes: loadedCommits.map(\.hash)
                    )
                }
            }

        }
    }

    private func historyPage(
        scope: HistoryScope,
        searchQuery: String,
        limit: Int,
        skip: Int
    ) async -> [Commit] {
        let comparisonTarget: String?
        switch scope {
        case .allBranches: comparisonTarget = nil
        case .currentBranch: comparisonTarget = "HEAD"
        case .ref(let ref): comparisonTarget = ref
        }
        if historyOnlyThisBranch, let branch = comparisonTarget {
            guard let base = historyBaseBranch else { return [] }
            return await GitStatusService.shared.branchOnlyCommitHistory(
                branch: branch, base: base, query: searchQuery,
                limit: limit, skip: skip, in: repositoryURL
            )
        }
        if searchQuery.isEmpty {
            switch scope {
            case .allBranches:
                return await GitStatusService.shared.commitHistory(
                    allBranches: true,
                    limit: limit,
                    skip: skip,
                    in: repositoryURL
                )
            case .currentBranch:
                return await GitStatusService.shared.commitHistory(
                    allBranches: false,
                    limit: limit,
                    skip: skip,
                    in: repositoryURL
                )
            case .ref(let ref):
                return await GitStatusService.shared.commitHistory(
                    branch: ref,
                    limit: limit,
                    skip: skip,
                    in: repositoryURL
                )
            }
        }

        switch scope {
        case .allBranches:
            return await GitStatusService.shared.searchCommitHistory(
                allBranches: true,
                query: searchQuery,
                limit: limit,
                skip: skip,
                in: repositoryURL
            )
        case .currentBranch:
            return await GitStatusService.shared.searchCommitHistory(
                allBranches: false,
                query: searchQuery,
                limit: limit,
                skip: skip,
                in: repositoryURL
            )
        case .ref(let ref):
            return await GitStatusService.shared.searchCommitHistory(
                branch: ref,
                query: searchQuery,
                limit: limit,
                skip: skip,
                in: repositoryURL
            )
        }
    }
    
    private func loadFileChanges(for commit: Commit?) async {
        let loadID = UUID()
        await MainActor.run {
            commitFilesLoadID = loadID
            commitLineCounts = [:]
            commitPatchEligibilityLoaded = false
            commitPatchEligibilityError = nil
            commitPatchReasons = [:]
            fileChanges = []
            selectedFile = nil
            diffHunks = []
            diffLoadID = UUID()
        }

        guard let commit = commit else {
            return
        }

        async let lineCounts = try? GitStatusService.shared.commitLineChangeCounts(in: commit.hash, in: repositoryURL)
        let changes = await GitStatusService.shared.changedFiles(
            in: commit.hash,
            in: repositoryURL
        )
        await MainActor.run {
            guard commitFilesLoadID == loadID,
                  selectedCommit?.hash == commit.hash else {
                return
            }
            fileChanges = changes
            selectedFile = changes.first
        }
        let loadedLineCounts = await lineCounts
        guard commitFilesLoadID == loadID, selectedCommit?.hash == commit.hash else { return }
        commitLineCounts = loadedLineCounts ?? [:]
        do {
            let reasons = try await GitStatusService.shared.commitPatchUnavailableReasons(commit: commit.hash, in: repositoryURL)
            guard commitFilesLoadID == loadID, selectedCommit?.hash == commit.hash else { return }
            commitPatchReasons = reasons
            commitPatchEligibilityLoaded = true
        } catch {
            guard commitFilesLoadID == loadID else { return }
            commitPatchEligibilityError = error.localizedDescription
            commitPatchEligibilityLoaded = true
        }
    }

    private func commitPatchDisabledReason(for files: [CommitFileChange]) -> String? {
        if selectedCommit?.isMerge == true { return "Selected changes from merge commits are not supported." }
        if commitPatchController.isBusy { return "Preparing or applying selected changes…" }
        if !commitPatchEligibilityLoaded { return "Checking selected changes…" }
        if let commitPatchEligibilityError { return commitPatchEligibilityError }
        for file in files {
            if let reason = commitPatchReasons[file.path] ?? file.oldPath.flatMap({ commitPatchReasons[$0] }) { return reason }
        }
        return nil
    }

    private func loadDiff(for file: CommitFileChange?, in commit: Commit?) async {
        let loadID = UUID()
        await MainActor.run {
            diffLoadID = loadID
            diffHunks = []
            diffCommitHash = nil
            diffFilePath = nil
        }

        guard let file = file, let commit = commit else {
            return
        }

        let hunks = await GitStatusService.shared.diff(
            for: file.path,
            in: commit.hash,
            in: repositoryURL
        )
        await MainActor.run {
            guard diffLoadID == loadID,
                  selectedCommit?.hash == commit.hash,
                  selectedFile == file else {
                return
            }
            diffHunks = hunks
            diffCommitHash = commit.hash
            diffFilePath = file.path
        }
    }

    private var commitTableSelection: Binding<Set<String>> {
        Binding(
            get: { tableSelection },
            set: { proposedSelection in
                let newSelection = proposedSelection.intersection(Set(commits.map(\.hash)))
                guard proposedSelection.isEmpty || !newSelection.isEmpty else { return }
                // A context click on an already selected row must not dismiss
                // its detail, even if the native Table publishes an empty set.
                // Intercept the write before onChange clears commitSelection.
                if newSelection.isEmpty,
                   !tableSelection.isEmpty,
                   tableScrollCoordinator.isContextClick(onRows: IndexSet(
                    commits.indices.filter { tableSelection.contains(commits[$0].hash) }
                   )) {
                    return
                }
                tableSelection = newSelection
            }
        )
    }

    private func applyTableSelection(
        from oldSelection: Set<String>,
        to newSelection: Set<String>
    ) {
        let visibleHashes = commits.map(\.hash)
        let visibleSet = Set(visibleHashes)
        let normalizedSelection = newSelection.intersection(visibleSet)
        guard normalizedSelection == newSelection else {
            tableSelection = normalizedSelection
            return
        }

        if let primaryHash = commitSelection.primaryHash,
           !visibleSet.contains(primaryHash),
           newSelection.isSubset(of: Set(commitSelection.selectedHashes)) {
            // A window update may leave only part of a multi-selection visible.
            // Keep the off-window primary selection and its pinned detail.
            return
        }

        guard !newSelection.isEmpty else {
            guard !isRestoringTableSelection else { return }
            if let primaryHash = commitSelection.primaryHash,
               !visibleSet.contains(primaryHash) {
                // The selected commit may be outside the retained history
                // window. Keep its detail snapshot and logical selection so
                // the native row selection returns when that page is loaded.
                return
            }
            commitSelection = HistoryCommitSelection()
            selectedCommit = nil
            return
        }

        // Cell clicks have already resolved the primary commit and range anchor.
        // Keep that anchor for subsequent Shift-clicks; native keyboard selection
        // still comes through the normal reconciliation below.
        guard Set(commitSelection.selectedHashes) != newSelection else { return }

        let orderedHashes = visibleHashes.filter(newSelection.contains)
        let primaryHash = Self.primaryHashForTableSelection(
            oldSelection: oldSelection,
            newSelection: newSelection,
            previousPrimaryHash: commitSelection.primaryHash,
            visibleHashes: visibleHashes
        )
        commitSelection = HistoryCommitSelection(
            selectedHashes: orderedHashes,
            primaryHash: primaryHash,
            anchorHash: primaryHash
        )
        selectedCommit = Self.commit(withHash: primaryHash, in: commits)
    }

    private func handleCommitTablePrimaryAction(_ selectedHashes: Set<String>) {
        let primaryCommit = selectedCommit.flatMap { selectedHashes.contains($0.hash) ? $0 : nil }
            ?? commits.first(where: { selectedHashes.contains($0.hash) })
        guard let primaryCommit,
              !consumeSuppressedCommitClick(primaryCommit.hash) else {
            return
        }
        handleCommitDoubleClick(primaryCommit)
    }

    private func handleHistoryCommitCellAppearance() {
        guard !isLoading, !paging.isLoadingMore else { return }
        guard let visibleRows = tableScrollCoordinator.visibleRowRange() else { return }
        let prefetchDistance = max(paging.pageSize, visibleRows.count * 3)
        if visibleRows.lowerBound <= prefetchDistance, paging.canLoadNewer {
            Task {
                await loadNewerHistoryIfNeeded()
            }
        } else if visibleRows.upperBound >= max(0, commits.count - prefetchDistance) {
            Task {
                await loadOlderHistoryIfNeeded()
            }
        }
    }
    
    private func performCheckoutCommit() async {
        guard let commit = pendingCommit else { return }
        do {
            try await GitStatusService.shared.checkoutCommit(
                commit.hash,
                force: discardLocalChanges,
                in: repositoryURL
            )
            await MainActor.run {
                pendingCommit = nil
                discardLocalChanges = false
                hasUncommittedChanges = false
                showingCheckoutConfirmation = false
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func handleCommitDoubleClick(_ commit: Commit) {
        if let branchRef = HistoryCheckoutPolicy.branchRef(from: commit.refs) {
            onRequestCheckout(branchRef, false)
            return
        }

        pendingCommit = commit
        discardLocalChanges = false
        hasUncommittedChanges = false
        Task {
            let changeCount = await GitStatusService.shared.uncommittedChangeCount(in: repositoryURL)
            await MainActor.run {
                guard pendingCommit?.hash == commit.hash else { return }
                hasUncommittedChanges = changeCount > 0
                showingCheckoutConfirmation = true
            }
        }
    }

    private func registerHeadChangingUndo(
        label: String,
        oldHead: String?,
        redoOperation: GitUndoOperation
    ) async {
        guard let oldHead,
              let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
              oldHead != newHead else { return }

        await MainActor.run {
            undoManager?.register(
                GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: label,
                    undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                    redoOperation: redoOperation
                )
            )
        }
    }
    
    private func performCherryPick(_ commits: [Commit]) async {
        guard !commits.isEmpty else { return }
        let hashes = commits.map(\.hash)

        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.cherryPickCommits(hashes, in: repositoryURL)
            await registerHeadChangingUndo(
                label: commits.count == 1
                    ? "Cherry-pick \(commits[0].hash.prefix(7))"
                    : "Cherry-pick \(commits.count) commits",
                oldHead: oldHead,
                redoOperation: commits.count == 1
                    ? .cherryPick(commit: commits[0].hash)
                    : .cherryPickCommits(commits: hashes)
            )
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await syncState?.refresh(repositoryURL: repositoryURL)
            let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
            let inProgress = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
            await MainActor.run {
                if hasConflicts {
                    errorMessage = "Cherry-pick produced conflicts. Resolve them in the File status view, then continue or abort."
                } else if inProgress != nil {
                    errorMessage = "Cherry-pick produced an empty commit. Open the File status view to skip or abort."
                } else {
                    errorMessage = error.localizedDescription
                }
                showingError = true
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        }
    }

    private func performMerge() async {
        guard let commit = pendingCommit else { return }
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.mergeCommit(
                commit.hash,
                noCommit: !mergeCommitImmediately,
                log: mergeIncludeMessages,
                in: repositoryURL
            )
            await registerHeadChangingUndo(
                label: "Merge \(commit.hash.prefix(7))",
                oldHead: oldHead,
                redoOperation: .mergeCommit(
                    commit: commit.hash,
                    noCommit: !mergeCommitImmediately,
                    log: mergeIncludeMessages
                )
            )
            await MainActor.run {
                pendingCommit = nil
                showingMergeConfirmation = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performRebase() async {
        guard let commit = pendingCommit else { return }
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.rebaseCommit(commit.hash, in: repositoryURL)
            await registerHeadChangingUndo(
                label: "Rebase onto \(commit.hash.prefix(7))",
                oldHead: oldHead,
                redoOperation: .rebaseOnto(commit: commit.hash)
            )
            await MainActor.run {
                pendingCommit = nil
                showingRebaseConfirmation = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performReset() async {
        guard let commit = pendingCommit else { return }
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.resetToCommit(commit.hash, mode: resetMode, in: repositoryURL)
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Reset HEAD",
                            undoOperation: .resetHead(
                                target: oldHead,
                                mode: resetMode == .hard ? .hard : .soft,
                                expectedHead: newHead
                            ),
                            redoOperation: .resetHead(
                                target: commit.hash,
                                mode: resetMode.gitUndoMode,
                                expectedHead: oldHead
                            )
                        )
                    )
                }
            }
            await MainActor.run {
                pendingCommit = nil
                showingResetConfirmation = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performRevert() async {
        guard let commit = pendingCommit else { return }
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.revertCommit(commit.hash, in: repositoryURL)
            await registerHeadChangingUndo(
                label: "Revert \(commit.hash.prefix(7))",
                oldHead: oldHead,
                redoOperation: .revert(commit: commit.hash)
            )
            await MainActor.run {
                pendingCommit = nil
                showingRevertConfirmation = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await syncState?.refresh(repositoryURL: repositoryURL)
            let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
            let inProgress = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
            await MainActor.run {
                if hasConflicts {
                    errorMessage = "Revert produced conflicts. Resolve them in the File status view, then continue or abort."
                } else if inProgress != nil {
                    errorMessage = "Revert produced an empty commit. Open the File status view to skip or abort."
                } else {
                    errorMessage = error.localizedDescription
                }
                showingError = true
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        }
    }

    private func performSquash(commits: [Commit], message: String) async {
        guard Self.canSquashCommits(commits, selectedHashes: commits.map(\.hash), headHash: currentHeadHash) else {
            return
        }

        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.squashCommits(
                commits.map(\.hash),
                message: message,
                in: repositoryURL
            )
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Squash \(commits.count) commits",
                            undoOperation: .resetHead(target: oldHead, mode: .soft, expectedHead: newHead),
                            redoOperation: .commit(message: message, noVerify: false, signOff: false)
                        )
                    )
                }
            }
            await MainActor.run {
                squashSheetPresentation = nil
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performCreateTag() async {
        guard let commit = pendingCommit else { return }
        let name = tagNameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await GitStatusService.shared.createTag(
                name: name,
                commit: commit.hash,
                annotated: false,
                message: nil,
                in: repositoryURL
            )
            await MainActor.run {
                tagNameInput = ""
                pendingCommit = nil
                showingTagSheet = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performCreateBranch() async {
        guard let commit = pendingCommit else { return }
        let name = branchNameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let support = GitBranchUndoSupport()
            let startPoint = try await support.tip(of: commit.hash, in: repositoryURL)
            _ = try await GitStatusService.shared.createBranch(
                name: name,
                checkout: checkoutNewBranch,
                commit: commit.hash,
                in: repositoryURL
            )
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Create branch \(name)",
                        undoOperation: .deleteLocalBranch(name: name, force: true, expectedTip: startPoint),
                        redoOperation: .createLocalBranch(name: name, startPoint: startPoint, checkout: checkoutNewBranch)
                    )
                )
                branchNameInput = ""
                checkoutNewBranch = true
                pendingCommit = nil
                showingBranchSheet = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private var historyLoadKey: String {
        let isComparing = historyOnlyThisBranch && appState.historyBranchFilter != .all
        let comparisonKey = isComparing ? "only:\(historyBaseBranch ?? "")" : "full"
        return "\(appState.historyBranchFilter.storageValue)|\(activeHistorySearchQuery)|\(historyLoadSizeRaw)|\(comparisonKey)"
    }

    private var historyEmptyDetail: String {
        if historyOnlyThisBranch && appState.historyBranchFilter != .all {
            guard let base = historyBaseBranch else {
                return "Choose a base branch to compare against"
            }
            return activeHistorySearchQuery.isEmpty
                ? "No commits ahead of \(base)"
                : "No matching commits ahead of \(base). Try author name, email, or commit ID"
        }
        return activeHistorySearchQuery.isEmpty
            ? "Repository may be empty" : "Try author name, email, or commit ID"
    }

    private var activeHistorySearchQuery: String {
        debouncedHistorySearchText
    }

    enum HistoryScope {
        case allBranches
        case currentBranch
        case ref(String)
    }

    struct HistorySnapshot {
        let commits: [Commit]
        let selectedCommit: Commit?
        let startIndex: Int
        let hasMore: Bool
    }

    static func historyScope(branchFilter: HistoryBranchFilter) -> HistoryScope {
        switch branchFilter {
        case .all:
            return .allBranches
        case .current:
            return .currentBranch
        case .branch(let branch):
            return .ref(branch)
        }
    }

    static func reloadTargetHash(
        reset: Bool,
        selectedCommitHash: String?,
        newScrollTarget: String?
    ) -> String? {
        reset ? (newScrollTarget ?? selectedCommitHash) : selectedCommitHash
    }

    static func highlighting(
        for branchFilter: HistoryBranchFilter
    ) -> CommitGraphHighlighting {
        branchFilter == .all ? .all : .currentBranchOnly
    }

    static func highlightRootHash(
        for branchFilter: HistoryBranchFilter,
        commits: [Commit],
        repositoryURL: URL
    ) async -> String? {
        switch branchFilter {
        case .all:
            return nil
        case .current:
            if let decoratedHead = resolvedHeadHash(from: commits) {
                return decoratedHead
            }
            return await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        case .branch(let branch):
            if let tipCommit = commits.first {
                return tipCommit.hash
            }
            return await GitStatusService.shared.tipHash(for: branch, in: repositoryURL)
        }
    }

    static func selectionModifiers(from flags: NSEvent.ModifierFlags) -> HistoryCommitSelection.Modifiers {
        var modifiers: HistoryCommitSelection.Modifiers = []
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }

    static func selectCommitFromNativeTap(
        _ hash: String,
        modifierFlags: NSEvent.ModifierFlags,
        commits: [Commit],
        selection: inout HistoryCommitSelection
    ) -> Commit? {
        selection.select(
            hash,
            modifiers: selectionModifiers(from: modifierFlags),
            visibleHashes: commits.map(\.hash)
        )
        return commit(withHash: selection.primaryHash, in: commits)
    }

    static func primaryHashForTableSelection(
        oldSelection: Set<String>,
        newSelection: Set<String>,
        previousPrimaryHash: String?,
        visibleHashes: [String]
    ) -> String? {
        guard !newSelection.isEmpty else { return nil }

        let addedHashes = newSelection.subtracting(oldSelection)
        if addedHashes.count == 1 {
            return addedHashes.first
        }

        let indexByHash = Dictionary(
            uniqueKeysWithValues: visibleHashes.enumerated().map { ($0.element, $0.offset) }
        )
        if addedHashes.count > 1,
           let previousPrimaryHash,
           let previousIndex = indexByHash[previousPrimaryHash] {
            return addedHashes.max { lhs, rhs in
                abs((indexByHash[lhs] ?? previousIndex) - previousIndex)
                    < abs((indexByHash[rhs] ?? previousIndex) - previousIndex)
            }
        }

        if let previousPrimaryHash,
           newSelection.contains(previousPrimaryHash) {
            return previousPrimaryHash
        }

        return visibleHashes.last(where: newSelection.contains)
    }

    static func normalizedSearchQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return "" }
        return trimmed
    }

    private func scheduleHistorySearchDebounce(for query: String) {
        historySearchDebounceTask?.cancel()

        let normalizedQuery = Self.normalizedSearchQuery(query)
        guard !normalizedQuery.isEmpty else {
            debouncedHistorySearchText = ""
            return
        }

        historySearchDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            let debouncedQuery = Self.normalizedSearchQuery(query)
            await MainActor.run {
                debouncedHistorySearchText = debouncedQuery
            }
        }
    }

    static func resolvedHeadHash(from commits: [Commit]) -> String? {
        commits.first(where: { commit in
            commit.refs.contains {
                $0 == "HEAD" || $0.hasPrefix("HEAD -> ")
            }
        })?.hash
    }

    static func tipCommit(for branch: String, in commits: [Commit]) -> Commit? {
        commits.first { commit in
            commit.refs.contains { ref in
                ref == branch || ref == "HEAD -> \(branch)"
            }
        }
    }

    private func selectBranchTip(_ branch: String) {
        guard activeHistorySearchQuery.isEmpty,
              let commit = Self.tipCommit(for: branch, in: commits) else {
            return
        }

        let visibleHashes = commits.map(\.hash)
        commitSelection.select(commit.hash, modifiers: [], visibleHashes: visibleHashes)
        selectedCommit = commit
        tableSelection = [commit.hash]
        scrollTarget = commit.hash
    }

    static func commit(withHash hash: String?, in commits: [Commit]) -> Commit? {
        guard let hash else { return nil }
        return commits.first { $0.hash == hash }
    }

    static func contextMenuCommits(
        startingAt hash: String,
        commits: [Commit],
        selection: HistoryCommitSelection
    ) -> [Commit] {
        guard let clickedCommit = commit(withHash: hash, in: commits) else { return [] }
        guard selection.selectedHashes.contains(hash) else { return [clickedCommit] }

        let commitsByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0) })
        let selectedCommits = selection.selectedHashes.compactMap { commitsByHash[$0] }
        guard selectedCommits.count == selection.selectedHashes.count else { return [] }
        return selectedCommits
    }

    static func cherryPickCommits(from contextMenuCommits: [Commit]) -> [Commit] {
        Array(contextMenuCommits.reversed())
    }

    static func draggedCommits(
        startingAt hash: String,
        commits: [Commit],
        selection: HistoryCommitSelection
    ) -> [GitDraggedCommit] {
        let commitsByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0) })
        return selection
            .draggedHashes(startingAt: hash, visibleHashes: commits.map(\.hash))
            .compactMap { selectedHash in
                guard let commit = commitsByHash[selectedHash] else { return nil }
                return GitDraggedCommit(
                    hash: commit.hash,
                    message: commit.message,
                    isMerge: commit.isMerge
                )
            }
    }

    private func commitInteractionCell<Content: View>(
        for commit: Commit,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                selectCommitFromCell(commit)
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard !consumeSuppressedCommitClick(commit.hash) else { return }
                    handleCommitDoubleClick(commit)
                }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.pointingHand.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
            .contextMenu {
                // Cell gestures own pointer selection. Resolve the menu from
                // that selection and the clicked row, rather than the native
                // Table's contextual selection, which can include another row.
                let contextCommits = Self.contextMenuCommits(
                    startingAt: commit.hash,
                    commits: commits,
                    selection: commitSelection
                )
                if tableScrollCoordinator.allowsContextMenu {
                    commitContextMenu(for: Set(contextCommits.map(\.hash)))
                }
            }
    }

    private func selectCommitFromCell(_ commit: Commit) {
        guard !consumeSuppressedCommitClick(commit.hash) else { return }
        selectedCommit = Self.selectCommitFromNativeTap(
            commit.hash,
            modifierFlags: NSEvent.modifierFlags,
            commits: commits,
            selection: &commitSelection
        )
        tableSelection = Set(commitSelection.selectedHashes).intersection(commits.map(\.hash))
    }

    private func makeCommitDragPayload(startingAt commit: Commit) -> GitDragPayload {
        let selectionHashes: [String]
        if tableSelection.contains(commit.hash) {
            selectionHashes = commits.map(\.hash).filter(tableSelection.contains)
        } else {
            selectionHashes = [commit.hash]
        }

        let dragSelection = HistoryCommitSelection(
            selectedHashes: selectionHashes,
            primaryHash: commit.hash,
            anchorHash: commit.hash
        )
        let draggedCommits = Self.draggedCommits(
            startingAt: commit.hash,
            commits: commits,
            selection: dragSelection
        )
        let payload = GitDragPayload.commits(
            draggedCommits,
            repositoryURL: repositoryURL
        )
        GitDragPayloadStore.set(payload)
        tableScrollCoordinator.prepareDragPreview(
            CommitDragPreviewPresentation(commit: commit, commitCount: draggedCommits.count)
        )
        activeDragCommitHashes = Set(draggedCommits.map(\.hash))
        beginCommitDrag(startingAt: commit.hash, payload: payload)
        return payload
    }

    private func beginCommitDrag(startingAt hash: String, payload: GitDragPayload) {
        dragClickSuppressionTask?.cancel()
        dragCompletionMonitorTask?.cancel()
        suppressedCommitClickHash = hash
        activeCommitDragPayload = payload
        dragCompletionMonitorTask = Task {
            while NSEvent.pressedMouseButtons & 1 != 0 {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            finishCommitDrag(payload: payload, clearsPayload: false)
        }
    }

    private func finishCommitDrag(payload: GitDragPayload, clearsPayload: Bool) {
        dragCompletionMonitorTask?.cancel()
        dragCompletionMonitorTask = nil
        activeDragCommitHashes.removeAll()
        if clearsPayload {
            GitDragPayloadStore.clear(ifMatching: payload)
        }
        if activeCommitDragPayload == payload {
            activeCommitDragPayload = nil
        }
        scheduleCommitClickSuppressionClear()
    }

    private func consumeSuppressedCommitClick(_ hash: String) -> Bool {
        guard suppressedCommitClickHash == hash else { return false }
        dragClickSuppressionTask?.cancel()
        suppressedCommitClickHash = nil
        return true
    }

    private func scheduleCommitClickSuppressionClear() {
        dragClickSuppressionTask?.cancel()
        dragClickSuppressionTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            suppressedCommitClickHash = nil
        }
    }

    @MainActor
    private func scheduleHistoryRefreshIndicator() {
        refreshIndicatorTask?.cancel()
        isRefreshingHistory = false
        refreshIndicatorTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isLoading && !commits.isEmpty {
                    isRefreshingHistory = true
                }
            }
        }
    }

    @MainActor
    private func cancelHistoryRefreshIndicator() {
        refreshIndicatorTask?.cancel()
        refreshIndicatorTask = nil
        isRefreshingHistory = false
    }
}

private extension ResetMode {
    var gitUndoMode: GitUndoResetMode {
        switch self {
        case .soft: return .soft
        case .mixed: return .mixed
        case .hard: return .hard
        }
    }
}
