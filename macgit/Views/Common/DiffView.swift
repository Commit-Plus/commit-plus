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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(hunks) { hunk in
                        HunkView(
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
                    }
                }
                .padding(12)
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

@MainActor
private final class DiffHorizontalScrollController {
    weak var scrollView: NSScrollView?

    func forward(_ event: NSEvent) {
        scrollView?.scrollWheel(with: event)
    }
}

private struct DiffHorizontalScrollProxy: NSViewRepresentable {
    let contentWidth: CGFloat
    let controller: DiffHorizontalScrollController
    let onOffsetChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffsetChange: onOffsetChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 1))
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observe(scrollView)
        controller.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onOffsetChange = onOffsetChange
        guard let documentView = scrollView.documentView,
              documentView.frame.width != contentWidth else { return }
        documentView.frame.size.width = contentWidth
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator {
        var onOffsetChange: (CGFloat) -> Void
        private var observer: NSObjectProtocol?

        init(onOffsetChange: @escaping (CGFloat) -> Void) {
            self.onOffsetChange = onOffsetChange
        }

        func observe(_ scrollView: NSScrollView) {
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                onOffsetChange(max(0, scrollView.contentView.bounds.origin.x))
            }
        }

        func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
        }

        deinit {
            stopObserving()
        }
    }
}

private struct DiffHorizontalScrollEventBridge: NSViewRepresentable {
    let controller: DiffHorizontalScrollController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        private let controller: DiffHorizontalScrollController
        private weak var view: NSView?
        private var monitor: Any?

        init(controller: DiffHorizontalScrollController) {
            self.controller = controller
        }

        func install(for view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let view = self.view,
                      event.window === view.window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else {
                    return event
                }
                let isShiftWheel = event.modifierFlags.contains(.shift)
                    && abs(event.scrollingDeltaY) > 0.01
                let isHorizontalGesture = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                guard isShiftWheel || isHorizontalGesture else { return event }
                controller.forward(event)
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            uninstall()
        }
    }
}


struct HunkView: View {
    private static let rowHeight: CGFloat = 22
    private static let headerHeight: CGFloat = 32
    private static let scrollerHeight: CGFloat = 16

    @Environment(\.appTextScale) private var textScale
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
    var onCommitHunk: ((DiffHunk, CommitPatchRequest.Direction) -> Void)? = nil
    var onCommitLines: ((Set<UUID>, CommitPatchRequest.Direction) -> Void)? = nil
    @State private var availableWidth: CGFloat = 0
    @State private var measuredContentWidth: CGFloat = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var horizontalViewport = CGRect(x: 0, y: 0, width: 1_024, height: 0)
    @State private var horizontalScrollController = DiffHorizontalScrollController()

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
        let lineRange = hunk.lines.indices
        let viewportWidth = max(1, availableWidth)
        let contentWidth = max(viewportWidth, measuredContentWidth)
        let hasHorizontalOverflow = measuredContentWidth > viewportWidth
        VStack(alignment: .leading, spacing: 0) {
            // Hunk header
            HStack(spacing: 10) {
                Text(hunk.header)
                    .font(.system(size: 11, weight: .medium, design: .monospaced).scaled(by: textScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if onCommitHunk != nil {
                    Menu("Changes") { commitPatchMenu }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Apply or revert this hunk")
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

            // Lines
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    lineRows(lineRange: lineRange)
                        .frame(width: contentWidth, alignment: .leading)
                        .offset(x: hasHorizontalOverflow ? -horizontalOffset : 0)
                }
                .frame(width: viewportWidth, height: linesHeight(lineRange), alignment: .topLeading)
                .clipped()
                .background {
                    if hasHorizontalOverflow {
                        DiffHorizontalScrollEventBridge(controller: horizontalScrollController)
                    }
                }

                if hasHorizontalOverflow {
                    horizontalScrollProxy(contentWidth: contentWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: textScale) {
                let text = hunk.widestLineCandidate
                let fontSize = 12 * textScale
                let fontName = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).fontName
                let width = await Task.detached(priority: .userInitiated) {
                    DiffLongLineLayout.measuredWidth(
                        text: text,
                        fontName: fontName,
                        fontSize: fontSize
                    )
                }.value
                guard !Task.isCancelled else { return }
                measuredContentWidth = ceil(width) + 114 * textScale
            }
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
        .contextMenu {
            hunkContextMenu
        }
    }

    private func linesHeight(_ lineRange: Range<Int>) -> CGFloat {
        CGFloat(lineRange.count) * Self.rowHeight * textScale
    }

    private func horizontalScrollProxy(contentWidth: CGFloat) -> some View {
        DiffHorizontalScrollProxy(
            contentWidth: contentWidth,
            controller: horizontalScrollController
        ) { newOffset in
            updateHorizontalOffset(newOffset)
        }
        .frame(height: Self.scrollerHeight * textScale)
    }

    private func updateHorizontalOffset(_ newOffset: CGFloat) {
        horizontalOffset = newOffset
        horizontalViewport = CGRect(
            x: floor(newOffset / 256) * 256,
            y: 0,
            width: ceil(max(1, availableWidth) / 256) * 256,
            height: 0
        )
    }

    private func lineRows(lineRange: Range<Int>) -> some View {
        ZStack(alignment: .topLeading) {
            DiffLineBackgroundRuns(
                runs: hunk.backgroundRuns,
                rowHeight: Self.rowHeight * textScale
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lineRange, id: \.self) { index in
                    let line = hunk.lines[index]
                    DiffLineView(
                        line: line,
                        fileExtension: fileExtension,
                        isSelected: selectedLineIDs.contains(line.id),
                        highlightCache: highlightCache,
                        showsChangeBackground: false,
                        horizontalViewport: horizontalViewport
                    )
                    .frame(height: Self.rowHeight * textScale)
                    .onTapGesture {
                        handleLineTap(at: index)
                    }
                }
            }
        }
    }

    private var hunkContextMenu: some View {
        Group {
            commitPatchMenu
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

    @ViewBuilder
    private var commitPatchMenu: some View {
        if let onCommitHunk {
            Button("Apply Hunk") { onCommitHunk(hunk, .apply) }
            Button("Revert Hunk") { onCommitHunk(hunk, .revert) }
            if let onCommitLines, hasSelectedLines {
                Divider()
                Button("Apply Selected Changes") { onCommitLines(selectedLineIDs, .apply) }
                Button("Revert Selected Changes") { onCommitLines(selectedLineIDs, .revert) }
            }
        }
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

private struct DiffLineBackgroundRuns: View {
    let runs: [DiffLineBackgroundRun]
    let rowHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(runs) { run in
                color(for: run.kind)
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(run.count) * rowHeight)
            }
        }
    }

    private func color(for kind: DiffLineBackgroundKind) -> Color {
        switch kind {
        case .added: Color.green.opacity(0.08)
        case .removed: Color.red.opacity(0.08)
        case .conflict: Color.purple.opacity(0.10)
        case .plain: Color.clear
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
