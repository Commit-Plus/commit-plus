// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// The outer document owns only Y. Each visible hunk owns a real horizontal
/// NSScrollView; neither scrolling axis round-trips through SwiftUI state.
struct DiffNativeTable<Content: View>: NSViewRepresentable {
    let hunks: [DiffHunk]
    let textScale: CGFloat
    let syntaxHighlighting: Bool
    let fileExtension: String
    let selectedLineIDs: Set<UUID>
    let onLineTap: (DiffHunk, Int, NSEvent.ModifierFlags) -> Void
    let lineMenu: (DiffHunk, Int) -> NSMenu
    @ViewBuilder let content: (DiffHunk) -> Content
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = context.coordinator.document
        context.coordinator.observe(scroll)
        context.coordinator.connectTextStore()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if scroll.appearance?.name != appearanceName {
            scroll.appearance = NSAppearance(named: appearanceName)
        }
        context.coordinator.apply(self, scroll: scroll)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject {
        let document = DiffFlippedView()
        private var model: DiffNativeTable?
        private var geometry = DiffHunkGeometry(lineCounts: [], scale: 1)
        private var hunkIDs: [UUID] = []
        private var revisions: [DiffContentRevision] = []
        private let textStore = DiffNativeTextStore()
        private var scale: CGFloat = 0
        private var widths: [CGFloat] = []
        private var offsets: [Int: CGFloat] = [:]
        private var panels: [Int: DiffNativeHunkView] = [:]
        private var recycledPanels: [DiffNativeHunkView] = []
        private var widthTask: Task<Void, Never>?
        private var observer: NSObjectProtocol?
        private var updating = false

        /// Keep one viewport of fully configured content on either side of the
        /// clip. This moves hosting-view reuse away from the hunk boundary the
        /// user is currently watching while keeping memory bounded.
        private let renderOverscanViewports: CGFloat = 1
        private let retentionViewports: CGFloat = 2

        func apply(_ model: DiffNativeTable, scroll: NSScrollView) {
            let ids = model.hunks.map(\.id)
            let revisions = model.hunks.map(\.contentRevision)
            let changed = ids != hunkIDs || revisions != self.revisions || scale != model.textScale
            if changed || self.model?.syntaxHighlighting != model.syntaxHighlighting
                || self.model?.fileExtension != model.fileExtension
                || self.model?.colorScheme != model.colorScheme
            {
                textStore.reset(
                    fontSize: 12 * model.textScale,
                    fileExtension: model.fileExtension,
                    syntaxHighlighting: model.syntaxHighlighting)
            }
            self.revisions = revisions
            self.model = model
            if changed {
                if ids != hunkIDs {
                    offsets.removeAll()
                } else {
                    for (index, panel) in panels { offsets[index] = panel.horizontalOffset }
                }
                hunkIDs = ids
                scale = model.textScale
                geometry = DiffHunkGeometry(
                    lineCounts: model.hunks.map { $0.lines.count }, scale: scale)
                widths = Array(repeating: 0, count: ids.count)
                for panel in panels.values { panel.removeFromSuperview() }
                panels.removeAll()
                recycledPanels.removeAll()
                measureWidths(model)
            }
            layout(scroll, refresh: true)
        }

        private func measureWidths(_ model: DiffNativeTable) {
            widthTask?.cancel()
            let hunks = model.hunks
            let fontSize = 12 * model.textScale
            let fontName = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).fontName
            widthTask = Task { [weak self] in
                let worker = Task.detached(priority: .userInitiated) {
                    var widths: [CGFloat] = []
                    for hunk in hunks {
                        var width: CGFloat = 0
                        for line in hunk.lines {
                            guard !Task.isCancelled else { return widths }
                            width = max(
                                width,
                                DiffLongLineLayout.measuredWidth(
                                    text: line.text, fontName: fontName, fontSize: fontSize))
                        }
                        widths.append(ceil(width) + 114)
                    }
                    return widths
                }
                let result = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self else { return }
                widths = result
                if let scroll = document.enclosingScrollView { layout(scroll) }
            }
        }

        func connectTextStore() {
            textStore.onReady = { [weak self] ids in
                guard let self else { return }
                for panel in self.panels.values { panel.canvas.invalidateLines(ids) }
            }
        }

        func observe(_ scroll: NSScrollView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                queue: .main
            ) { [weak self, weak scroll] _ in
                MainActor.assumeIsolated {
                    guard let self, let scroll else { return }
                    self.layout(scroll)
                }
            }
        }

        private func layout(_ scroll: NSScrollView, refresh: Bool = false) {
            guard let model, !updating else { return }
            updating = true
            defer { updating = false }
            let bounds = scroll.contentView.bounds
            let size = CGSize(
                width: max(1, bounds.width), height: max(bounds.height, geometry.height))
            if document.frame.size != size { document.setFrameSize(size) }
            let renderBounds = bounds.insetBy(
                dx: 0,
                dy: -bounds.height * renderOverscanViewports
            )
            let retentionBounds = bounds.insetBy(
                dx: 0,
                dy: -bounds.height * retentionViewports
            )
            let rendered = geometry.visibleHunks(in: renderBounds)
            let retained = geometry.visibleHunks(in: retentionBounds)
            for index in Array(panels.keys) where !retained.contains(index) {
                if let panel = panels.removeValue(forKey: index) {
                    offsets[index] = panel.horizontalOffset
                    panel.canvas.onLineTap = nil
                    panel.canvas.lineMenu = nil
                    panel.canvas.cancelPendingWork()
                    panel.removeFromSuperview()
                    recycledPanels.append(panel)
                }
            }
            for index in rendered {
                let panel: DiffNativeHunkView
                let isNew: Bool
                if let existing = panels[index] {
                    panel = existing
                    isNew = false
                } else {
                    panel = recycledPanels.popLast() ?? DiffNativeHunkView()
                    panels[index] = panel
                    document.addSubview(panel)
                    panel.horizontalScroll.verticalScrollView = scroll
                    isNew = true
                }
                let hunk = model.hunks[index]
                let frame = geometry.frame(at: index, width: size.width)
                if panel.frame != frame { panel.frame = frame }
                let localVisible = renderBounds.offsetBy(
                    dx: -panel.frame.minX, dy: -panel.frame.minY)
                panel.updateGeometry(
                    visible: localVisible, headerHeight: geometry.headerHeight,
                    lineHeight: geometry.lineHeight, lineCount: hunk.lines.count,
                    contentWidth: widths[index],
                    restoredOffset: isNew ? offsets[index, default: 0] : nil
                )
                if refresh || isNew {
                    configureHeader(panel.header, hunk: hunk)
                    panel.canvas.configure(
                        hunk: hunk, textStore: textStore,
                        selectedLineIDs: model.selectedLineIDs,
                        lineHeight: geometry.lineHeight)
                    // Read the coordinator's latest model when the event occurs.
                    // A hosted header and native rows share exactly the same actions.
                    panel.canvas.onLineTap = { [weak self] line, flags in
                        guard let model = self?.model, model.hunks.indices.contains(index) else {
                            return
                        }
                        model.onLineTap(model.hunks[index], line, flags)
                    }
                    panel.canvas.lineMenu = { [weak self] line in
                        guard let model = self?.model, model.hunks.indices.contains(index) else {
                            return nil
                        }
                        return model.lineMenu(model.hunks[index], line)
                    }
                }

            }
            // Match the spare pool to the current render window. Files with many
            // small hunks can then reuse a warm panel instead of rebuilding its
            // hosting tree at every boundary, without retaining the whole diff.
            let spareLimit = max(2, rendered.count)
            if recycledPanels.count > spareLimit {
                recycledPanels.removeFirst(recycledPanels.count - spareLimit)
            }
        }

        private func configureHeader(_ cell: DiffNativeCell, hunk: DiffHunk) {
            guard let model else { return }
            #if DEBUG
                DiffRenderStats.headerHostAssignments += 1
            #endif
            cell.host.rootView = AnyView(
                model.content(hunk)
                    .id(hunk.id)
                    .environment(\.appTextScale, model.textScale)
                    .environment(\.colorScheme, model.colorScheme))
        }

        func stop() {
            widthTask?.cancel()
            widthTask = nil
            for panel in panels.values { panel.canvas.cancelPendingWork() }
            textStore.cancel()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
}
