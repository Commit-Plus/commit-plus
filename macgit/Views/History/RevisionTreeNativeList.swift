// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// AppKit-backed tree of a repository at one revision. Rows are reused by the
/// table, so scrolling and expanding large folders stays smooth.
struct RevisionTreeNativeList: NSViewRepresentable {
    struct Row: Equatable, Identifiable {
        let entry: RevisionTreeEntry
        let depth: Int
        let isExpanded: Bool
        let isLoading: Bool
        /// Second line under the name, such as a folder load error.
        let note: String?
        var id: String { entry.path }
    }

    let rows: [Row]
    let selectedID: String?
    let reveal: (path: String, token: UUID)?
    let textScale: CGFloat
    let onSelect: (RevisionTreeEntry) -> Void
    let onToggle: (RevisionTreeEntry) -> Void
    let makeContextMenu: (RevisionTreeEntry) -> NSMenu?

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.apply(self) }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        private let table = RevisionTreeTableView()
        private var model: RevisionTreeNativeList?
        private var rows: [Row] = []
        private var hostedMenu: NSMenu?
        private var isApplying = false
        private var revealToken: UUID?
        private var appliedScale: CGFloat = 0
        private var hasShownSelection = false

        func makeScrollView() -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            let column = NSTableColumn(identifier: .init("revision-tree"))
            column.resizingMask = .autoresizingMask
            table.addTableColumn(column)
            table.headerView = nil
            table.backgroundColor = .clear
            table.style = .plain
            table.intercellSpacing = .zero
            table.selectionHighlightStyle = .regular
            table.allowsEmptySelection = true
            table.allowsMultipleSelection = false
            table.dataSource = self
            table.delegate = self
            table.target = self
            table.action = #selector(clicked)
            table.contextMenuProvider = { [weak self] in self?.contextMenu($0) }
            scroll.documentView = table
            return scroll
        }

        func stop() {
            table.contextMenuProvider = nil
            hostedMenu = nil
        }

        func apply(_ model: RevisionTreeNativeList) {
            let old = rows
            self.model = model
            rows = model.rows
            isApplying = true
            defer { isApplying = false }
            let scaleChanged = appliedScale != model.textScale
            appliedScale = model.textScale
            if scaleChanged || old.map(\.id) != rows.map(\.id) {
                let anchor = viewportAnchor(old)
                table.reloadData()
                restore(anchor)
            } else {
                var changed = IndexSet()
                for index in rows.indices where rows[index] != old[index] { changed.insert(index) }
                if !changed.isEmpty {
                    table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
                    table.noteHeightOfRows(withIndexesChanged: changed)
                }
            }
            let selection = model.selectedID.flatMap { id in rows.firstIndex { $0.id == id } }
                .map { IndexSet(integer: $0) } ?? IndexSet()
            if table.selectedRowIndexes != selection {
                table.selectRowIndexes(selection, byExtendingSelection: false)
            }
            var scrolledToSelection = false
            if !hasShownSelection, !rows.isEmpty {
                // Only the first populated update: a recreated list (for example after a tab switch)
                // starts at the kept selection. Later selections come from the user and stay put.
                hasShownSelection = true
                if let row = selection.first {
                    scrolledToSelection = true
                    revealToken = model.reveal?.token
                    let rect = table.rect(ofRow: row)
                    table.scroll(NSPoint(x: 0, y: max(0, rect.midY - table.visibleRect.height / 2)))
                }
            }
            if !scrolledToSelection, let reveal = model.reveal, reveal.token != revealToken,
               let row = rows.firstIndex(where: { $0.id == reveal.path }) {
                revealToken = reveal.token
                let rect = table.rect(ofRow: row)
                let visible = table.visibleRect
                table.scroll(NSPoint(x: 0, y: max(0, rect.midY - visible.height / 2)))
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row) else { return 26 }
            return (rows[row].note == nil ? 26 : 40) * (model?.textScale ?? 1)
        }

        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let model else { return nil }
            let id = NSUserInterfaceItemIdentifier("RevisionTreeCell")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? RevisionTreeCell ?? RevisionTreeCell()
            cell.identifier = id
            cell.configure(rows[row], textScale: model.textScale)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplying, rows.indices.contains(table.selectedRow) else { return }
            model?.onSelect(rows[table.selectedRow].entry)
        }

        @objc private func clicked() {
            let index = table.clickedRow
            guard rows.indices.contains(index), rows[index].entry.isDirectory else { return }
            model?.onToggle(rows[index].entry)
        }

        private func contextMenu(_ index: Int) -> NSMenu? {
            guard rows.indices.contains(index), let menu = model?.makeContextMenu(rows[index].entry) else { return nil }
            hostedMenu = menu
            menu.delegate = self
            return menu
        }

        func menuDidClose(_ menu: NSMenu) {
            if hostedMenu === menu { hostedMenu = nil }
        }

        private func viewportAnchor(_ source: [Row]) -> (String, CGFloat)? {
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound, source.indices.contains(visible.location) else { return nil }
            return (source[visible.location].id, table.visibleRect.minY - table.rect(ofRow: visible.location).minY)
        }

        private func restore(_ anchor: (String, CGFloat)?) {
            guard let anchor, let row = rows.firstIndex(where: { $0.id == anchor.0 }),
                  let scroll = table.enclosingScrollView else { return }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, table.rect(ofRow: row).minY + anchor.1)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

private final class RevisionTreeTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        return index < 0 ? nil : contextMenuProvider?(index)
    }
}

private final class RevisionTreeCell: NSTableCellView {
    private let chevron = NSImageView()
    private let content = FileChangeRowContentView()
    private let spinner = NSProgressIndicator()
    private var depth = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        [chevron, content, spinner].forEach(addSubview)
        chevron.imageScaling = .scaleProportionallyDown
        chevron.contentTintColor = .secondaryLabelColor
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ row: RevisionTreeNativeList.Row, textScale: CGFloat) {
        let entry = row.entry
        depth = min(row.depth, 20)
        chevron.isHidden = !entry.isDirectory
        chevron.image = NSImage(systemSymbolName: row.isExpanded ? "chevron.down" : "chevron.right",
                                accessibilityDescription: row.isExpanded ? "Expanded" : "Collapsed")
        content.configure(.init(path: entry.path, name: entry.name, isDirectory: entry.isDirectory,
            isExpanded: row.isExpanded,
            subtitle: row.note, textScale: textScale))
        if row.isLoading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        toolTip = entry.isSubmodule ? "\(entry.path) (submodule)" : entry.isSymlink ? "\(entry.path) (symbolic link)" : entry.path
        setAccessibilityLabel(entry.name)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let x = CGFloat(depth) * 14 + 6
        chevron.frame = NSRect(x: x, y: bounds.midY - 6, width: 10, height: 12)
        spinner.frame = NSRect(x: bounds.maxX - 22, y: bounds.midY - 8, width: 16, height: 16)
        let contentX = x + 15
        content.frame = NSRect(x: contentX, y: 0, width: max(0, bounds.maxX - 26 - contentX), height: bounds.height)
    }
}
