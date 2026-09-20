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

struct DiffView: View {
    let hunks: [DiffHunk]
    let file: StatusFile?
    let repositoryURL: URL?
    let undoManager: GitUndoManager?
    let onRefresh: () -> Void
    let onError: (String) -> Void
    let filePath: String?
    let gitRef: String?

    init(
        hunks: [DiffHunk],
        file: StatusFile? = nil,
        repositoryURL: URL? = nil,
        undoManager: GitUndoManager? = nil,
        onRefresh: @escaping () -> Void = {},
        onError: @escaping (String) -> Void = { _ in },
        filePath: String? = nil,
        gitRef: String? = nil
    ) {
        self.hunks = hunks
        self.file = file
        self.repositoryURL = repositoryURL
        self.undoManager = undoManager
        self.onRefresh = onRefresh
        self.onError = onError
        self.filePath = filePath
        self.gitRef = gitRef
    }

    @State private var selectedLineIDs: Set<UUID> = []
    @State private var lastSelectedLineID: UUID?
    @State private var loadedImage: NSImage?
    @State private var renderedBlockRange = 0..<5

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
        if isImageFile {
            imagePreview
        } else if hunks.isEmpty {
            EmptyStateView(message: "No diff to display", detail: "Select a file to see changes")
        } else {
            let blocks = DiffRenderBlock.layout(hunks: hunks)
            let range = renderedBlockRange.clamped(to: blocks.indices)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let first = range.first {
                        Color.clear.frame(height: blocks[first].offset)
                    }
                    ForEach(blocks[range]) { block in
                            HunkView(
                                hunk: block.hunk,
                                lineRange: block.lineRange,
                                file: file,
                                fileExtension: syntaxFileExtension,
                                repositoryURL: repositoryURL,
                                undoManager: undoManager,
                                selectedLineIDs: $selectedLineIDs,
                                lastSelectedLineID: $lastSelectedLineID,
                                onRefresh: onRefresh,
                                onError: onError
                            )
                            .frame(height: block.height)
                            .padding(.bottom, DiffRenderBlock.spacing)
                    }
                    if let last = range.last, let end = blocks.last {
                        Color.clear.frame(height: end.endOffset - blocks[last].endOffset)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
            .onScrollGeometryChange(for: Range<Int>.self) { geometry in
                DiffRenderBlock.renderedRange(
                    in: blocks,
                    viewport: geometry.visibleRect.offsetBy(dx: 0, dy: -12)
                )
            } action: { _, range in
                renderedBlockRange = range
            }
            .onChange(of: hunks.first?.id) {
                renderedBlockRange = 0..<min(5, blocks.count)
            }
            .id(hunks.first?.id)
        }
    }

    private var syntaxFileExtension: String {
        if let file {
            return file.fileExtension
        }
        guard let filePath else { return "" }
        return URL(fileURLWithPath: filePath).pathExtension.lowercased()
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
                imageDisplayView(nsImage)
            } else {
                EmptyStateView(icon: "photo", message: "Unable to preview image", detail: filePath)
            }
        }
    }

    private func gitImagePreview(ref: String, url: URL, path: String) -> some View {
        Group {
            if let image = loadedImage {
                imageDisplayView(image)
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

    private func imageDisplayView(_ nsImage: NSImage) -> some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, alignment: .top)
                    .clipped()
            }
        }
        .padding(12)
    }
}

struct ReferenceDiffView: View {
    let repositoryURL: URL
    let baseRef: String
    let targetRef: String
    let title: String
    let onClose: () -> Void

    @State private var changes: [CommitFileChange] = []
    @State private var selectedFile: CommitFileChange?
    @State private var diffHunks: [DiffHunk] = []
    @State private var isLoading = true
    @State private var isLoadingDiff = false
    @State private var diffLoadID = UUID()
    @AppStorage("referenceDiff.fileListWidth") private var fileListWidth: Double = 240

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                Text(title).font(.headline)
                Spacer()
                Text("\(changes.count) file\(changes.count == 1 ? "" : "s") changed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Close", systemImage: "xmark", action: onClose)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.separator).frame(height: 0.5)
            }

            if isLoading {
                ProgressView("Loading comparison…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if changes.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    message: "No differences",
                    detail: "These references point to the same tree"
                )
            } else {
                GeometryReader { geometry in
                    let availableWidth = max(0, geometry.size.width - 6)
                    HStack(spacing: 0) {
                        CommitFileListView(changes: changes, selectedFile: $selectedFile)
                            .frame(width: CGFloat(fileListWidth))

                        ColumnResizer(
                            leftWidth: Binding(
                                get: { CGFloat(fileListWidth) },
                                set: { fileListWidth = Double($0) }
                            ),
                            rightWidth: Binding(
                                get: { max(40, availableWidth - CGFloat(fileListWidth)) },
                                set: { fileListWidth = Double(availableWidth - $0) }
                            ),
                            minimumLeftWidth: 240
                        )

                        Group {
                            if let selectedFile {
                                if isLoadingDiff {
                                    ProgressView("Loading file diff…")
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    DiffView(
                                        hunks: diffHunks,
                                        repositoryURL: repositoryURL,
                                        filePath: selectedFile.path
                                    )
                                }
                            } else {
                                EmptyStateView(
                                    icon: "doc.text",
                                    message: "Select a file",
                                    detail: "Click a file to see its changes"
                                )
                            }
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task(id: "\(baseRef)→\(targetRef)") {
            isLoading = true
            changes = await GitStatusService.shared.changedFiles(
                from: baseRef,
                to: targetRef,
                in: repositoryURL
            )
            selectedFile = nil
            diffHunks = []
            isLoadingDiff = false
            isLoading = false
        }
        .onChange(of: selectedFile) { _, file in
            guard let file else {
                diffHunks = []
                isLoadingDiff = false
                return
            }

            let loadID = UUID()
            diffLoadID = loadID
            diffHunks = []
            isLoadingDiff = true
            Task {
                let hunks = await GitStatusService.shared.diff(
                    for: file.path,
                    from: baseRef,
                    to: targetRef,
                    in: repositoryURL
                )
                guard !Task.isCancelled, diffLoadID == loadID else { return }
                diffHunks = hunks
                isLoadingDiff = false
            }
        }
    }
}

struct HunkView: View {
    let hunk: DiffHunk
    let lineRange: Range<Int>
    let file: StatusFile?
    let fileExtension: String
    let repositoryURL: URL?
    let undoManager: GitUndoManager?
    @Binding var selectedLineIDs: Set<UUID>
    @Binding var lastSelectedLineID: UUID?
    let onRefresh: () -> Void
    let onError: (String) -> Void
    @State private var availableWidth: CGFloat = 0

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk header
            HStack(spacing: 10) {
                Text(hunk.header)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if hunk.lines.count > DiffRenderBatch.lineLimit {
                    Text("\(lineRange.lowerBound + 1)–\(lineRange.upperBound) of \(hunk.lines.count) diff lines")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if canInteract {
                    if isStaged {
                        Button("Unstage") {
                            unstageHunk()
                        }
                        .buttonStyle(GlassButtonStyle(tint: .yellow, fontSize: 10))
                    } else {
                        Button("Stage") {
                            stageHunk()
                        }
                        .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 10))

                        Button("Discard") {
                            let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file!.path)
                            performPatchAction(label: "Discard hunk in \(file!.displayName)", patch: patch, cached: false, reverse: true)
                        }
                        .buttonStyle(GlassButtonStyle(tint: .red, fontSize: 10))
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: DiffRenderBlock.headerHeight)
            .background(.secondary.opacity(0.06))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 0.5)
            }
            .contextMenu {
                hunkContextMenu
            }

            // Lines
            ScrollView([.horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lineRange, id: \.self) { index in
                        let line = hunk.lines[index]
                        DiffLineView(
                            line: line,
                            fileExtension: fileExtension,
                            isSelected: selectedLineIDs.contains(line.id)
                        )
                        .frame(height: DiffRenderBlock.rowHeight)
                        .frame(minWidth: availableWidth, alignment: .leading)
                        .onTapGesture {
                            handleLineTap(at: index)
                        }
                        .contextMenu {
                            lineContextMenu(for: line)
                        }
                    }
                }
            }
            .frame(height: CGFloat(lineRange.count) * DiffRenderBlock.rowHeight + DiffRenderBlock.scrollerHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            availableWidth = geometry.size.width
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            availableWidth = newWidth
                        }
                }
            }
        }
        .background(.secondary.opacity(0.06))
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    private var hunkContextMenu: some View {
        Group {
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
        }
    }

    private func lineContextMenu(for line: DiffLine) -> some View {
        Group {
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

    private func handleLineTap(at index: Int) {
        let line = hunk.lines[index]
        guard line.type == .added || line.type == .removed else { return }

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
            let rangeIDs = Set(hunk.lines[start...end].filter { $0.type == .added || $0.type == .removed }.map(\.id))
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
    let line: DiffLine
    let fileExtension: String
    let isSelected: Bool
    var cachedHighlightedText: AttributedString? = nil

    var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
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
            // Old line number
            Text(line.oldLineNumber.map(String.init) ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)

            // New line number
            Text(line.newLineNumber.map(String.init) ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)

            // Prefix
            if !prefix.isEmpty {
                Text(prefix)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(textColor.opacity(0.7))
                    .frame(width: 14, alignment: .center)
            }

            // Content
            Text(highlightedText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(backgroundColor)
    }

    private var highlightedText: AttributedString {
        var attributed = cachedHighlightedText ?? SyntaxHighlighter(fileExtension: fileExtension)
            .attributedString(for: line.text, fontSize: 12)

        // Keep diff metadata readable while allowing syntax colors in the code.
        if line.type == .header || line.type == .conflictMarker {
            attributed.foregroundColor = textColor
        }
        return attributed
    }
}
