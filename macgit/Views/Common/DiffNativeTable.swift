// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// One native document owns both scroll axes; only visible rows have hosting views.
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
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let table = context.coordinator.table
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .none
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))
        column.minWidth = 1
        column.maxWidth = .greatestFiniteMagnitude
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        scroll.documentView = table
        scroll.contentView.postsBoundsChangedNotifications = true
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
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        struct Row { let hunk: Int; let line: Int? }
        let table = NSTableView()
        private var model: DiffNativeTable?
        private var rows: [Row] = []
        private var hunkIDs: [UUID] = []
        private var scale: CGFloat = 0
        private var measuredWidth: CGFloat = 0
        private var widthTask: Task<Void, Never>?
        private var observer: NSObjectProtocol?
        private var viewport = CGRect.zero

        func apply(_ model: DiffNativeTable, scroll: NSScrollView) {
            let ids = model.hunks.map(\.id)
            let changed = ids != hunkIDs || scale != model.textScale
            self.model = model
            if changed {
                hunkIDs = ids
                scale = model.textScale
                rows = model.hunks.enumerated().flatMap { index, hunk in
                    [Row(hunk: index, line: nil)] + hunk.lines.indices.map { Row(hunk: index, line: $0) }
                }
                measuredWidth = 0
                table.reloadData()
                measureWidth(model)
            } else {
                // Selection and action availability refresh visible cells only.
                refreshVisibleCells()
            }
            updateWidth(scroll)
        }

        private func measureWidth(_ model: DiffNativeTable) {
            widthTask?.cancel()
            let hunks = model.hunks
            let fontSize = 12 * model.textScale
            let fontName = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).fontName
            widthTask = Task { [weak self] in
                let worker = Task.detached(priority: .userInitiated) {
                    var width: CGFloat = 0
                    for hunk in hunks {
                        for line in hunk.lines {
                            guard !Task.isCancelled else { return width }
                            width = max(width, DiffLongLineLayout.measuredWidth(
                                text: line.text, fontName: fontName, fontSize: fontSize))
                        }
                    }
                    return ceil(width) + 114
                }
                let width = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, let self else { return }
                measuredWidth = width
                if let scroll = table.enclosingScrollView { updateWidth(scroll) }
            }
        }

        private func updateWidth(_ scroll: NSScrollView) {
            let width = max(1, scroll.contentView.bounds.width, measuredWidth)
            guard let column = table.tableColumns.first, column.width != width else { return }
            column.width = width
        }

        func observe(_ scroll: NSScrollView) {
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self, weak scroll] _ in
                MainActor.assumeIsolated {
                    guard let self, let scroll else { return }
                    self.updateWidth(scroll)
                    let bounds = scroll.contentView.bounds
                    let next = CGRect(x: floor(max(0, bounds.minX) / 256) * 256, y: 0,
                                      width: ceil(max(1, bounds.width) / 256) * 256, height: 0)
                    guard next != self.viewport else { return }
                    self.viewport = next
                    // Native scrolling moves ordinary lines without rebuilding them.
                    self.refreshVisibleCells(longLinesOnly: true)
                }
            }
        }

        private func refreshVisibleCells(longLinesOnly: Bool = false) {
            guard let model else { return }
            table.enumerateAvailableRowViews { _, index in
                guard rows.indices.contains(index),
                      let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? DiffNativeCell else { return }
                let row = rows[index]
                if longLinesOnly {
                    guard let line = row.line, DiffLongLineLayout.isLong(model.hunks[row.hunk].lines[line].text) else { return }
                }
                configure(cell, row: row)
            }
        }

        private func configure(_ cell: DiffNativeCell, row: Row) {
            guard let model else { return }
            let hunk = model.hunks[row.hunk]
            let identity = row.line.map { hunk.lines[$0].id } ?? hunk.id
            cell.host.rootView = AnyView(model.content(hunk, row.line, viewport)
                .id(identity)
                .environment(\.appTextScale, model.textScale)
                .environment(\.colorScheme, model.colorScheme))
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            (rows[row].line == nil ? 44 : 22) * scale
        }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier(rows[row].line == nil ? "header" : "line")
            let cell = table.makeView(withIdentifier: id, owner: self) as? DiffNativeCell ?? DiffNativeCell()
            cell.identifier = id
            configure(cell, row: rows[row])
            return cell
        }
        func stop() {
            widthTask?.cancel()
            widthTask = nil
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
}
