// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

enum HistoryDetailTab: String, CaseIterable, Identifiable {
    case commit, changes, fileTree
    var id: String { rawValue }
    var title: String {
        switch self {
        case .commit: "Commit"
        case .changes: "Changes"
        case .fileTree: "File Tree"
        }
    }
}

struct HistoryCommitDetailView: View {
    @Bindable var model: HistoryCommitDetailModel
    let repositoryURL: URL
    let undoManager: GitUndoManager?
    let syncState: SyncState?
    let runOperation: RepositoryOperationRunner
    var fileActions: RevisionFileActionCenter? = nil
    @Environment(\.appTextScale) private var textScale
    let onOpenFile: (String, SearchFileLineTarget?) -> Void
    /// Collapses the panel to its tab bar; choosing a tab or the collapse button opens it again.
    var isCollapsed: Binding<Bool> = .constant(false)
    var onBrowseRevision: (Commit) -> Void = { _ in }
    var onSelectCommit: (String) -> Void = { _ in }
    /// False embeds only the changes, for hosts that provide their own commit summary.
    var showsTabs = true

    /// Per window; the last choice is saved only as the default for panels opened later.
    @State private var tabRaw = UserDefaults.standard.string(forKey: Self.tabDefaultsKey)
        ?? HistoryDetailTab.changes.rawValue
    @State private var imageComparisonMode: ImageComparisonMode = .overlay
    /// Last file chosen in the File Tree tab, re-selected when the commit changes.
    @State private var treePath: String?
    /// Kept while the commit stays selected so returning to the File Tree tab does not reload it.
    @State private var tree: (hash: String, controller: RevisionBrowserController)?

    static let tabDefaultsKey = "history.detailTab"

    static func collapsedHeight(textScale: CGFloat) -> CGFloat { ceil(34 * max(1, textScale)) }

    private var collapsed: Bool { showsTabs && isCollapsed.wrappedValue }

    private var tab: HistoryDetailTab {
        showsTabs ? HistoryDetailTab(rawValue: tabRaw) ?? .changes : .changes
    }

    var body: some View {
        @Bindable var patch = model.patchController
        Group {
            if let commit = model.commit {
                VStack(spacing: 0) {
                    if showsTabs { tabBar(commit) }
                    if tab != .commit { CommitSummaryBar(commit: commit) }
                    // Changes and the loaded tree stay mounted so switching tabs keeps their
                    // selection and scroll position instead of rebuilding them.
                    ZStack {
                        VStack(spacing: 0) { changes(commit) }
                            .repositoryScreenVisibility(isActive: tab == .changes)
                        if let tree, tree.hash == commit.hash {
                            RevisionTreeBrowser(controller: tree.controller, autosaveName: "HistoryDetailTreeSplit",
                                actions: fileActions, loadDelay: .milliseconds(120), initialPath: treePath,
                                releasesOnDisappear: false,
                                onOpenFile: { onOpenFile($0, nil) }, onSelectFile: { treePath = $0 })
                                .id(commit.hash)
                                .repositoryScreenVisibility(isActive: tab == .fileTree)
                        } else if tab == .fileTree {
                            ProgressView("Loading repository…").frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if tab == .commit {
                            CommitInfoView(commit: commit, fullMessage: model.fullMessage,
                                isLoadingMessage: model.isLoadingFullMessage, onSelectParent: onSelectCommit)
                                .zIndex(2)
                        }
                    }
                }
                // Collapsed, only the tab bar fits; the content stays mounted below it, clipped by the pane.
                // minHeight 0 lets the frame shrink to the pane, so the content is top-aligned, not centered.
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
            } else if collapsed {
                tabBar(nil).frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            } else {
                EmptyStateView(icon: "doc.text", message: "Select a commit",
                    detail: "Click a commit above to see its changes")
            }
        }
        .onAppear { updateActiveContent() }
        .onChange(of: tabRaw) {
            if showsTabs { UserDefaults.standard.set(tabRaw, forKey: Self.tabDefaultsKey) }
            updateActiveContent()
        }
        .onChange(of: collapsed) { prepareTree() }
        .onChange(of: model.commit?.hash) { prepareTree() }
        .onDisappear { releaseTree() }
        .replacingSheet(item: $patch.prepared) { _ in
            if let prepared = model.patchController.prepared {
                CommitPatchReviewSheet(prepared: prepared, isBusy: patch.isBusy,
                    errorMessage: patch.reviewError,
                    onCancel: { patch.prepared = nil },
                    onApply: { patch.apply(undoManager: undoManager, syncState: syncState, run: runOperation) },
                    onOpenConflict: { patch.openConflict($0) })
                    .disabled(patch.isResolving)
                    .onDisappear { patch.closeConflict() }
            }
        }
        .alert("Selected changes", isPresented: $patch.showingError) {
            Button("OK", role: .cancel) {}
        } message: { Text(patch.errorMessage) }
    }

    private func updateActiveContent() {
        model.needsFullMessage = showsTabs && tab == .commit
        prepareTree()
    }

    /// Creates the tree for the selected commit when its tab is shown, and drops a tree of another commit.
    private func prepareTree() {
        let hash = model.commit?.hash
        if let tree, tree.hash != hash { releaseTree() }
        guard tab == .fileTree, !collapsed, tree == nil, let hash else { return }
        tree = (hash, RevisionBrowserController(repositoryURL: repositoryURL, revision: hash))
    }

    private func releaseTree() {
        tree?.controller.releaseResources()
        tree = nil
    }

    private func tabBar(_ commit: Commit?) -> some View {
        HStack(spacing: 4) {
            ForEach(HistoryDetailTab.allCases) { item in
                let isSelected = tab == item && !collapsed
                Button {
                    tabRaw = item.rawValue
                    isCollapsed.wrappedValue = false
                } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium).scaled(by: textScale))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 8)
            Button("Open in New Window", systemImage: "arrow.up.forward.square") {
                if let commit { onBrowseRevision(commit) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
            .pointingHandCursor()
            .disabled(commit == nil)
            .help("Show the repository at this revision in a new window")
            Divider().frame(height: 14)
            Button(collapsed ? "Show Details" : "Hide Details",
                   systemImage: collapsed ? "rectangle" : "rectangle.bottomthird.inset.filled") {
                isCollapsed.wrappedValue.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
            .pointingHandCursor()
            .help(collapsed ? "Show the commit details panel" : "Collapse the commit details panel to its header")
        }
        .padding(.horizontal, 8)
        .frame(height: Self.collapsedHeight(textScale: textScale))
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
    }

    @ViewBuilder private func changes(_ commit: Commit) -> some View {
        let patch = model.patchController
        if patch.isPreparing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking and merging selected changes…")
                    .font(.callout.scaled(by: textScale))
                Spacer()
                Button("Cancel") { patch.cancelPreparation() }
            }
            .padding(10)
        }
        PersistentHSplit(autosaveName: "HistoryDetailSplit",
            minimumLeftWidth: 220, minimumRightWidth: 300,
            left: {
                CommitFileListView(changes: model.fileChanges, lineCounts: model.lineCounts,
                    selectedFile: $model.selectedFile,
                    showsLayoutControls: true,
                    onOpenFile: { onOpenFile($0.path, .commitChange(commit.hash)) },
                    onPatch: { files, direction in
                        patch.prepare(CommitPatchRequest(commit: commit.hash, files: files,
                            direction: direction, lines: nil,
                            scope: "\(files.count) selected file(s)"), in: repositoryURL)
                    }, patchDisabledReason: { model.patchDisabledReason(for: $0) },
                    fileMenu: fileActions.map { actions in
                        { change in
                            AnyView(RevisionFileMenuItems(actions: actions, path: change.path,
                                revision: commit.hash, existsAtRevision: change.status != .deleted,
                                onOpen: { onOpenFile(change.path, .commitChange(commit.hash)) },
                                onShowInFileTree: showsTabs ? {
                                    treePath = change.path
                                    tabRaw = HistoryDetailTab.fileTree.rawValue
                                } : nil))
                        }
                    })
                    .frame(minWidth: 220)
            }, right: { diffViewer(commit).frame(minWidth: 300) })
    }

    @ViewBuilder private func diffViewer(_ commit: Commit) -> some View {
        if let file = model.selectedFile {
            let matches = model.diff?.commit == commit.hash && model.diff?.path == file.path
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    FilePathLabel(path: file.path)
                    Spacer(minLength: 8)
                    if file.status != .added && StatusFile(path: file.path, status: .modified, originalPath: nil).isImage {
                        ImageComparisonModeButton(mode: $imageComparisonMode)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
                if !matches {
                    ProgressView("Loading diff…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DiffView(hunks: model.diff?.hunks ?? [], file: nil,
                        repositoryURL: repositoryURL, undoManager: nil, onRefresh: {}, onError: { _ in },
                        filePath: file.path, gitRef: commit.hash,
                        imageComparisonMode: imageComparisonMode, imageOldPath: file.oldPath, imageFileStatus: file.status,
                        commitPatchDisabledReason: model.patchDisabledReason(for: [file]),
                        onCommitPatch: { lines, direction, scope in
                            guard model.commit?.hash == commit.hash, model.selectedFile == file,
                                  model.diff?.commit == commit.hash, model.diff?.path == file.path else { return }
                            model.patchController.prepare(CommitPatchRequest(commit: commit.hash, files: [file],
                                direction: direction, lines: Set(lines.map(CommitPatchRequest.Line.init)),
                                scope: scope), in: repositoryURL)
                        })
                }
            }
        } else {
            EmptyStateView(icon: "doc.text", message: "Select a file",
                detail: "Click a file on the left to see its diff")
        }
    }
}
