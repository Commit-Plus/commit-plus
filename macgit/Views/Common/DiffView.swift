//
//  DiffView.swift
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

private func isChangedDiffLine(_ line: DiffLine) -> Bool {
    (line.oldLineNumber == nil) != (line.newLineNumber == nil)
}

struct DiffView: View {
    @Environment(\.appTextScale) private var textScale
    @ObservedObject private var advancedSettings = AdvancedSettingsStore.shared
    let hunks: [DiffHunk]
    let file: StatusFile?
    let repositoryURL: URL?
    let undoManager: GitUndoManager?
    let onRefresh: () -> Void
    let onError: (String) -> Void
    let filePath: String?
    let gitRef: String?
    let commitPatchDisabledReason: String?
    let prefersTextDiff: Bool
    let onCommitPatch: (([DiffLine], CommitPatchRequest.Direction, String) -> Void)?

    init(
        hunks: [DiffHunk],
        file: StatusFile? = nil,
        repositoryURL: URL? = nil,
        undoManager: GitUndoManager? = nil,
        onRefresh: @escaping () -> Void = {},
        onError: @escaping (String) -> Void = { _ in },
        filePath: String? = nil,
        gitRef: String? = nil,
        prefersTextDiff: Bool = false,
        commitPatchDisabledReason: String? = nil,
        onCommitPatch: (([DiffLine], CommitPatchRequest.Direction, String) -> Void)? = nil
    ) {
        self.hunks = hunks
        self.file = file
        self.repositoryURL = repositoryURL
        self.undoManager = undoManager
        self.onRefresh = onRefresh
        self.onError = onError
        self.filePath = filePath
        self.gitRef = gitRef
        self.prefersTextDiff = prefersTextDiff
        self.commitPatchDisabledReason = commitPatchDisabledReason
        self.onCommitPatch = onCommitPatch
    }

    @State private var selectedLineIDs: Set<UUID> = []
    @State private var lastSelectedLineID: UUID?
    @State private var loadedImage: NSImage?
    @State private var highlightCache = DiffLineHighlightCache()

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp",
        "tiff", "tif", "ico", "heic", "heif", "raw",
        "cr2", "nef", "arw", "dng"
    ]

    private var isImageFile: Bool {
        if let file = file { return file.isImage }
        guard let path = filePath else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
    }

    var body: some View {
        if isImageFile && !prefersTextDiff {
            imagePreview
        } else if hunks.isEmpty {
            EmptyStateView(message: "No diff to display", detail: "Select a file to see changes")
        } else {
            DiffNativeTable(
                hunks: hunks, textScale: textScale,
                syntaxHighlighting: advancedSettings.diffSyntaxHighlighting,
                selectedLineIDs: selectedLineIDs
            ) { hunk, lineIndex, viewport in
                let renderer = HunkView(
                    textScale: textScale,
                    hunk: hunk,
                    file: file,
                    fileExtension: syntaxFileExtension,
                    highlightCache: advancedSettings.diffSyntaxHighlighting ? highlightCache : nil,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    selectedLineIDs: $selectedLineIDs,
                    lastSelectedLineID: $lastSelectedLineID,
                    onRefresh: onRefresh,
                    onError: onError,
                    commitPatchDisabledReason: commitPatchDisabledReason,
                    onCommitHunk: onCommitPatch.map { action in
                        { hunk, direction in
                            action(hunk.lines.filter(isChangedDiffLine), direction, "Selected hunk")
                        }
                    },
                    onCommitLines: onCommitPatch.map { action in
                        { ids, direction in
                            action(hunks.flatMap(\.lines).filter {
                                ids.contains($0.id) && isChangedDiffLine($0)
                            }, direction, "Selected lines")
                        }
                    }
                )
                if let lineIndex {
                    renderer.nativeLine(at: lineIndex, viewport: viewport)
                } else {
                    renderer.nativeHeader
                }
            }
            .onChange(of: hunks.first?.id) {
                selectedLineIDs.removeAll()
                lastSelectedLineID = nil
                highlightCache.removeAll()
            }
            .onChange(of: textScale) {
                highlightCache.removeAll()
            }
            .onChange(of: advancedSettings.diffSyntaxHighlighting) {
                highlightCache.removeAll()
            }
            .id(hunks.first?.id)
        }
    }

    private var syntaxFileExtension: String {
        SyntaxHighlighter.syntaxIdentifier(forFilePath: file?.path ?? filePath ?? "")
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let file = file, let url = repositoryURL {
            let fileURL = url.appendingPathComponent(file.path)
            diskImagePreview(fileURL: fileURL, filePath: file.path)
        } else if let ref = gitRef, let url = repositoryURL, let path = filePath {
            gitImagePreview(ref: ref, url: url, path: path)
        } else {
            EmptyStateView(icon: "photo", message: "Unable to preview image")
        }
    }

    private func diskImagePreview(fileURL: URL, filePath: String) -> some View {
        Group {
            if let nsImage = NSImage(contentsOf: fileURL) {
                FileImagePreview(image: nsImage)
            } else {
                EmptyStateView(icon: "photo", message: "Unable to preview image", detail: filePath)
            }
        }
    }

    private func gitImagePreview(ref: String, url: URL, path: String) -> some View {
        Group {
            if let image = loadedImage {
                FileImagePreview(image: image)
            } else {
                ProgressView("Loading image…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadImageFromGit(ref: ref, url: url, path: path)
        }
    }

    private func loadImageFromGit(ref: String, url: URL, path: String) async {
        do {
            let data = try await GitStatusService.shared.showFile(at: path, ref: ref, in: url)
            if let image = NSImage(data: data) {
                loadedImage = image
            }
        } catch {
            onError("Failed to load image: \(error.localizedDescription)")
        }
    }


}

struct HunkView: View {
    private static let rowHeight: CGFloat = 22
    private static let headerHeight: CGFloat = 32

    let textScale: CGFloat
    let hunk: DiffHunk
    let file: StatusFile?
    let fileExtension: String
    let highlightCache: DiffLineHighlightCache?
    let repositoryURL: URL?
    let undoManager: GitUndoManager?
    @Binding var selectedLineIDs: Set<UUID>
    @Binding var lastSelectedLineID: UUID?
    let onRefresh: () -> Void
    let onError: (String) -> Void
    var commitPatchDisabledReason: String? = nil
    var onCommitHunk: ((DiffHunk, CommitPatchRequest.Direction) -> Void)? = nil
    var onCommitLines: ((Set<UUID>, CommitPatchRequest.Direction) -> Void)? = nil

    private var isStaged: Bool {
        guard let file = file else { return false }
        return file.status == .staged || file.status == .added || file.status == .renamed
    }

    private var isUntracked: Bool {
        file?.status == .untracked
    }

    private var isConflict: Bool {
        file?.status == .conflict
    }

    private var canInteract: Bool {
        !isUntracked && !isConflict && file != nil && repositoryURL != nil
    }

    private var hasSelectedLines: Bool {
        !selectedLineIDs.isEmpty
    }

    var body: some View { nativeHeader }

    var nativeHeader: some View {
        HStack(spacing: 10) {
            Text(hunk.header)
                .font(.system(size: 11, weight: .medium, design: .monospaced).scaled(by: textScale))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("+\(hunk.backgroundRuns.filter { $0.kind == .added }.reduce(0) { $0 + $1.count })")
                .foregroundStyle(.green)
            Text("−\(hunk.backgroundRuns.filter { $0.kind == .removed }.reduce(0) { $0 + $1.count })")
                .foregroundStyle(.red)
            Spacer()

            if onCommitHunk != nil {
                Menu("Changes") { commitPatchMenu(line: nil) }
                    .disabled(commitPatchDisabledReason != nil)
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(commitPatchDisabledReason ?? "Apply or revert this hunk")
            }
            if canInteract {
                if isStaged {
                    Button("Unstage") {
                        unstageHunk()
                    }
                    .buttonStyle(GlassButtonStyle(tint: .yellow, fontSize: 10 * textScale))
                    .pointingHandCursor()
                } else {
                    Button("Stage") {
                        stageHunk()
                    }
                    .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 10 * textScale))
                    .pointingHandCursor()

                    Button("Discard") {
                        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file!.path)
                        performPatchAction(label: "Discard hunk in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                    }
                    .buttonStyle(GlassButtonStyle(tint: .red, fontSize: 10 * textScale))
                    .pointingHandCursor()
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.headerHeight * textScale)
        .background(.secondary.opacity(0.06))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }

        .contextMenu { hunkContextMenu }
        .padding(.top, 12 * textScale)
    }

    func nativeLine(at index: Int, viewport: CGRect) -> some View {
        let line = hunk.lines[index]
        return DiffLineView(
            line: line, fileExtension: fileExtension,
            isSelected: selectedLineIDs.contains(line.id),
            highlightCache: highlightCache, showsChangeBackground: true,
            horizontalViewport: viewport
        )
        .frame(height: Self.rowHeight * textScale)
        .contentShape(Rectangle())
        .onTapGesture { handleLineTap(at: index) }
        .contextMenu { lineContextMenu(for: line) }
    }

    private var hunkContextMenu: some View {
        Group {
            commitPatchMenu(line: nil)
            if canInteract {
                if isStaged {
                    Button("Unstage Hunk") {
                        unstageHunk()
                    }
                    if hasSelectedLines {
                        Divider()
                        Button("Unstage Selected Lines") {
                            unstageSelectedLines()
                        }
                    }
                } else {
                    Button("Stage Hunk") {
                        stageHunk()
                    }
                    Button("Discard Hunk") {
                        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file!.path)
                        performPatchAction(label: "Discard hunk in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                    }

                    if hasSelectedLines {
                        Divider()
                        Button("Stage Selected Lines") {
                            stageSelectedLines()
                        }
                        Button("Discard Selected Lines") {
                            let lines = expandedSelectedLines(for: hunk)
                            let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file!.path)
                            performPatchAction(label: "Discard selected lines in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                        }
                    }
                }
            }
            Divider()
            Button("Copy Hunk") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    hunk.lines.map(\.text).joined(separator: "\n"),
                    forType: .string
                )
            }
        }
    }

    private func lineContextMenu(for line: DiffLine) -> some View {
        Group {
            commitPatchMenu(line: line)
            if canInteract {
                if isStaged {
                    Button("Unstage Hunk") {
                        unstageHunk()
                    }
                    if selectedLineIDs.contains(line.id) && hasSelectedLines {
                        Divider()
                        Button("Unstage Selected Lines") {
                            unstageSelectedLines()
                        }
                    }
                } else {
                    Button("Stage Hunk") {
                        stageHunk()
                    }
                    Button("Discard Hunk") {
                        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file!.path)
                        performPatchAction(label: "Discard hunk in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                    }

                    if selectedLineIDs.contains(line.id) && hasSelectedLines {
                        Divider()
                        Button("Stage Selected Lines") {
                            stageSelectedLines()
                        }
                        Button("Discard Selected Lines") {
                            let lines = expandedSelectedLines(for: hunk)
                            let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file!.path)
                            performPatchAction(label: "Discard selected lines in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                        }
                    }
                }
            }
            Divider()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line.text, forType: .string)
            }
        }
    }

    @ViewBuilder
    private func commitPatchMenu(line: DiffLine?) -> some View {
        if let onCommitHunk {
            Button("Apply Hunk") { onCommitHunk(hunk, .apply) }
                .disabled(commitPatchDisabledReason != nil)
            Button("Revert Hunk") { onCommitHunk(hunk, .revert) }
                .disabled(commitPatchDisabledReason != nil)
            if let onCommitLines, hasSelectedLines || line?.type == .added || line?.type == .removed {
                Divider()
                Button("Apply Selected Changes") { onCommitLines(commitLineIDs(line), .apply) }
                    .disabled(commitPatchDisabledReason != nil)
                Button("Revert Selected Changes") { onCommitLines(commitLineIDs(line), .revert) }
                    .disabled(commitPatchDisabledReason != nil)
            }
            if let commitPatchDisabledReason { Text(commitPatchDisabledReason) }
        }
    }

    private func commitLineIDs(_ line: DiffLine?) -> Set<UUID> {
        if let line, !selectedLineIDs.contains(line.id), isChangedDiffLine(line) {
            return [line.id]
        }
        return selectedLineIDs
    }

    private func handleLineTap(at index: Int) {
        let line = hunk.lines[index]
        guard isChangedDiffLine(line) else { return }

        let flags = NSEvent.modifierFlags
        let isShift = flags.contains(.shift)
        let isCommand = flags.contains(.command)

        if isShift {
            guard let lastID = lastSelectedLineID,
                  let lastIndex = hunk.lines.firstIndex(where: { $0.id == lastID }) else {
                selectedLineIDs = [line.id]
                lastSelectedLineID = line.id
                return
            }
            let start = min(lastIndex, index)
            let end = max(lastIndex, index)
            let rangeIDs = Set(hunk.lines[start...end].filter(isChangedDiffLine).map(\.id))
            if isCommand {
                selectedLineIDs.formSymmetricDifference(rangeIDs)
            } else {
                selectedLineIDs = rangeIDs
            }
            lastSelectedLineID = line.id
        } else if isCommand {
            if selectedLineIDs.contains(line.id) {
                selectedLineIDs.remove(line.id)
            } else {
                selectedLineIDs.insert(line.id)
            }
            lastSelectedLineID = line.id
        } else {
            selectedLineIDs = [line.id]
            lastSelectedLineID = line.id
        }
    }

    private func expandedSelectedLines(for hunk: DiffHunk) -> [DiffLine] {
        var blocks: [Set<UUID>] = []
        var currentBlock = Set<UUID>()

        for line in hunk.lines {
            switch line.type {
            case .added, .removed:
                currentBlock.insert(line.id)
            case .context, .header, .conflictMarker:
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock)
                    currentBlock = []
                }
            }
        }
        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }

        var expandedIDs = Set<UUID>()
        for block in blocks {
            if !block.isDisjoint(with: selectedLineIDs) {
                expandedIDs.formUnion(block)
            }
        }

        return hunk.lines.filter { expandedIDs.contains($0.id) }
    }

    private func stageHunk() {
        guard let file else { return }
        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file.path)
        performPatchAction(
            label: "Stage hunk in \(file.displayName)",
            patch: patch,
            cached: true,
            reverse: false
        )
    }

    private func unstageHunk() {
        guard let file else { return }
        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file.path)
        performPatchAction(
            label: "Unstage hunk in \(file.displayName)",
            patch: patch,
            cached: true,
            reverse: true
        )
    }

    private func stageSelectedLines() {
        guard let file else { return }
        let lines = expandedSelectedLines(for: hunk)
        let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file.path)
        performPatchAction(
            label: "Stage selected lines in \(file.displayName)",
            patch: patch,
            cached: true,
            reverse: false
        )
    }

    private func unstageSelectedLines() {
        guard let file else { return }
        let lines = expandedSelectedLines(for: hunk)
        let patch = DiffPatchBuilder.patchString(for: hunk, selectedLines: lines, filePath: file.path)
        performPatchAction(
            label: "Unstage selected lines in \(file.displayName)",
            patch: patch,
            cached: true,
            reverse: true
        )
    }

    private func performPatchAction(
        label: String,
        patch: String,
        cached: Bool,
        reverse: Bool
    ) {
        guard let repositoryURL else { return }
        perform {
            try await GitStatusService.shared.applyPatch(
                patch,
                in: repositoryURL,
                cached: cached,
                reverse: reverse
            )
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntryFactory.applyPatch(
                        repositoryURL: repositoryURL,
                        label: label,
                        patch: patch,
                        cached: cached,
                        reverse: reverse
                    )
                )
            }
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
                await MainActor.run {
                    selectedLineIDs.removeAll()
                    onRefresh()
                }
            } catch {
                await MainActor.run {
                    onError(error.localizedDescription)
                }
            }
        }
    }
}

struct DiffLineView: View {
    @Environment(\.appTextScale) private var textScale
    let line: DiffLine
    let fileExtension: String
    let isSelected: Bool
    var cachedHighlightedText: AttributedString? = nil
    var highlightCache: DiffLineHighlightCache? = nil
    var showsDiffGutter = true
    var showsChangeBackground = true
    var horizontalViewport = CGRect(x: 0, y: 0, width: 1_024, height: 0)
    @State private var deferredHighlightedText: AttributedString? = nil

    var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        guard showsChangeBackground else { return .clear }
        switch line.type {
        case .added:
            return Color.green.opacity(0.08)
        case .removed:
            return Color.red.opacity(0.08)
        case .context:
            return Color.clear
        case .header:
            return Color.clear
        case .conflictMarker:
            return Color.purple.opacity(0.10)
        }
    }

    var textColor: Color {
        switch line.type {
        case .added:
            return Color(nsColor: NSColor(calibratedRed: 0.12, green: 0.55, blue: 0.18, alpha: 1.0))
        case .removed:
            return Color(nsColor: NSColor(calibratedRed: 0.75, green: 0.18, blue: 0.18, alpha: 1.0))
        case .context:
            return .primary
        case .header:
            return .secondary
        case .conflictMarker:
            return Color.purple
        }
    }

    var prefix: String {
        switch line.type {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        case .header: return ""
        case .conflictMarker: return "!"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsDiffGutter {
                Text(line.oldLineNumber.map(String.init) ?? "")
                    .font(.system(size: 10, design: .monospaced).scaled(by: textScale))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, alignment: .trailing)
                    .padding(.trailing, 6)
            }

            // New line number
            Text(line.newLineNumber.map(String.init) ?? "")
                .font(.system(size: 10, design: .monospaced).scaled(by: textScale))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)

            // Prefix
            if showsDiffGutter && !prefix.isEmpty {
                Text(prefix)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced).scaled(by: textScale))
                    .foregroundStyle(textColor.opacity(0.7))
                    .frame(width: 14, alignment: .center)
            }

            // Content
            if DiffLongLineLayout.isLong(line.text) {
                DiffLongLineContent(
                    lineID: line.id,
                    text: line.text,
                    viewport: horizontalViewport.offsetBy(dx: -contentLeadingInset, dy: 0),
                    fontSize: 12 * textScale
                )
            } else {
                Text(highlightedText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .task(id: "\(line.id)-\(textScale)-\(highlightCache != nil)") {
                        await loadHighlightedTextIfNeeded()
                    }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(backgroundColor)
    }

    private var contentLeadingInset: CGFloat {
        8 + (showsDiffGutter ? 84 : 42) + (showsDiffGutter && !prefix.isEmpty ? 14 : 0)
    }

    private var highlightedText: AttributedString {
        var attributed: AttributedString
        if let cachedHighlightedText {
            attributed = cachedHighlightedText
        } else if highlightCache != nil, let deferredHighlightedText {
            attributed = deferredHighlightedText
        } else if let cached = highlightCache?.cachedText(for: line.id) {
            attributed = cached
        } else if highlightCache != nil {
            attributed = AttributedString(line.text)
            attributed.font = Font(NSFont.monospacedSystemFont(ofSize: 12 * textScale, weight: .regular))
            attributed.foregroundColor = .primary
        } else {
            attributed = AttributedString(line.text)
            attributed.font = Font(NSFont.monospacedSystemFont(ofSize: 12 * textScale, weight: .regular))
            attributed.foregroundColor = .primary
        }

        // Keep diff metadata readable while allowing syntax colors in the code.
        if line.type == .header || line.type == .conflictMarker {
            attributed.foregroundColor = textColor
        }
        return attributed
    }

    private func loadHighlightedTextIfNeeded() async {
        guard cachedHighlightedText == nil,
              let highlightCache,
              !DiffLongLineLayout.isLong(line.text) else {
            return
        }
        if let cached = highlightCache.cachedText(for: line.id) {
            deferredHighlightedText = cached
            return
        }

        // Let the plain monospaced row reach the first frame before regex work.
        await Task.yield()
        guard !Task.isCancelled else { return }
        let highlighted = highlightCache.text(for: line, fileExtension: fileExtension, fontSize: 12 * textScale)
        guard !Task.isCancelled else { return }
        deferredHighlightedText = highlighted
    }
}
