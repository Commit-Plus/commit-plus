// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct YourRepositoriesNativeList: NSViewRepresentable {
    struct Row: Identifiable, Equatable {
        enum Content: Equatable {
            case folder(URL, String, Bool, Bool)
            case repository(YourRepository, String, Bool)
        }

        let id: String
        let depth: Int
        let content: Content
    }

    let rows: [Row]
    let textScale: CGFloat
    let onOpen: (URL) -> Void
    let onToggleFolder: (URL) -> Void
    let onToggleStar: (URL) -> Void
    let onRemoveRoot: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.apply(self) }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private let table = TableView()
        private var model: YourRepositoriesNativeList?
        private var rows: [Row] = []
        private var scale: CGFloat = 0

        func makeScrollView() -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            let column = NSTableColumn(identifier: .init("your-repositories"))
            column.resizingMask = .autoresizingMask
            table.addTableColumn(column)
            table.headerView = nil
            table.style = .plain
            scroll.contentInsets = .init()
            scroll.automaticallyAdjustsContentInsets = false
            table.backgroundColor = .clear
            table.intercellSpacing = .zero
            table.selectionHighlightStyle = .none
            table.dataSource = self
            table.delegate = self
            table.target = self
            table.action = #selector(clickedRow)
            table.doubleAction = #selector(doubleClickedRow)
            table.contextMenuProvider = { [weak self] row in self?.contextMenu(for: row) }
            scroll.documentView = table
            return scroll
        }

        func apply(_ model: YourRepositoriesNativeList) {
            let oldRows = rows
            let structureChanged = oldRows.map(\.id) != model.rows.map(\.id)
            let scaleChanged = scale != model.textScale
            self.model = model
            rows = model.rows
            scale = model.textScale
            table.rowHeight = 48 * model.textScale
            if structureChanged || scaleChanged {
                let anchor = viewportAnchor(in: oldRows)
                table.reloadData()
                restoreViewport(anchor)
                return
            }
            var changed = IndexSet()
            for index in rows.indices where rows[index] != oldRows[index] { changed.insert(index) }
            if !changed.isEmpty {
                table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row) else { return 48 * scale }
            if case .folder = rows[row].content { return 36 * scale }
            return 52 * scale
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let model else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("YourRepositoryCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? Cell ?? Cell()
            cell.identifier = identifier
            let item = rows[row]
            switch item.content {
            case .folder(let url, let name, let expanded, let isRoot):
                cell.configureFolder(name: name, depth: item.depth, expanded: expanded, textScale: model.textScale)
                cell.toolTip = url.path
                cell.setAccessibilityLabel(name)
                cell.starAction = nil
                cell.starButton.isHidden = true
                cell.removeAction = isRoot ? { [weak self] in self?.model?.onRemoveRoot(url) } : nil
            case .repository(let repository, let iconName, let starred):
                cell.configureRepository(repository, iconName: iconName, starred: starred, depth: item.depth, textScale: model.textScale)
                cell.starAction = { [weak self] in self?.model?.onToggleStar(repository.url) }
                cell.removeAction = nil
            }
            return cell
        }

        @objc private func clickedRow() {
            let index = table.clickedRow
            guard rows.indices.contains(index), let model else { return }
            switch rows[index].content {
            case .folder(let url, _, _, _): model.onToggleFolder(url)
            case .repository(let repository, _, _): model.onOpen(repository.url)
            }
        }

        @objc private func doubleClickedRow() {
            let index = table.clickedRow
            guard rows.indices.contains(index),
                  case .repository(let repository, _, _) = rows[index].content else { return }
            model?.onOpen(repository.url)
        }

        private func contextMenu(for index: Int) -> NSMenu? {
            guard rows.indices.contains(index),
                  case .folder(let url, _, _, let isRoot) = rows[index].content,
                  isRoot else { return nil }
            let menu = NSMenu()
            let item = NSMenuItem(title: "Remove Folder", action: #selector(removeRoot(_:)), keyEquivalent: "")
            item.representedObject = url
            item.target = self
            menu.addItem(item)
            return menu
        }

        @objc private func removeRoot(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            model?.onRemoveRoot(url)
        }

        private func viewportAnchor(in source: [Row]) -> (String, CGFloat)? {
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound, source.indices.contains(visible.location) else { return nil }
            return (source[visible.location].id, table.visibleRect.minY - table.rect(ofRow: visible.location).minY)
        }

        private func restoreViewport(_ anchor: (String, CGFloat)?) {
            guard let anchor,
                  let row = rows.firstIndex(where: { $0.id == anchor.0 }),
                  let scroll = table.enclosingScrollView else { return }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, table.rect(ofRow: row).minY + anchor.1)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

private extension YourRepositoriesNativeList.Coordinator {
    final class TableView: NSTableView {
        var contextMenuProvider: ((Int) -> NSMenu?)?

        override func menu(for event: NSEvent) -> NSMenu? {
            let index = row(at: convert(event.locationInWindow, from: nil))
            return index < 0 ? nil : contextMenuProvider?(index)
        }
    }

    final class Cell: NSTableCellView {
        let starButton = NSButton()
        var starAction: (() -> Void)?
        var removeAction: (() -> Void)?
        private let chevron = NSImageView()
        private let icon = NSImageView()
        private let name = NSTextField(labelWithString: "")
        private let path = NSTextField(labelWithString: "")
        private var depth = 0

        override init(frame: NSRect) {
            super.init(frame: frame)
            [chevron, icon, name, path, starButton].forEach(addSubview)
            chevron.imageScaling = .scaleProportionallyDown
            icon.imageScaling = .scaleProportionallyDown
            name.lineBreakMode = .byTruncatingTail
            path.lineBreakMode = .byTruncatingMiddle
            path.textColor = .secondaryLabelColor
            starButton.isBordered = false
            starButton.target = self
            starButton.action = #selector(toggleStar)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configureFolder(name title: String, depth: Int, expanded: Bool, textScale: CGFloat) {
            self.depth = depth
            chevron.isHidden = false
            chevron.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
            icon.image = NSImage(systemSymbolName: expanded ? "folder.fill.badge.minus" : "folder.fill", accessibilityDescription: "Folder")
            icon.contentTintColor = .systemBlue
            name.stringValue = title
            name.font = .systemFont(ofSize: 13 * textScale, weight: .medium)
            path.isHidden = true
            starButton.isHidden = true
            needsLayout = true
        }

        func configureRepository(_ repository: YourRepository, iconName: String, starred: Bool, depth: Int, textScale: CGFloat) {
            self.depth = depth
            chevron.isHidden = true
            let providerImage = iconName == "code-branch" ? nil : NSImage(named: iconName)
            icon.image = providerImage ?? NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "Repository")
            icon.contentTintColor = providerImage == nil ? .secondaryLabelColor : nil
            name.stringValue = repository.name
            name.font = .systemFont(ofSize: 13 * textScale, weight: .medium)
            path.stringValue = repository.url.path
            path.font = .systemFont(ofSize: 11 * textScale)
            path.isHidden = false
            starButton.image = NSImage(systemSymbolName: starred ? "star.fill" : "star", accessibilityDescription: starred ? "Remove bookmark" : "Bookmark repository")
            starButton.contentTintColor = starred ? .systemYellow : .secondaryLabelColor
            starButton.isHidden = false
            starButton.toolTip = starred ? "Remove bookmark" : "Bookmark repository"
            needsLayout = true
        }

        override func layout() {
            super.layout()
            let indentation = CGFloat(depth) * 16
            let centerY = bounds.midY
            chevron.frame = .init(x: indentation, y: centerY - 6, width: 10, height: 12)
            icon.frame = .init(x: indentation + (chevron.isHidden ? 0 : 16), y: centerY - 9, width: 18, height: 18)
            let right = starButton.isHidden ? bounds.maxX - 8 : bounds.maxX - 40
            starButton.frame = .init(x: bounds.maxX - 34, y: centerY - 13, width: 28, height: 26)
            let textX = icon.frame.maxX + 8
            if path.isHidden {
                name.frame = .init(x: textX, y: centerY - 9, width: max(20, right - textX), height: 18)
            } else {
                name.frame = .init(x: textX, y: centerY + 2, width: max(20, right - textX), height: 18)
                path.frame = .init(x: textX, y: centerY - 17, width: max(20, right - textX), height: 16)
            }
        }

        @objc private func toggleStar() { starAction?() }
    }
}
