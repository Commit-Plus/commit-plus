// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct CommitFileTreeNativeList: NSViewRepresentable {
    struct Row: Equatable, Identifiable {
        enum Content: Equatable {
            case folder(path: String, name: String, isExpanded: Bool)
            case file(change: CommitFileChange, name: String, count: FileLineChangeCount?)
        }
        let id: String
        let depth: Int
        let content: Content
    }
    let rows: [Row]
    let selectedIDs: Set<UUID>
    let textScale: CGFloat
    let onToggleFolder: (String) -> Void
    let onSelect: (CommitFileChange) -> Void
    let onOpenFile: ((CommitFileChange) -> Void)?
    let makeContextMenu: ((CommitFileChange) -> NSMenu?)?

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.apply(self) }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        private let table = CommitTreeTableView(); private var model: CommitFileTreeNativeList?; private var rows: [Row] = []; private var hostedMenu: NSMenu?
        func makeScrollView() -> NSScrollView {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
            let column = NSTableColumn(identifier: .init("commit-tree")); column.resizingMask = .autoresizingMask
            table.addTableColumn(column); table.headerView = nil; table.backgroundColor = .clear; table.rowHeight = 36; table.intercellSpacing = .zero; table.selectionHighlightStyle = .none
            table.dataSource = self; table.delegate = self; table.target = self; table.action = #selector(clicked); table.doubleAction = #selector(doubleClicked)
            table.contextMenuProvider = { [weak self] in self?.contextMenu($0) }; scroll.documentView = table; return scroll
        }
        func apply(_ model: CommitFileTreeNativeList) {
            let old = rows
            let oldSelectedIDs = self.model?.selectedIDs ?? []
            let structural = old.map(\.id) != model.rows.map(\.id)
            self.model = model; rows = model.rows
            if structural { let anchor = viewportAnchor(old); table.reloadData(); restore(anchor) }
            else {
                var changed = IndexSet()
                for i in rows.indices where rows[i] != old[i]
                    || selection(old[i], selectedIDs: oldSelectedIDs) != selection(rows[i], selectedIDs: model.selectedIDs) {
                    changed.insert(i)
                }
                if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0)) }
            }
        }
        private func selection(_ row: Row, selectedIDs: Set<UUID>) -> Bool { if case .file(let change, _, _) = row.content { return selectedIDs.contains(change.id) }; return false }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let model else { return nil }; let item = rows[row]; let id = NSUserInterfaceItemIdentifier("CommitTreeCell")
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? CommitTreeCell ?? CommitTreeCell(); cell.identifier = id
            switch item.content {
            case .folder(let path, let name, let expanded): cell.configureFolder(name: name, depth: item.depth, expanded: expanded, textScale: model.textScale); cell.toolTip = path
            case .file(let change, let name, let count): cell.configureFile(change: change, name: name, count: count, depth: item.depth, selected: model.selectedIDs.contains(change.id), textScale: model.textScale, showsOpen: model.onOpenFile != nil, onOpen: { [weak self] in self?.model?.onOpenFile?(change) })
            }
            return cell
        }
        @objc private func clicked() { let i = table.clickedRow; guard rows.indices.contains(i), let model else { return }; switch rows[i].content { case .folder(let path, _, _): model.onToggleFolder(path); case .file(let change, _, _): model.onSelect(change) } }
        @objc private func doubleClicked() { let i = table.clickedRow; guard rows.indices.contains(i), case .file(let change, _, _) = rows[i].content else { return }; model?.onOpenFile?(change) }
        private func contextMenu(_ i: Int) -> NSMenu? { guard rows.indices.contains(i), case .file(let change, _, _) = rows[i].content, let menu = model?.makeContextMenu?(change) else { return nil }; hostedMenu = menu; menu.delegate = self; return menu }
        func menuDidClose(_ menu: NSMenu) { if hostedMenu === menu { hostedMenu = nil } }
        private func viewportAnchor(_ source: [Row]) -> (String, CGFloat)? { let visible = table.rows(in: table.visibleRect); guard visible.location != NSNotFound, source.indices.contains(visible.location) else { return nil }; return (source[visible.location].id, table.visibleRect.minY - table.rect(ofRow: visible.location).minY) }
        private func restore(_ anchor: (String, CGFloat)?) { guard let anchor, let row = rows.firstIndex(where: { $0.id == anchor.0 }), let scroll = table.enclosingScrollView else { return }; scroll.contentView.scroll(to: .init(x: 0, y: max(0, table.rect(ofRow: row).minY + anchor.1))); scroll.reflectScrolledClipView(scroll.contentView) }
    }
}

private final class CommitTreeTableView: NSTableView { var contextMenuProvider: ((Int) -> NSMenu?)?; override func menu(for event: NSEvent) -> NSMenu? { let i = row(at: convert(event.locationInWindow, from: nil)); return i < 0 ? nil : contextMenuProvider?(i) } }

private final class CommitTreeCell: NSTableCellView {
    private let chevron = NSImageView(), icon = NSImageView(), name = NSTextField(labelWithString: ""), added = NSTextField(labelWithString: ""), removed = NSTextField(labelWithString: ""), status = NSTextField(labelWithString: ""), open = NSButton()
    private var depth = 0; private var onOpen: (() -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); [chevron, icon, name, added, removed, status, open].forEach(addSubview); chevron.imageScaling = .scaleProportionallyDown; icon.imageScaling = .scaleProportionallyDown; name.lineBreakMode = .byTruncatingMiddle; added.textColor = .systemGreen; removed.textColor = .systemRed; status.alignment = .center; open.isBordered = false; open.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: "Open with application"); open.target = self; open.action = #selector(openFile) }
    required init?(coder: NSCoder) { fatalError() }
    func configureFolder(name title: String, depth: Int, expanded: Bool, textScale: CGFloat) { self.depth = depth; chevron.isHidden = false; chevron.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil); icon.image = NSImage(systemSymbolName: expanded ? "folder.fill.badge.minus" : "folder.fill", accessibilityDescription: "Folder"); icon.contentTintColor = .systemBlue; name.stringValue = title; name.font = .systemFont(ofSize: 12 * textScale, weight: .medium); added.isHidden = true; removed.isHidden = true; status.isHidden = true; open.isHidden = true; wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor; needsLayout = true }
    func configureFile(change: CommitFileChange, name title: String, count: FileLineChangeCount?, depth: Int, selected: Bool, textScale: CGFloat, showsOpen: Bool, onOpen: @escaping () -> Void) { self.depth = depth; self.onOpen = onOpen; chevron.isHidden = true; icon.image = NSImage(systemSymbolName: Self.symbol(change.status), accessibilityDescription: nil); icon.contentTintColor = Self.color(change.status); name.stringValue = title; name.font = .systemFont(ofSize: 12 * textScale, weight: .medium); if let count { added.stringValue = "+\(count.added)"; removed.stringValue = "−\(count.removed)"; added.isHidden = false; removed.isHidden = false } else { added.isHidden = true; removed.isHidden = true }; let font = NSFont.monospacedSystemFont(ofSize: 10 * textScale, weight: .medium); added.font = font; removed.font = font; status.stringValue = change.status.rawValue; status.font = font; status.textColor = Self.color(change.status); status.isHidden = showsOpen; open.isHidden = !showsOpen; wantsLayer = true; layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor; needsLayout = true }
    override func layout() { super.layout(); let y = bounds.midY, x = CGFloat(depth) * 14 + 8; chevron.frame = .init(x: x, y: y - 6, width: 10, height: 12); icon.frame = .init(x: x + (chevron.isHidden ? 0 : 16), y: y - 9, width: 18, height: 18); var right = bounds.maxX - 8; if !open.isHidden { open.frame = .init(x: right - 22, y: y - 11, width: 22, height: 22); right -= 26 } else if !status.isHidden { let w = min(68, status.intrinsicContentSize.width + 8); status.frame = .init(x: right - w, y: y - 8, width: w, height: 16); right -= w + 6 }; if !removed.isHidden { let w = ceil(removed.intrinsicContentSize.width) + 4; removed.frame = .init(x: right - w, y: y - 8, width: w, height: 16); right -= w + 4 }; if !added.isHidden { let w = ceil(added.intrinsicContentSize.width) + 4; added.frame = .init(x: right - w, y: y - 8, width: w, height: 16); right -= w + 6 }; name.frame = .init(x: icon.frame.maxX + 7, y: y - 9, width: max(20, right - icon.frame.maxX - 9), height: 18) }
    @objc private func openFile() { onOpen?() }
    private static func symbol(_ s: CommitFileStatus) -> String { switch s { case .added: "plus.circle.fill"; case .modified: "pencil.circle.fill"; case .deleted: "minus.circle.fill"; case .renamed: "arrow.right.circle.fill"; case .copied: "doc.on.doc.fill" } }
    private static func color(_ s: CommitFileStatus) -> NSColor { switch s { case .added: .systemGreen; case .modified: .systemOrange; case .deleted: .systemRed; case .renamed: .systemBlue; case .copied: .systemPurple } }
}
