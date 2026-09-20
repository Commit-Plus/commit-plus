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
import CoreTransferable
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
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
    @EnvironmentObject private var appState: AppState
    
    @State private var commits: [Commit] = []
    @State private var graphModel: CommitGraphModel? = nil
    @State private var commitSelection = HistoryCommitSelection()
    @State private var activeDragCommitHashes: Set<String> = []
    @State private var activeCommitDragPayload: GitDragPayload?
    @State private var suppressedCommitClickHash: String?
    @State private var dragClickSuppressionTask: Task<Void, Never>?
    @State private var dragCompletionMonitorTask: Task<Void, Never>?
    @State private var selectedCommit: Commit? = nil
    @State private var showingCommitInfo = false
    @State private var fullFilePreview: CommitFilePreviewRequest?
    @State private var previewAvailableSize = CGSize(width: 1000, height: 700)
    @State private var fullCommitMessage: String?
    @State private var isLoadingFullCommitMessage = false
    @State private var fullCommitMessageLoadID = UUID()
    @State private var fileChanges: [CommitFileChange] = []
    @State private var selectedFile: CommitFileChange? = nil
    @State private var diffHunks: [DiffHunk] = []
    @State private var commitFilesLoadID = UUID()
    @State private var diffLoadID = UUID()
    @AppStorage("history.tableColumns") private var tableColumnCustomization = TableColumnCustomization<Commit>()
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
    @State private var historyCache: [String: HistorySnapshot] = [:]
    @State private var historySearchText = ""
    @State private var debouncedHistorySearchText = ""
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
        onRequestExplainCommit: @escaping (Commit) -> Void = { _ in }
    ) {
        self.repositoryURL = repositoryURL
        self.selectedBranch = selectedBranch
        self.undoManager = undoManager
        self.syncState = syncState
        self.onRunRepositoryOperation = onRunRepositoryOperation
        self.onRequestCheckout = onRequestCheckout
        self.onRequestExplainCommit = onRequestExplainCommit
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
                searchText: $historySearchText
            )
            
            if isLoading && commits.isEmpty {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commits.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    message: activeHistorySearchQuery.isEmpty ? "No commits to display" : "No matching commits",
                    detail: activeHistorySearchQuery.isEmpty ? "Repository may be empty" : "Try author name, email, or commit ID"
                )
            } else {
                ZStack(alignment: .top) {
                    PersistentVSplit(
                        autosaveName: "HistoryMainSplit",
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
            if appState.historyBranchFilter != .all {
                appState.historyBranchFilter = newBranch.map(HistoryBranchFilter.branch) ?? .current
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
        .onDisappear {
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
        .sheet(item: $fullFilePreview) { request in
            CommitFilePreviewSheet(request: request, availableSize: previewAvailableSize)
        }
        .sheet(isPresented: $showingResetConfirmation) {
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
        .sheet(isPresented: $showingTagSheet) {
            tagSheet
        }
        .sheet(isPresented: $showingBranchSheet) {
            branchSheet
        }
        .sheet(isPresented: $showingMergeConfirmation) {
            mergeConfirmationSheet
        }
        .sheet(isPresented: $showingRebaseConfirmation) {
            rebaseConfirmationSheet
        }
        .sheet(item: $squashSheetPresentation) { presentation in
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
        .sheet(isPresented: $showingCheckoutConfirmation) {
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
                let rowIndexByHash = Dictionary(
                    uniqueKeysWithValues: commits.enumerated().map { ($0.element.hash, $0.offset) }
                )
                // Fixed initial hints only; the native coordinator owns all
                // subsequent sizing, including window and scroller changes.
                ZStack(alignment: .bottom) {
                    Table(
                        of: Commit.self,
                        selection: $tableSelection,
                        columnCustomization: $tableColumnCustomization
                    ) {
                        TableColumn("Graph") { commit in
                            BranchGraphRowCanvas(
                                model: graphModel,
                                rowIndex: rowIndexByHash[commit.hash] ?? 0
                            )
                            .opacity(activeDragCommitHashes.contains(commit.hash) ? 0.4 : 1)
                        }
                        .width(min: 60, ideal: 200, max: .infinity)
                        .customizationID("graph")
                        .disabledCustomizationBehavior([.reorder, .visibility])

                        TableColumn("Message") { commit in
                            HistoryCommitMessageCell(
                                commit: commit,
                                graphModel: graphModel,
                                isDragActive: activeDragCommitHashes.contains(commit.hash),
                                scrollCoordinator: tableScrollCoordinator,
                                onAppear: {
                                    handleHistoryCommitCellAppearance(commit)
                                }
                            )
                        }
                        .width(
                            min: 120,
                            ideal: 400,
                            max: .infinity
                        )
                        .customizationID("message")
                        .disabledCustomizationBehavior([.reorder, .visibility])

                        TableColumn("Author") { commit in
                            Text("\(commit.author) <\(commit.email)>")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help("\(commit.author) <\(commit.email)>")
                        }
                        .width(
                            min: 140,
                            ideal: 180,
                            max: .infinity
                        )
                        .customizationID("author")

                        TableColumn("Date") { commit in
                            Text(
                                commit.date,
                                format: .dateTime
                                    .hour()
                                    .minute()
                                    .day()
                                    .month(.abbreviated)
                                    .year()
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                        }
                        .width(
                            min: 100,
                            ideal: 140,
                            max: .infinity
                        )
                        .alignment(.leading)
                        .customizationID("date")

                        TableColumn("Commit") { commit in
                            Text(commit.shortHash)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .help(commit.hash)
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
                            TableRow(commit)
                                .itemProvider {
                                    makeCommitItemProvider(startingAt: commit)
                                }
                        }
                    }
                    .tableStyle(.bordered)
                    .alternatingRowBackgrounds(.enabled)
                    .controlSize(.small)
                    .contextMenu(forSelectionType: String.self) { selectedHashes in
                        if !selectedHashes.isEmpty {
                            commitContextMenu(for: selectedHashes)
                        }
                    } primaryAction: { selectedHashes in
                        handleCommitTablePrimaryAction(selectedHashes)
                    }
                    .onChange(of: tableSelection) { oldSelection, newSelection in
                        applyTableSelection(from: oldSelection, to: newSelection)
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

                    if paging.isLoadingMore {
                        ProgressView("Loading older commits…")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .id(historyLoadKey)
    }

    // MARK: - Bottom Panel
    
    private var commitDetailPanel: some View {
        Group {
            if let commit = selectedCommit {
                VStack(spacing: 0) {
                    // Commit info header
                    commitInfoHeader(for: commit)
                    
                    PersistentHSplit(
                        autosaveName: "HistoryDetailSplit",
                        left: {
                            CommitFileListView(changes: fileChanges, selectedFile: $selectedFile) { file in
                                fullFilePreview = CommitFilePreviewRequest(
                                    repositoryURL: repositoryURL,
                                    commitHash: commit.hash,
                                    file: file
                                )
                            }
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
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(commit.author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(commit.email)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(commit.date, format: .dateTime.year().month().day().hour().minute())
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(commit.hash)
                        .font(.system(size: 11, design: .monospaced))
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
                            .font(.system(size: 13, weight: .semibold))
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
                        gitRef: selectedCommit.map(\.hash)
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
        if reset, let cached = historyCache[cacheKey] {
            await MainActor.run {
                applyCachedSnapshot(cached)
            }
            return
        }

        let preservedLoadLimit = await MainActor.run { () -> Int? in
            guard reset, preservingSelectionAndScroll else { return nil }

            let selectedIndex = commitSelection.primaryHash.flatMap { primaryHash in
                commits.firstIndex(where: { $0.hash == primaryHash })
            }
            let selectionBufferLimit = selectedIndex.map { $0 + paging.pageSize } ?? 0
            return max(paging.pageSize, paging.loadedCount, selectionBufferLimit)
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
        let skip = await MainActor.run { paging.loadedCount }
        let pageSize = await MainActor.run { paging.pageSize }
        let loadLimit = preservedLoadLimit ?? pageSize
        let searchQuery = activeHistorySearchQuery
        let newCommits: [Commit]
        if searchQuery.isEmpty {
            switch scope {
            case .allBranches:
                newCommits = await GitStatusService.shared.commitHistory(
                    allBranches: true,
                    limit: loadLimit,
                    skip: skip,
                    in: repositoryURL
                )
            case .currentBranch:
                newCommits = await GitStatusService.shared.commitHistory(
                    allBranches: false,
                    limit: loadLimit,
                    skip: skip,
                    in: repositoryURL
                )
            case .ref(let ref):
                newCommits = await GitStatusService.shared.commitHistory(
                    branch: ref,
                    limit: loadLimit,
                    skip: skip,
                    in: repositoryURL
                )
            }
        } else {
            switch scope {
            case .allBranches:
                newCommits = await GitStatusService.shared.searchCommitHistory(
                    allBranches: true,
                    query: searchQuery,
                    limit: loadLimit,
                    skip: skip,
                    in: repositoryURL
                )
            case .currentBranch:
                newCommits = await GitStatusService.shared.searchCommitHistory(
                    allBranches: false,
                    query: searchQuery,
                    limit: loadLimit,
                    skip: skip,
                    in: repositoryURL
                )
            case .ref(let ref):
                newCommits = await GitStatusService.shared.searchCommitHistory(
                    branch: ref,
                    query: searchQuery,
                    limit: loadLimit,
                    skip: skip,
                    in: repositoryURL
                )
            }
        }

        let newSelectedCommit: Commit?
        let newScrollTarget: String?
        switch scope {
        case .ref:
            newSelectedCommit = newCommits.first
            newScrollTarget = newCommits.first?.hash
        case .allBranches:
            if searchQuery.isEmpty,
               let selectedBranch,
               let tipHash = await GitStatusService.shared.tipHash(for: selectedBranch, in: repositoryURL),
               let tipCommit = newCommits.first(where: { $0.hash == tipHash }) {
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

        let loadedCommits = await MainActor.run {
            if reset || skip == 0 {
                return newCommits
            }
            return commits + newCommits
        }
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
        let newGraphModel = await CommitGraphGenerator.generateAsync(
            commits: loadedCommits,
            highlighting: highlighting,
            headHash: headHash,
            highlightRootHash: highlightRootHash
        )

        await MainActor.run {
            let shouldPreserveTableSelection =
                (preservingSelectionAndScroll || !reset)
                && !commitSelection.selectedHashes.isEmpty
            if shouldPreserveTableSelection {
                isRestoringTableSelection = true
            }
            commits = loadedCommits
            graphModel = newGraphModel
            let visibleHashes = loadedCommits.map(\.hash)
            if skip == 0 && !preservingSelectionAndScroll {
                // A branch change must select that branch's tip, even when the
                // previously selected commit is also reachable from the new branch.
                commitSelection = HistoryCommitSelection()
            } else {
                commitSelection.prune(visibleHashes: visibleHashes)
            }
            let shouldSelectDefaultCommit =
                (skip == 0 && !preservingSelectionAndScroll)
                || commitSelection.selectedHashes.isEmpty
            if shouldSelectDefaultCommit, let newSelectedCommit {
                commitSelection.select(
                    newSelectedCommit.hash,
                    modifiers: [],
                    visibleHashes: visibleHashes
                )
            }
            selectedCommit = Self.commit(withHash: commitSelection.primaryHash, in: loadedCommits)
            tableSelection = Set(commitSelection.selectedHashes)
            if skip == 0 && !preservingSelectionAndScroll {
                scrollTarget = Self.reloadTargetHash(
                    reset: true,
                    selectedCommitHash: selectedCommit?.hash,
                    newScrollTarget: newScrollTarget
                )
            }
            if skip == 0 && preservingSelectionAndScroll {
                paging.replaceLoadedHistory(
                    count: newCommits.count,
                    hasMore: newCommits.count == loadLimit
                )
            } else {
                paging.finishLoadingMore(loaded: newCommits.count)
            }
            cancelHistoryRefreshIndicator()

            historyCache[cacheKey] = HistorySnapshot(
                commits: loadedCommits,
                graphModel: newGraphModel,
                selectedCommitHash: selectedCommit?.hash
            )

            // Appending a page also updates the native Table's rows and can
            // transiently clear its selection, just like a background refresh.
            if shouldPreserveTableSelection {
                restoreSelectionIfTableClearsAfterReload(
                    commitSelection,
                    in: loadedCommits,
                    loadKey: cacheKey
                )
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

            var restoredSelection = selection
            restoredSelection.prune(visibleHashes: reloadedCommits.map(\.hash))
            guard !restoredSelection.selectedHashes.isEmpty else {
                isRestoringTableSelection = false
                return
            }

            commitSelection = restoredSelection
            selectedCommit = Self.commit(
                withHash: restoredSelection.primaryHash,
                in: reloadedCommits
            )
            tableSelection = Set(restoredSelection.selectedHashes)
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

    private func applyCachedSnapshot(_ snapshot: HistorySnapshot) {
        cancelHistoryRefreshIndicator()
        paging.reset()
        paging.finishLoadingMore(loaded: snapshot.commits.count)
        scrollTarget = snapshot.selectedCommitHash
        currentHeadHash = Self.resolvedHeadHash(from: snapshot.commits)

        commits = snapshot.commits
        graphModel = snapshot.graphModel

        let visibleHashes = snapshot.commits.map(\.hash)
        commitSelection.prune(visibleHashes: visibleHashes)
        if let cachedHash = snapshot.selectedCommitHash,
           snapshot.commits.contains(where: { $0.hash == cachedHash }) {
            commitSelection.select(cachedHash, modifiers: [], visibleHashes: visibleHashes)
        } else if commitSelection.selectedHashes.isEmpty, let first = snapshot.commits.first {
            commitSelection.select(first.hash, modifiers: [], visibleHashes: visibleHashes)
        }
        selectedCommit = Self.commit(withHash: commitSelection.primaryHash, in: snapshot.commits)
        tableSelection = Set(commitSelection.selectedHashes)

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
    
    private func loadFileChanges(for commit: Commit?) async {
        let loadID = UUID()
        await MainActor.run {
            commitFilesLoadID = loadID
            fileChanges = []
            selectedFile = nil
            diffHunks = []
            diffLoadID = UUID()
        }

        guard let commit = commit else {
            return
        }

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
    }
    
    private func loadDiff(for file: CommitFileChange?, in commit: Commit?) async {
        let loadID = UUID()
        await MainActor.run {
            diffLoadID = loadID
            diffHunks = []
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
        }
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

        guard !newSelection.isEmpty else {
            guard !isRestoringTableSelection else { return }
            commitSelection = HistoryCommitSelection()
            selectedCommit = nil
            return
        }

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

    private func handleHistoryCommitCellAppearance(_ commit: Commit) {
        guard commit.hash == commits.last?.hash else { return }
        Task {
            await loadOlderHistoryIfNeeded()
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
        "\(appState.historyBranchFilter.storageValue)|\(activeHistorySearchQuery)|\(historyLoadSizeRaw)"
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
        let graphModel: CommitGraphModel
        let selectedCommitHash: String?
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

    private func makeCommitItemProvider(startingAt commit: Commit) -> NSItemProvider? {
        let selectionHashes: [String]
        if tableSelection.contains(commit.hash) {
            selectionHashes = commits.map(\.hash).filter(tableSelection.contains)
        } else {
            selectionHashes = [commit.hash]
            tableSelection = [commit.hash]
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
        activeDragCommitHashes = Set(draggedCommits.map(\.hash))
        beginCommitDrag(startingAt: commit.hash, payload: payload)
        return makeCommitItemProvider(payload: payload)
    }

    private func makeCommitItemProvider(payload: GitDragPayload) -> NSItemProvider {
        GitDragPayloadStore.set(payload)

        let provider = NSItemProvider()
        if let data = try? GitDragPayload.encodeTransferData(payload) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.macgitGitDragPayload.identifier,
                visibility: .all
            ) { completionHandler in
                completionHandler(data, nil)
                return nil
            }
        }
        provider.register(payload)
        return provider
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
