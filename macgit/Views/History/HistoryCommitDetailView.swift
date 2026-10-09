// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct HistoryCommitDetailView: View {
    @Bindable var model: HistoryCommitDetailModel
    let repositoryURL: URL
    let undoManager: GitUndoManager?
    let syncState: SyncState?
    let runOperation: RepositoryOperationRunner
    @Environment(\.appTextScale) private var textScale
    let onOpenFile: (String) -> Void

    var body: some View {
        @Bindable var patch = model.patchController
        Group {
            if let commit = model.commit {
                VStack(spacing: 0) {
                    header(commit)
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
                                onOpenFile: { onOpenFile($0.path) },
                                onPatch: { files, direction in
                                    patch.prepare(CommitPatchRequest(commit: commit.hash, files: files,
                                        direction: direction, lines: nil,
                                        scope: "\(files.count) selected file(s)"), in: repositoryURL)
                                }, patchDisabledReason: { model.patchDisabledReason(for: $0) })
                                .frame(minWidth: 220)
                        }, right: { diffViewer(commit).frame(minWidth: 300) })
                }
            } else {
                EmptyStateView(icon: "doc.text", message: "Select a commit",
                    detail: "Click a commit above to see its changes")
            }
        }
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

    private func header(_ commit: Commit) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 18)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(commit.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "<empty message>" : commit.message)
                    .font(.system(size: 13, weight: .semibold).scaled(by: textScale))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(commit.author).foregroundStyle(.secondary)
                    Text("•").foregroundStyle(.tertiary)
                    Text(commit.email).foregroundStyle(.secondary)
                    Text("•").foregroundStyle(.tertiary)
                    Text(commit.date, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                    Text("•").foregroundStyle(.tertiary)
                    Text(commit.hash).font(.system(size: 11, design: .monospaced).scaled(by: textScale))
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 11).scaled(by: textScale)).lineLimit(1)
            }
            Spacer()
            Button("Show commit details", systemImage: "info.circle") {
                model.showingCommitInfo = true
                model.loadFullMessage()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active: NSCursor.pointingHand.set()
                case .ended: NSCursor.arrow.set()
                }
            }
            .padding(.trailing, 8)
            .help("Show full commit message and details")
            .accessibilityLabel("Show full commit message and details")
            .popover(isPresented: $model.showingCommitInfo, arrowEdge: .bottom) {
                CommitInfoPopoverView(commit: commit, fullMessage: model.fullMessage,
                    isLoadingMessage: model.isLoadingFullMessage,
                    onCopyMessage: { copy(model.fullMessage ?? commit.message) },
                    onCopyHash: { copy(commit.hash) })
            }
            if !commit.refs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(commit.refs.prefix(5), id: \.self) { RefLabel(text: $0) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
    }

    @ViewBuilder private func diffViewer(_ commit: Commit) -> some View {
        if let file = model.selectedFile {
            let matches = model.diff?.commit == commit.hash && model.diff?.path == file.path
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.primary).font(.system(size: 14, weight: .medium))
                    Text(file.path).font(.system(size: 13, weight: .semibold).scaled(by: textScale))
                        .lineLimit(1)
                    Spacer()
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

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
