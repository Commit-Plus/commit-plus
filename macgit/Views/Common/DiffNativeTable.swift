// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// The outer document owns only Y. Each visible hunk owns a real horizontal
/// NSScrollView; neither scrolling axis round-trips through SwiftUI state.
struct DiffNativeTable<Content: View>: NSViewRepresentable {
    let hunks: [DiffHunk]
    let textScale: CGFloat
    let syntaxHighlighting: Bool
    let selectedLineIDs: Set<UUID>
    @ViewBuilder let content: (DiffHunk, Int?, CGRect) -> Content
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
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
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
        private var scale: CGFloat = 0
        private var widths: [CGFloat] = []
        private var offsets: [Int: CGFloat] = [:]
        private var panels: [Int: DiffNativeHunkView] = [:]
        private var recycledPanels: [DiffNativeHunkView] = []
        private var widthTask: Task<Void, Never>?
        private var observer: NSObjectProtocol?
        private var updating = false

        func apply(_ model: DiffNativeTable, scroll: NSScrollView) {
            let ids = model.hunks.map(\.id)
            let changed = ids != hunkIDs || scale != model.textScale
            self.model = model
            if changed {
                if ids != hunkIDs {
                    offsets.removeAll()
                } else {
                    for (index, panel) in panels { offsets[index] = panel.horizontalOffset }
                }
                hunkIDs = ids
                scale = model.textScale
                geometry = DiffHunkGeometry(lineCounts: model.hunks.map { $0.lines.count }, scale: scale)
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
                            width = max(width, DiffLongLineLayout.measuredWidth(
                                text: line.text, fontName: fontName, fontSize: fontSize))
                        }
                        widths.append(ceil(width) + 114)
                    }
                    return widths
                }
                let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, let self else { return }
                widths = result
                if let scroll = document.enclosingScrollView { layout(scroll) }
            }
        }

        func observe(_ scroll: NSScrollView) {
            scroll.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
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
            let size = CGSize(width: max(1, bounds.width), height: max(bounds.height, geometry.height))
            if document.frame.size != size { document.setFrameSize(size) }
            let visible = geometry.visibleHunks(in: bounds)
            for index in Array(panels.keys) where !visible.contains(index) {
                if let panel = panels.removeValue(forKey: index) {
                    offsets[index] = panel.horizontalOffset
                    panel.onHorizontalScroll = nil
                    panel.removeFromSuperview()
                    recycledPanels.append(panel)
                }
            }
            for index in visible {
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
                let localVisible = bounds.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
                panel.updateGeometry(
                    visible: localVisible, headerHeight: geometry.headerHeight,
                    lineHeight: geometry.lineHeight, lineCount: hunk.lines.count,
                    contentWidth: widths[index], restoredOffset: isNew ? offsets[index, default: 0] : nil
                )
                if refresh || isNew {
                    configure(panel.header, hunk: hunk, line: nil, viewport: panel.horizontalViewport)
                }
                panel.updateLines(lineCount: hunk.lines.count, lineHeight: geometry.lineHeight,
                                  refresh: refresh || isNew) { cell, line, created in
                    if refresh || isNew || created {
                        configure(cell, hunk: hunk, line: line, viewport: panel.horizontalViewport)
                    }
                }
                if isNew {
                    // Rebind only after old row indices and content have been
                    // replaced, so width notifications cannot access the old hunk.
                    panel.onHorizontalScroll = { [weak self, weak panel] viewport in
                        guard let self, let panel else { return }
                        self.offsets[index] = panel.horizontalOffset
                        self.refreshLongLines(panel, hunk: index, viewport: viewport)
                    }
                }
            }
            // A bounded spare pool absorbs changes in visible hunk count without
            // retaining every hosting tree visited during a long scroll.
            if recycledPanels.count > 2 { recycledPanels.removeFirst(recycledPanels.count - 2) }
        }

        private func refreshLongLines(_ panel: DiffNativeHunkView, hunk index: Int, viewport: CGRect) {
            guard let model, model.hunks.indices.contains(index) else { return }
            let hunk = model.hunks[index]
            for (line, cell) in panel.cells where DiffLongLineLayout.isLong(hunk.lines[line].text) {
                configure(cell, hunk: hunk, line: line, viewport: viewport)
            }
        }

        private func configure(_ cell: DiffNativeCell, hunk: DiffHunk, line: Int?, viewport: CGRect) {
            guard let model else { return }
            let identity = line.map { hunk.lines[$0].id } ?? hunk.id
            cell.host.rootView = AnyView(model.content(hunk, line, viewport)
                .id(identity)
                .environment(\.appTextScale, model.textScale)
                .environment(\.colorScheme, model.colorScheme))
        }

        func stop() {
            widthTask?.cancel()
            widthTask = nil
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
}
