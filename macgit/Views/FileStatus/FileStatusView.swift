//
//  FileStatusView.swift
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
import SwiftUI
import UniformTypeIdentifiers

struct FileStatusView: View {
    private enum EmptyCommitAction: Hashable {
        case allowEmptyCommit
        case commitChangedFiles
    }

    let repositoryURL: URL
    @ObservedObject var aiProviderController: AIProviderController
    @EnvironmentObject private var accountController: AccountSessionController
    @EnvironmentObject private var featureAccessController: FeatureAccessController
    @ObservedObject var syncState: SyncState
    var undoManager: GitUndoManager? = nil
    var preferredRemote: String? = nil
    var gitFlowConfiguration: GitFlowConfiguration = GitFlowConfiguration()
    var canUpdateCurrentBranch = false
    var onRequestUpdateCurrentBranch: (CurrentBranchIntegrationStatus) -> Void = { _ in }
    var onRequestApplyStash: (String) -> Void = { _ in }
    var onRequestComparePath: (ComparisonPath) -> Void = { _ in }
    var onAuthorizeCommit: () async -> Bool = { true }
    var onRequestPushAfterCommit: (String, String) async throws -> Void
    var onRunRepositoryOperation: RepositoryOperationRunner

    @ObservedObject private var integrationSettings = IntegrationSettingsStore.shared
    @State private var gitStatus: GitStatus = GitStatus(staged: [], unstaged: [], untracked: [])
    @State private var changedFiles: [StatusFile] = []
    @State private var visibleStagedFileCount = 100
    @State private var visibleChangedFileCount = 100
    @State private var selectedFile: StatusFile? = nil
    @State private var selectedFileKey: FileStatusSelectionKey? = nil
    @State private var selectedActionFileKeys: Set<FileStatusSelectionKey> = []
    @State private var diffHunks: [DiffHunk] = []
    @State private var isLoadingDiff = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isAIGenerationRequested = false

    @State private var isCommitBarExpanded = false
    @State private var isCommitting = false
    @State private var commitMessage = ""
    @State private var commitMessageSelection: TextSelection?
    @FocusState private var isCommitMessageFocused: Bool
    @State private var showingCommitConfirmation = false
    @State private var emptyCommitAction: EmptyCommitAction?
    @State private var allowEmptyMessage = false
    @State private var amendLastCommit = false
    @State private var bypassHooks = false
    @State private var signOffCommit = false
    @State private var pushAfterCommit = false
    @State private var commitAuthor: String?
    @State private var currentBranch: String?
    @State private var currentBranchIntegrationStatus: CurrentBranchIntegrationStatus?
    @State private var potentialConflictPresentation: PotentialConflictFilePresentation?
    @State private var recentCommits: [(hash: String, message: String)] = []
    @State private var ignoreTargetFile: StatusFile? = nil
    @State private var conflictResolverWindowController = NSWindowController(window: nil)

    private let fileDisplayPageSize = 100

    private var visibleStagedFiles: ArraySlice<StatusFile> {
        gitStatus.staged.prefix(visibleStagedFileCount)
    }

    private var visibleChangedFiles: ArraySlice<StatusFile> {
        changedFiles.prefix(visibleChangedFileCount)
    }

    private var visibleStagedRows: [FileStatusRowItem] {
        visibleStagedFiles.map { FileStatusRowItem(file: $0, isStaged: true) }
    }

    private var visibleChangedRows: [FileStatusRowItem] {
        visibleChangedFiles.map { FileStatusRowItem(file: $0, isStaged: false) }
    }

    private var hasChanges: Bool {
        !gitStatus.isEmpty
    }

    private var isCommitMessageEmpty: Bool {
        commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var needsCommitConfirmation: Bool {
        gitStatus.staged.isEmpty || isCommitMessageEmpty
    }

    private var canConfirmCommit: Bool {
        (!gitStatus.staged.isEmpty || emptyCommitAction != nil)
            && (!isCommitMessageEmpty || allowEmptyMessage)
    }

    private var actionSelection: FileStatusActionSelection {
        FileStatusActionSelection(
            selectedKeys: selectedActionFileKeys,
            stagedFiles: gitStatus.staged,
            changedFiles: changedFiles
        )
    }

    private func sectionCheckState(isStaged: Bool) -> NSControl.StateValue {
        let files = isStaged ? gitStatus.staged : changedFiles
        let selectedCount = selectedActionFileKeys.count { $0.isStaged == isStaged }
        if selectedCount == 0 { return .off }
        if selectedCount == files.count { return .on }
        return .mixed
    }

    private func toggleSelectAll(isStaged: Bool, selectAll: Bool) {
        let files = isStaged ? gitStatus.staged : changedFiles
        let allKeys = Set(files.map { FileStatusSelectionKey(file: $0, isStaged: isStaged) })
        if selectAll {
            selectedActionFileKeys.formUnion(allKeys)
        } else {
            selectedActionFileKeys.subtract(allKeys)
        }
    }

    @ViewBuilder
    private var inProgressBanner: some View {
        if let operation = syncState.inProgressOperation {
            let isEmpty = !hasChanges
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))

                Text(isEmpty ? operation.emptyMessage : operation.message)
                    .font(.system(size: 12))

                Spacer()

                HStack(spacing: 8) {
                    if isEmpty && operation.canSkip {
                        Button("Skip") {
                            Task { await skipInProgressOperation(operation) }
                        }
                        .buttonStyle(.borderedProminent)
                        .pointingHandCursor()
                        .controlSize(.small)

                        Button("Abort") {
                            Task { await abortInProgressOperation(operation) }
                        }
                        .buttonStyle(.borderless)
                        .pointingHandCursor()
                        .controlSize(.small)
                    } else {
                        Button("Abort") {
                            Task { await abortInProgressOperation(operation) }
                        }
                        .buttonStyle(.borderless)
                        .pointingHandCursor()
                        .controlSize(.small)

                        Button("Continue") {
                            Task { await continueInProgressOperation(operation) }
                        }
                        .buttonStyle(.borderedProminent)
                        .pointingHandCursor()
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.08))
            .overlay(
                Rectangle()
                    .fill(Color.orange.opacity(0.25))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    private var hasInProgressOperation: Bool {
        syncState.inProgressOperation != nil
    }

    var body: some View {
        Group {
            if isLoading && !hasChanges && !hasInProgressOperation {
                ProgressView("Loading status…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasChanges && !hasInProgressOperation {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    message: "No changes",
                    detail: "Working directory is clean"
                )
            } else {
                VStack(spacing: 0) {
                    inProgressBanner

                    if hasChanges {
                        PersistentHSplit(
                            autosaveName: "FileStatusMainSplit",
                            left: { fileListPanel.frame(minWidth: 220) },
                            right: { diffPanel.frame(minWidth: 300) }
                        )

                        commitBar
                    } else {
                        EmptyStateView(
                            icon: "doc.text.magnifyingglass",
                            message: "No changes",
                            detail: "Working directory is clean"
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            GitDragPayloadItemProviderLoader.load(from: provider) { result in
                Task { @MainActor in
                    if case .success(let payload) = result,
                       let stashRef = payload.stash {
                        onRequestApplyStash(stashRef)
                    }
                }
            }
            return true
        }
        .task {
            await loadStatus()
        }
        .onChange(of: selectedFileKey) { _, newSelectionKey in
            diffHunks = []
            isLoadingDiff = newSelectionKey != nil
            guard let newSelectionKey,
                  let file = selectedFile else {
                return
            }

            Task {
                await loadDiff(for: file, selectionKey: newSelectionKey)
            }
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .replacingSheet(isPresented: $showingCommitConfirmation) {
            commitConfirmation
        }
        .replacingSheet(item: $ignoreTargetFile) { file in
            IgnoreOptionsView(
                file: file,
                repositoryURL: repositoryURL,
                onConfirm: { pattern in
                    Task {
                        await confirmIgnore(file: file, pattern: pattern)
                        ignoreTargetFile = nil
                    }
                },
                onCancel: {
                    ignoreTargetFile = nil
                }
            )
        }
        .replacingSheet(item: $potentialConflictPresentation) { presentation in
            PotentialConflictFileDetailSheet(
                presentation: presentation,
                repositoryURL: repositoryURL,
                canUpdateCurrentBranch: canUpdateCurrentBranch,
                onUpdateCurrentBranch: onRequestUpdateCurrentBranch
            )
        }

        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await loadStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                Task {
                    await loadStatus()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryRemoteRefsDidRefresh)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                Task {
                    await loadStatus()
                }
            }
        }
    }

    private var fileListPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TriStateCheckbox(state: sectionCheckState(isStaged: true), accessibilityLabel: "Select all staged") { selectAll in
                        toggleSelectAll(isStaged: true, selectAll: selectAll)
                    }
                    .pointingHandCursor()
                    .disabled(gitStatus.staged.isEmpty)
                    Text("Staged")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                    Spacer()
                    Button(actionSelection.title(for: .staged)) {
                        Task {
                            if actionSelection.selectedStagedFiles.isEmpty {
                                await unstageAll()
                            } else {
                                await unstageSelected()
                            }
                        }
                    }
                    .buttonStyle(GlassButtonStyle(tint: .yellow, fontSize: 10))
                    .pointingHandCursor()
                    .disabled(gitStatus.staged.isEmpty)
                }
                .frame(height: 22)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .bottom) {
                    Divider()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleStagedRows) { row in
                            fileRow(file: row.file, isStaged: row.isStaged)
                        }
                        if visibleStagedFileCount < gitStatus.staged.count {
                            filePageLoader {
                                visibleStagedFileCount = min(
                                    visibleStagedFileCount + fileDisplayPageSize,
                                    gitStatus.staged.count
                                )
                            }
                            .id(visibleStagedFileCount)
                        }
                        if gitStatus.staged.isEmpty {
                            Text("No staged files")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    }
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TriStateCheckbox(state: sectionCheckState(isStaged: false), accessibilityLabel: "Select all changed") { selectAll in
                        toggleSelectAll(isStaged: false, selectAll: selectAll)
                    }
                    .pointingHandCursor()
                    .disabled(changedFiles.isEmpty)
                    Text("Changed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.none)
                    Spacer()
                    Button(actionSelection.title(for: .changed)) {
                        Task {
                            if actionSelection.selectedChangedFiles.isEmpty {
                                await stageAll()
                            } else {
                                await stageSelected()
                            }
                        }
                    }
                    .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 10))
                    .pointingHandCursor()
                    .disabled(changedFiles.isEmpty)
                }
                .frame(height: 22)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .bottom) {
                    Divider()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleChangedRows) { row in
                            fileRow(file: row.file, isStaged: row.isStaged)
                        }
                        if visibleChangedFileCount < changedFiles.count {
                            filePageLoader {
                                visibleChangedFileCount = min(
                                    visibleChangedFileCount + fileDisplayPageSize,
                                    changedFiles.count
                                )
                            }
                            .id(visibleChangedFileCount)
                        }
                        if changedFiles.isEmpty {
                            Text("No changed files")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    }
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func filePageLoader(action: @escaping () -> Void) -> some View {
        Color.clear
            .frame(height: 1)
            .onAppear(perform: action)
    }

    private func fileRow(file: StatusFile, isStaged: Bool) -> some View {
        let selectionKey = FileStatusSelectionKey(file: file, isStaged: isStaged)
        let isSelected = selectedFileKey == selectionKey
        let quickAction = FileStatusRowQuickAction(isStaged: isStaged)
        let isPotentialConflict = hasPotentialConflict(file)

        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { selectedActionFileKeys.contains(selectionKey) },
                    set: { isSelected in
                        if isSelected {
                            selectedActionFileKeys.insert(selectionKey)
                        } else {
                            selectedActionFileKeys.remove(selectionKey)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .pointingHandCursor()

                if isPotentialConflict {
                    PotentialConflictFileIndicator(
                        baseRef: currentBranchIntegrationStatus?.baseRef,
                        onOpenDetails: { presentPotentialConflictDetails(for: file) }
                    )
                } else {
                    Image(systemName: fileIcon(for: file))
                        .foregroundStyle(fileColor(for: file))
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 18)
                }

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        if let original = file.originalPath {
                            Text("\(original) → \(file.path)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(file.directory)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .onDrag {
                    let paths = actionSelection.dragPaths(startingAt: file, isStaged: isStaged)
                    return makeFileItemProvider(payload: .files(paths, repositoryURL: repositoryURL))
                } preview: {
                    FileDragPreview(
                        pathCount: actionSelection.dragPaths(startingAt: file, isStaged: isStaged).count,
                        fallbackPath: file.path
                    )
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 2)

            quickActionButton(quickAction, file: file)
                .padding(.trailing, 2)

            moreButton(file: file, isStaged: isStaged)
                .padding(.trailing, 4)
        }
        .padding(.leading, 8)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 3)
        }
        .pointingHandCursor()
        .onTapGesture {
            guard selectedFileKey != selectionKey else { return }
            selectedFile = file
            selectedFileKey = selectionKey
            diffHunks = []
            isLoadingDiff = true
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                Task {
                    if isStaged {
                        await unstage(file: file)
                    } else {
                        await stage(file: file)
                    }
                }
            }
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            fileContextMenu(file: file, isStaged: isStaged)
        }
    }

    private func makeFileItemProvider(payload: GitDragPayload) -> NSItemProvider {
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
        provider.suggestedName = "\(payload.files.count) files"
        return provider
    }

    private func quickActionButton(_ quickAction: FileStatusRowQuickAction, file: StatusFile) -> some View {
        Button {
            Task {
                switch quickAction.kind {
                case .stage:
                    await stage(file: file)
                case .unstage:
                    await unstage(file: file)
                }
            }
        } label: {
            Image(systemName: quickAction.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .pointingHandCursor()
        .help(quickAction.accessibilityLabel)
        .accessibilityLabel(quickAction.accessibilityLabel)
        .frame(width: 24)
    }

    private func moreButton(file: StatusFile, isStaged: Bool) -> some View {
        let selection = actionSelection

        return Menu {
            comparisonMenu(file: file)
            Button("Open") { openFile(file: file) }
                .disabled(selection.isSingleFileActionDisabled)
            Button("Show in Finder") { showInFinder(file: file) }
                .disabled(selection.isSingleFileActionDisabled)
            if hasPotentialConflict(file) {
                Button("View Potential Conflict Details…", systemImage: "exclamationmark.triangle") {
                    presentPotentialConflictDetails(for: file)
                }
                .disabled(selection.isSingleFileActionDisabled)
            }
            Divider()

            if isStaged {
                Button(menuTitle(for: .unstage, selection: selection)) {
                    Task {
                        await unstage(files: selection.files(for: .unstage, fallback: file))
                    }
                }
                Button(selection.title(for: .remove)) {
                    Task {
                        await remove(files: selection.files(for: .remove, fallback: file))
                    }
                }
            } else {
                Button(menuTitle(for: .stage, selection: selection)) {
                    Task {
                        await stage(files: selection.files(for: .stage, fallback: file))
                    }
                }
                Button(selection.title(for: .discard)) {
                    Task {
                        await discard(files: selection.files(for: .discard, fallback: file))
                    }
                }
                Button(selection.title(for: .remove)) {
                    Task {
                        await remove(files: selection.files(for: .remove, fallback: file))
                    }
                }
                if file.status == .untracked || file.status == .added {
                    Button("Ignore") { ignoreTargetFile = file }
                        .disabled(selection.isSingleFileActionDisabled)
                }
            }

            Divider()

            if !isStaged {
                Button("Reset") { Task { await discard(file: file) } }
                    .disabled(selection.isSingleFileActionDisabled)

                if !recentCommits.isEmpty {
                    Menu("Reset to Commit...") {
                        ForEach(recentCommits, id: \.hash) { commit in
                            Button("\(commit.hash) \(commit.message)") {
                                Task { await resetToCommit(file: file, commit: commit.hash) }
                            }
                        }
                    }
                    .disabled(selection.isSingleFileActionDisabled)
                }

                if file.status == .conflict {
                    Menu("Resolve Conflicts") {
                        Button("Use Current Version") {
                            Task { await resolveConflict(file: file, using: .ours) }
                        }
                        Button("Use Incoming Version") {
                            Task { await resolveConflict(file: file, using: .theirs) }
                        }
                        Divider()
                        Button("Resolve Manually…") {
                            openConflictResolverWindow(for: file)
                        }
                        Button("Resolve with External Tool") {
                            Task { await resolveConflictWithExternalTool(file: file) }
                        }
                        .disabled(integrationSettings.selectedApplication(for: .merge) == nil)
                    }
                    .disabled(selection.isSingleFileActionDisabled)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .pointingHandCursor()
        .menuIndicator(.hidden)
        .frame(width: 24)
    }

    @ViewBuilder
    private func comparisonMenu(file: StatusFile) -> some View {
        Button("Compare with Revision…") {
            onRequestComparePath(ComparisonPath(path: file.path, isDirectory: false))
        }
        .disabled(file.status == .untracked || actionSelection.isSingleFileActionDisabled)
        Button("Compare Parent Folder with Revision…") {
            let components = file.path.split(separator: "/", omittingEmptySubsequences: false).dropLast()
            onRequestComparePath(ComparisonPath(path: components.isEmpty ? "." : components.joined(separator: "/"),
                                               isDirectory: true))
        }
        .disabled(actionSelection.isSingleFileActionDisabled)
        Divider()
    }

    @ViewBuilder
    private func fileContextMenu(file: StatusFile, isStaged: Bool) -> some View {
        let selection = actionSelection

        comparisonMenu(file: file)
        Button("Open") { openFile(file: file) }
            .disabled(selection.isSingleFileActionDisabled)
        Button("Show in Finder") { showInFinder(file: file) }
            .disabled(selection.isSingleFileActionDisabled)
        Button("External Diff") {
            Task {
                await openExternalDiff(file: file)
            }
        }
        .disabled(
            isStaged
                || !supportsExternalDiff(file)
                || integrationSettings.selectedApplication(for: .diff) == nil
                || selection.isSingleFileActionDisabled
        )
        if hasPotentialConflict(file) {
            Button("View Potential Conflict Details…", systemImage: "exclamationmark.triangle") {
                presentPotentialConflictDetails(for: file)
            }
            .disabled(selection.isSingleFileActionDisabled)
        }
        Divider()

        if isStaged {
            Button(menuTitle(for: .unstage, selection: selection)) {
                Task {
                    await unstage(files: selection.files(for: .unstage, fallback: file))
                }
            }
            Button(selection.title(for: .remove)) {
                Task {
                    await remove(files: selection.files(for: .remove, fallback: file))
                }
            }
        } else {
            Button(menuTitle(for: .stage, selection: selection)) {
                Task {
                    await stage(files: selection.files(for: .stage, fallback: file))
                }
            }
            Button(selection.title(for: .discard)) {
                Task {
                    await discard(files: selection.files(for: .discard, fallback: file))
                }
            }
            Button(selection.title(for: .remove)) {
                Task {
                    await remove(files: selection.files(for: .remove, fallback: file))
                }
            }
            if file.status == .untracked || file.status == .added {
                Button("Ignore") { ignoreTargetFile = file }
                    .disabled(selection.isSingleFileActionDisabled)
            }
        }

        Button("Stop Tracking") {
            Task {
                await stopTracking(file: file)
            }
        }
        .disabled(isStaged || file.status == .untracked || selection.isSingleFileActionDisabled)

        Divider()

        if !isStaged {
            Button("Reset") { Task { await discard(file: file) } }
                .disabled(selection.isSingleFileActionDisabled)

            if !recentCommits.isEmpty {
                Menu("Reset to Commit...") {
                    ForEach(recentCommits, id: \.hash) { commit in
                        Button("\(commit.hash) \(commit.message)") {
                            Task { await resetToCommit(file: file, commit: commit.hash) }
                        }
                    }
                }
                .disabled(selection.isSingleFileActionDisabled)
            }

            if file.status == .conflict {
                Menu("Resolve Conflicts") {
                    Button("Use Current Version") {
                        Task { await resolveConflict(file: file, using: .ours) }
                    }
                    Button("Use Incoming Version") {
                        Task { await resolveConflict(file: file, using: .theirs) }
                    }
                    Divider()
                    Button("Resolve Manually…") {
                        openConflictResolverWindow(for: file)
                    }
                    Button("Resolve with External Tool") {
                        Task { await resolveConflictWithExternalTool(file: file) }
                    }
                    .disabled(integrationSettings.selectedApplication(for: .merge) == nil)
                }
                .disabled(selection.isSingleFileActionDisabled)
            }
        }
    }

    private func menuTitle(for action: FileStatusSelectionAction, selection: FileStatusActionSelection) -> String {
        let base = selection.title(for: action)
        switch action {
        case .stage, .unstage:
            return "\(base) (double click)"
        case .discard, .remove:
            return base
        }
    }

    private var diffPanel: some View {
        Group {
            if let file = selectedFile {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: fileIcon(for: file))
                            .foregroundStyle(fileColor(for: file))
                            .font(.system(size: 16, weight: .medium))
                        Text(file.path)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.separator)
                            .frame(height: 0.5)
                    }

                    if isLoadingDiff {
                        ProgressView("Loading diff…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if file.isImage {
                        imagePreview(file: file)
                    } else if file.isVideo {
                        videoPreview(file: file)
                    } else {
                        DiffView(
                            hunks: diffHunks,
                            file: file,
                            repositoryURL: repositoryURL,
                            undoManager: undoManager,
                            onRefresh: {
                                Task {
                                    await reloadRepositoryState()
                                }
                            },
                            onError: { message in
                                errorMessage = message
                                showingError = true
                            }
                        )
                    }
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

    private var commitBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCommitBarExpanded {
                expandedCommitBar
            } else {
                collapsedCommitBar
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
        .onChange(of: isCommitBarExpanded) { _, isExpanded in
            if isExpanded {
                Task { @MainActor in
                    await Task.yield()
                    isCommitMessageFocused = true
                }
            } else {
                isCommitMessageFocused = false
            }
        }
    }

    private var collapsedCommitBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                TextField("Commit message", text: $commitMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .disabled(true)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.pointingHand.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCommitBarExpanded = true
                }
                Task {
                    if commitAuthor == nil {
                        commitAuthor = await GitStatusService.shared.gitUser(in: repositoryURL)
                    }
                    if currentBranch == nil {
                        currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var expandedCommitBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: author + options
            HStack(spacing: 10) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)

                Text(commitAuthor ?? "Committer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Menu {
                    Toggle("Amend last commit", isOn: $amendLastCommit)
                    Toggle("Bypass commit hooks", isOn: $bypassHooks)
                    Toggle("Sign off", isOn: $signOffCommit)
                } label: {
                    HStack(spacing: 4) {
                        Text("Commit Options")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(GlassButtonStyle(tint: .secondary, fontSize: 10))
                .onContinuousHover { updateCommitBarCursor($0) }

                AIProviderMenu(
                    controller: aiProviderController,
                    restrictedProviderAccess: aiProviderAccessDecision,
                    showsConfigureAction: true
                )
                .onContinuousHover {
                    updateCommitBarCursor($0, isEnabled: !aiProviderController.isGenerating)
                }
            }

            // Message editor
            ZStack(alignment: .topTrailing) {
                TextField(
                    "",
                    text: $commitMessage,
                    selection: $commitMessageSelection,
                    axis: .vertical
                )
                    .focused($isCommitMessageFocused)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .textFieldStyle(.plain)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 100, alignment: .topLeading)
                    .padding(6)
                    .padding(.trailing, 30)
                    .disabled(aiProviderController.isGenerating)
                    .accessibilityLabel("Commit message")
                    .onKeyPress(.return, phases: .down) { keyPress in
                        if keyPress.modifiers == .shift {
                            insertNewlineInCommitMessage()
                            return .handled
                        }
                        guard keyPress.modifiers.isEmpty else { return .ignored }
                        requestCommit()
                        return .handled
                    }

                Button {
                    isAIGenerationRequested = true
                } label: {
                    ZStack {
                        Label("Generate commit message", systemImage: "sparkles")
                            .labelStyle(.iconOnly)
                            .opacity(aiProviderController.isGenerating ? 0 : 1)

                        if aiProviderController.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: 14, height: 14)
                }
                .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 11))
                .disabled(!canGenerateCommitMessage)
                .help(generateCommitMessageHelp)
                .accessibilityLabel(aiProviderController.isGenerating
                    ? "Generating commit message"
                    : "Generate commit message")
                .onContinuousHover {
                    updateCommitBarCursor($0, isEnabled: canGenerateCommitMessage)
                }
                .padding(8)
            }
            .frame(minHeight: 48, maxHeight: 100)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 0.5)
            )

            // Bottom row: toggles + buttons
            HStack(spacing: 12) {
                Toggle("Amend last commit", isOn: $amendLastCommit)
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.checkbox)
                    .onContinuousHover { updateCommitBarCursor($0) }

                Toggle("Push changes immediately to \(currentBranch ?? "current branch")", isOn: $pushAfterCommit)
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.checkbox)
                    .onContinuousHover { updateCommitBarCursor($0) }

                Spacer()

                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCommitBarExpanded = false
                    }
                }
                .buttonStyle(GlassButtonStyle(tint: .secondary, fontSize: 12))
                .onContinuousHover { updateCommitBarCursor($0) }

                Button(action: requestCommit) {
                    HStack(spacing: 6) {
                        if isCommitting {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)
                        }
                        Text(isCommitting ? "Committing..." : "Commit")
                    }
                }
                    .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 12))
                    .onContinuousHover { updateCommitBarCursor($0) }
            }
        }
        .disabled(isCommitting)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .task {
            await aiProviderController.refreshAvailability()
        }
        .aiCommitMessageAccessGate(
            isRequested: $isAIGenerationRequested,
            requiresProAccess: aiProviderController.selectedDescriptor.billing.requiresProAccess
        ) {
            Task {
                await generateCommitMessage()
            }
        }
    }

    private func updateCommitBarCursor(_ phase: HoverPhase, isEnabled: Bool = true) {
        switch phase {
        case .active:
            (isEnabled && !isCommitting ? NSCursor.pointingHand : NSCursor.arrow).set()
        case .ended:
            NSCursor.arrow.set()
        }
    }

    private var commitConfirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(commitConfirmationTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(commitConfirmationMessage)
                .foregroundStyle(.secondary)

            if gitStatus.staged.isEmpty {
                Picker("Commit action", selection: $emptyCommitAction) {
                    Text("Create empty commit (no staged files)")
                        .tag(EmptyCommitAction.allowEmptyCommit as EmptyCommitAction?)
                    Text("Commit all changed files")
                        .tag(EmptyCommitAction.commitChangedFiles as EmptyCommitAction?)
                }
                .pickerStyle(.radioGroup)
            }

            if isCommitMessageEmpty {
                Toggle("Commit with empty message", isOn: $allowEmptyMessage)
                    .toggleStyle(.checkbox)
                    .pointingHandCursor()
            }

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    showingCommitConfirmation = false
                    emptyCommitAction = nil
                    allowEmptyMessage = false
                }
                .pointingHandCursor()

                Button("Commit") {
                    showingCommitConfirmation = false
                    let shouldAllowEmptyCommit = gitStatus.staged.isEmpty
                        && emptyCommitAction == .allowEmptyCommit
                    let shouldCommitChangedFiles = gitStatus.staged.isEmpty
                        && emptyCommitAction == .commitChangedFiles
                    let shouldAllowEmptyMessage = allowEmptyMessage
                    self.emptyCommitAction = nil
                    allowEmptyMessage = false
                    startCommit(
                        allowEmpty: shouldAllowEmptyCommit,
                        commitChangedFiles: shouldCommitChangedFiles,
                        allowEmptyMessage: shouldAllowEmptyMessage
                    )
                }
                .pointingHandCursor()
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirmCommit)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private var commitConfirmationTitle: String {
        if gitStatus.staged.isEmpty {
            "No files staged"
        } else {
            "Empty commit message"
        }
    }

    private var commitConfirmationMessage: String {
        if gitStatus.staged.isEmpty && isCommitMessageEmpty {
            "No files are staged and the commit message is empty. Choose how to handle changed files, then confirm the empty message."
        } else if gitStatus.staged.isEmpty {
            "No files are staged. Choose whether to create an empty commit or stage all changed files before committing."
        } else {
            "The commit message is empty. Confirm that you want to commit the staged files without a message."
        }
    }

    private var canGenerateCommitMessage: Bool {
        (!gitStatus.staged.isEmpty || !changedFiles.isEmpty)
            && !aiProviderController.isGenerating
    }

    private var aiProviderAccessDecision: FeatureAccessDecision {
        featureAccessController.decision(
            for: .aiBringYourOwnKey,
            entitlement: accountController.entitlement
        )
    }

    private var generateCommitMessageHelp: String {
        if gitStatus.staged.isEmpty && changedFiles.isEmpty {
            return "Change a file before generating a commit message."
        }
        if !aiProviderController.selectedProviderAvailability.isAvailable {
            return aiProviderController.selectedProviderAvailability.detail
        }
        return gitStatus.staged.isEmpty
            ? "Generate an editable message from changed files."
            : "Generate an editable message from staged changes."
    }

    private func generateCommitMessage() async {
        do {
            let changeSource: CommitChangeSource = gitStatus.staged.isEmpty ? .workingTree : .staged
            let generated = try await aiProviderController.generateCommitMessage(
                repositoryURL: repositoryURL,
                branchName: currentBranch,
                changeSource: changeSource,
                recentCommitSubjects: recentCommits.map(\.message)
            )
            commitMessage = generated.text
            isCommitMessageFocused = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func insertNewlineInCommitMessage() {
        guard let commitMessageSelection,
              case let .selection(range) = commitMessageSelection.indices else {
            commitMessage.append("\n")
            self.commitMessageSelection = TextSelection(insertionPoint: commitMessage.endIndex)
            return
        }

        let insertionOffset = commitMessage.distance(
            from: commitMessage.startIndex,
            to: range.lowerBound
        )
        commitMessage.replaceSubrange(range, with: "\n")
        let insertionPoint = commitMessage.index(
            commitMessage.startIndex,
            offsetBy: insertionOffset + 1
        )
        self.commitMessageSelection = TextSelection(insertionPoint: insertionPoint)
    }

    private func requestCommit() {
        guard !isCommitting, !showingCommitConfirmation else { return }
        if needsCommitConfirmation {
            emptyCommitAction = nil
            allowEmptyMessage = false
            showingCommitConfirmation = true
        } else {
            startCommit()
        }
    }

    private func startCommit(
        allowEmpty: Bool = false,
        commitChangedFiles: Bool = false,
        allowEmptyMessage: Bool = false
    ) {
        guard !isCommitting else { return }
        isCommitting = true
        syncState.isCommitting = true
        onRunRepositoryOperation("Committing changes...") {
            defer {
                isCommitting = false
                syncState.isCommitting = false
            }
            await performCommit(
                allowEmpty: allowEmpty,
                commitChangedFiles: commitChangedFiles,
                allowEmptyMessage: allowEmptyMessage
            )
        }
    }

    private func performCommit(
        allowEmpty: Bool = false,
        commitChangedFiles: Bool = false,
        allowEmptyMessage: Bool = false
    ) async {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty || allowEmptyMessage else { return }
        guard await onAuthorizeCommit() else { return }
        do {
            if commitChangedFiles {
                try await GitStatusService.shared.stageAllChanges(in: repositoryURL)
            }
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.commit(
                message: message,
                in: repositoryURL,
                amend: amendLastCommit,
                noVerify: bypassHooks,
                signOff: signOffCommit,
                allowEmpty: allowEmpty
            )
            let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            if !amendLastCommit, let oldHead, let newHead, oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntryFactory.commit(
                            repositoryURL: repositoryURL,
                            oldHead: oldHead,
                            newHead: newHead,
                            message: message,
                            noVerify: bypassHooks,
                            signOff: signOffCommit
                        )
                    )
                }
            }
            if pushAfterCommit {
                let branch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
                try await onRequestPushAfterCommit("origin", branch)
            }
            await MainActor.run {
                commitMessage = ""
                amendLastCommit = false
                bypassHooks = false
                signOffCommit = false
                pushAfterCommit = false
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCommitBarExpanded = false
                }
            }
            await reloadRepositoryState()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func imagePreview(file: StatusFile) -> some View {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        return Group {
            if let nsImage = NSImage(contentsOf: fileURL) {
                GeometryReader { geo in
                    ScrollView(.vertical) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, alignment: .top)
                            .clipped()
                    }
                }
            } else {
                EmptyStateView(
                    icon: "photo",
                    message: "Unable to preview image",
                    detail: file.path
                )
            }
        }
    }

    private func videoPreview(file: StatusFile) -> some View {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        return VideoThumbnailView(fileURL: fileURL, filePath: file.path)
    }

    private func fileIcon(for file: StatusFile) -> String {
        switch file.status {
        case .added:
            return "plus.circle.fill"
        case .staged:
            return "pencil.circle.fill"
        case .modified:
            return "pencil.circle.fill"
        case .deleted:
            return "minus.circle.fill"
        case .renamed:
            return "arrow.right.circle.fill"
        case .untracked:
            return "questionmark.circle.fill"
        case .conflict:
            return "exclamationmark.triangle.fill"
        }
    }

    private func fileColor(for file: StatusFile) -> Color {
        switch file.status {
        case .added:
            return .green
        case .staged, .modified:
            return .orange
        case .deleted:
            return .red
        case .renamed:
            return .blue
        case .untracked:
            return .gray
        case .conflict:
            return .purple
        }
    }

    private func hasPotentialConflict(_ file: StatusFile) -> Bool {
        guard file.status != .conflict,
              let conflictPaths = currentBranchIntegrationStatus?.potentialConflictPaths
        else {
            return false
        }

        return conflictPaths.contains(file.path)
            || file.originalPath.map(conflictPaths.contains) == true
    }

    private func presentPotentialConflictDetails(for file: StatusFile) {
        guard hasPotentialConflict(file), let currentBranchIntegrationStatus else { return }
        potentialConflictPresentation = PotentialConflictFilePresentation(
            file: file,
            status: currentBranchIntegrationStatus
        )
    }

    private func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedStatus = try await GitStatusService.shared.status(for: repositoryURL)
            let loadedCurrentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
            let loadedIntegrationStatus: CurrentBranchIntegrationStatus?
            if let loadedCurrentBranch {
                loadedIntegrationStatus = await GitStatusService.shared.currentBranchIntegrationStatus(
                    branch: loadedCurrentBranch,
                    preferredRemote: preferredRemote,
                    gitFlowConfiguration: gitFlowConfiguration,
                    in: repositoryURL
                )
            } else {
                loadedIntegrationStatus = nil
            }

            gitStatus = loadedStatus
            changedFiles = loadedStatus.unstaged + loadedStatus.untracked
            currentBranch = loadedCurrentBranch
            currentBranchIntegrationStatus = loadedIntegrationStatus
            visibleStagedFileCount = min(
                max(visibleStagedFileCount, fileDisplayPageSize),
                loadedStatus.staged.count
            )
            visibleChangedFileCount = min(
                max(visibleChangedFileCount, fileDisplayPageSize),
                changedFiles.count
            )
            recentCommits = await GitStatusService.shared.recentCommits(in: repositoryURL)

            restoreSelectedFileAfterStatusRefresh()

            if !selectedActionFileKeys.isEmpty {
                selectedActionFileKeys = actionSelection.prunedSelection
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func reloadRepositoryState() async {
        await loadStatus()
        await syncState.refresh(repositoryURL: repositoryURL)
    }

    private func restoreSelectedFileAfterStatusRefresh() {
        if let selectedFileKey {
            let files = selectedFileKey.isStaged ? gitStatus.staged : changedFiles
            if let matched = files.first(where: {
                FileStatusSelectionKey(file: $0, isStaged: selectedFileKey.isStaged) == selectedFileKey
            }) {
                selectedFile = matched
                return
            }
        }

        if let firstStagedFile = gitStatus.staged.first {
            selectedFile = firstStagedFile
            selectedFileKey = FileStatusSelectionKey(file: firstStagedFile, isStaged: true)
        } else if let firstChangedFile = changedFiles.first {
            selectedFile = firstChangedFile
            selectedFileKey = FileStatusSelectionKey(file: firstChangedFile, isStaged: false)
        } else {
            selectedFile = nil
            selectedFileKey = nil
            diffHunks = []
            isLoadingDiff = false
        }
    }

    private func loadDiff(for file: StatusFile, selectionKey: FileStatusSelectionKey) async {
        do {
            let loadedDiffHunks = try await GitStatusService.shared.diff(for: file, in: repositoryURL)
            guard selectedFileKey == selectionKey else { return }
            diffHunks = loadedDiffHunks
        } catch {
            guard selectedFileKey == selectionKey else { return }
            diffHunks = []
        }

        guard selectedFileKey == selectionKey else { return }
        isLoadingDiff = false
    }

    private func continueInProgressOperation(_ operation: GitInProgressOperation) async {
        if case .merge = operation {
            guard await onAuthorizeCommit() else { return }
        }
        do {
            switch operation {
            case .merge:
                try await GitStatusService.shared.continueMerge(in: repositoryURL)
            case .cherryPick:
                try await GitStatusService.shared.continueCherryPick(in: repositoryURL)
            case .revert:
                try await GitStatusService.shared.continueRevert(in: repositoryURL)
            }
            await reloadRepositoryState()
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

    private func skipInProgressOperation(_ operation: GitInProgressOperation) async {
        do {
            switch operation {
            case .merge:
                return
            case .cherryPick:
                try await GitStatusService.shared.skipCherryPick(in: repositoryURL)
            case .revert:
                try await GitStatusService.shared.skipRevert(in: repositoryURL)
            }
            await reloadRepositoryState()
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

    private func abortInProgressOperation(_ operation: GitInProgressOperation) async {
        do {
            switch operation {
            case .merge:
                try await GitStatusService.shared.abortMerge(in: repositoryURL)
            case .cherryPick:
                try await GitStatusService.shared.abortCherryPick(in: repositoryURL)
            case .revert:
                try await GitStatusService.shared.abortRevert(in: repositoryURL)
            }
            await reloadRepositoryState()
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

    private func stage(file: StatusFile) async {
        await stage(files: [file])
    }

    private func stage(files: [StatusFile]) async {
        guard !files.isEmpty else { return }
        let paths = files.map(\.path)
        do {
            try await GitStatusService.shared.stageAll(files: files, in: repositoryURL)
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntryFactory.stageFiles(
                        repositoryURL: repositoryURL,
                        paths: paths
                    )
                )
            }
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func unstage(file: StatusFile) async {
        await unstage(files: [file])
    }

    private func unstage(files: [StatusFile]) async {
        guard !files.isEmpty else { return }
        let paths = files.map(\.path)
        do {
            try await GitStatusService.shared.unstageAll(files: files, in: repositoryURL)
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntryFactory.unstageFiles(
                        repositoryURL: repositoryURL,
                        paths: paths
                    )
                )
            }
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func commit(message: String) async {
        guard await onAuthorizeCommit() else { return }
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.commit(message: message, in: repositoryURL)
            let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            if let oldHead, let newHead, oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntryFactory.commit(
                            repositoryURL: repositoryURL,
                            oldHead: oldHead,
                            newHead: newHead,
                            message: message,
                            noVerify: false,
                            signOff: false
                        )
                    )
                }
            }
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func stageAll() async {
        await stage(files: changedFiles)
    }

    private func unstageAll() async {
        await unstage(files: gitStatus.staged)
    }

    private func stageSelected() async {
        await stage(files: actionSelection.selectedChangedFiles)
    }

    private func unstageSelected() async {
        await unstage(files: actionSelection.selectedStagedFiles)
    }

    private func discard(files: [StatusFile]) async {
        guard !files.isEmpty else { return }
        let paths = files.map(\.path)
        let snapshotStore = GitFileUndoSnapshotStore()
        do {
            let snapshot = try snapshotStore.capture(paths: paths, in: repositoryURL)
            for file in files {
                try await GitStatusService.shared.discard(file: file, in: repositoryURL)
            }
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: paths.count == 1 ? "Discard \((paths[0] as NSString).lastPathComponent)" : "Discard \(paths.count) files",
                        undoOperation: .restoreFileSnapshot(id: snapshot.id),
                        redoOperation: .discardFiles(paths: paths)
                    )
                )
            }
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func showInFinder(file: StatusFile) {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
    }

    private func openFile(file: StatusFile) {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        NSWorkspace.shared.open(fileURL)
    }

    private func discard(file: StatusFile) async {
        await discard(files: [file])
    }

    private func remove(files: [StatusFile]) async {
        guard !files.isEmpty else { return }
        let paths = files.map(\.path)
        let snapshotStore = GitFileUndoSnapshotStore()
        do {
            let snapshot = try snapshotStore.capture(paths: paths, in: repositoryURL)
            for file in files {
                try await GitStatusService.shared.remove(file: file, in: repositoryURL)
            }
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: paths.count == 1 ? "Remove \((paths[0] as NSString).lastPathComponent)" : "Remove \(paths.count) files",
                        undoOperation: .restoreFileSnapshot(id: snapshot.id),
                        redoOperation: .removeFiles(paths: paths)
                    )
                )
            }
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func remove(file: StatusFile) async {
        await remove(files: [file])
    }

    private func stopTracking(file: StatusFile) async {
        do {
            try await GitStatusService.shared.stopTracking(file: file, in: repositoryURL)
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func supportsExternalDiff(_ file: StatusFile) -> Bool {
        file.status == .modified || file.status == .deleted || file.status == .renamed
    }

    private func openExternalDiff(file: StatusFile) async {
        do {
            try await integrationSettings.openDiff(for: file, in: repositoryURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func confirmIgnore(file: StatusFile, pattern: String) async {
        do {
            try await GitStatusService.shared.ignore(file: file, pattern: pattern, in: repositoryURL)
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func resolveConflict(file: StatusFile, using: GitStatusService.ConflictResolution) async {
        do {
            try await GitStatusService.shared.resolveConflict(file: file, in: repositoryURL, using: using)
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func resolveConflictWithExternalTool(file: StatusFile) async {
        do {
            try await integrationSettings.openExternalMerge(
                for: file,
                in: repositoryURL
            )
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func resetToCommit(file: StatusFile, commit: String) async {
        do {
            try await GitStatusService.shared.resetToCommit(file: file, commit: commit, in: repositoryURL)
            await reloadRepositoryState()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func openConflictResolverWindow(for file: StatusFile) {
        let windowController = conflictResolverWindowController
        windowController.close()

        let allConflictFiles = (gitStatus.staged + gitStatus.unstaged + gitStatus.untracked)
            .filter { $0.status == .conflict }
            .reduce(into: [String: StatusFile]()) { dict, file in
                dict[file.path] = file
            }
            .values
            .sorted { $0.path < $1.path }

        guard let selectedConflictFile = allConflictFiles.first(where: { $0.path == file.path })
            ?? allConflictFiles.first else {
            Task { await reloadRepositoryState() }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Resolve Conflicts"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let commandContextIdentifier = ConflictUndoCommandContext.makeIdentifier()
        window.identifier = commandContextIdentifier

        let view = ConflictMergeToolView(
            allConflictFiles: allConflictFiles,
            selectedFile: selectedConflictFile,
            repositoryURL: repositoryURL,
            commandContextIdentifier: commandContextIdentifier.rawValue,
            aiProviderController: aiProviderController,
            aiProviderAccessDecision: aiProviderAccessDecision,
            onResolved: { [repositoryURL] in
                Task {
                    await reloadRepositoryState()
                }
            },
            onClose: { [weak windowController] in
                windowController?.close()
            }
        )

        window.contentView = NSHostingView(rootView: view
            .environmentObject(accountController)
            .environmentObject(featureAccessController)
        )
        window.center()
        windowController.window = window
        windowController.showWindow(nil)
    }
}
