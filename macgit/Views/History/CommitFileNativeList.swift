// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct CommitFileNativeList: NSViewRepresentable {
    struct Row: Equatable {
        let change: CommitFileChange
        let count: FileLineChangeCount?
    }

    let rows: [Row]
    let selectedIDs: Set<UUID>
    let primarySelectedID: UUID?
    let allowsMultipleSelection: Bool
    let textScale: CGFloat
    let onSelectionChange: ([CommitFileChange], CommitFileChange?) -> Void
    let onOpenFile: ((CommitFileChange) -> Void)?
    let makeContextMenu: ((CommitFileChange) -> NSMenu?)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.apply(self)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        private let tableView = CommitFileTableView()
        private var model: CommitFileNativeList?
        private var rows: [Row] = []
        private var appliedScale: CGFloat = 0
        private var hostedMenu: NSMenu?
        private var isApplyingSelection = false

        func makeScrollView() -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false

            let column = NSTableColumn(identifier: .init("commit-file"))
            column.resizingMask = .autoresizingMask
            tableView.addTableColumn(column)
            tableView.headerView = nil
            tableView.backgroundColor = .clear
            tableView.intercellSpacing = .zero
            tableView.style = .plain
            tableView.selectionHighlightStyle = .regular
            tableView.allowsEmptySelection = true
            tableView.dataSource = self
            tableView.delegate = self
            tableView.contextMenuProvider = { [weak self] row in self?.contextMenu(for: row) }
            scrollView.documentView = tableView
            return scrollView
        }

        func stop() {
            tableView.contextMenuProvider = nil
            hostedMenu = nil
        }

        func apply(_ model: CommitFileNativeList) {
            let oldRows = rows
            let oldPrimaryID = self.model?.primarySelectedID
            self.model = model
            tableView.allowsMultipleSelection = model.allowsMultipleSelection

            let scaleChanged = appliedScale != model.textScale
            appliedScale = model.textScale
            let structureChanged = oldRows.map(\.change.id) != model.rows.map(\.change.id)
            rows = model.rows

            if structureChanged || scaleChanged {
                let anchor = viewportAnchor(in: oldRows)
                tableView.reloadData()
                restoreViewport(anchor)
            } else {
                var changed = IndexSet()
                for index in rows.indices where rows[index] != oldRows[index] { changed.insert(index) }
                if !changed.isEmpty {
                    tableView.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
                }
            }

            applySelection(model.selectedIDs)
            if oldPrimaryID != model.primarySelectedID,
               let id = model.primarySelectedID,
               let row = rows.firstIndex(where: { $0.change.id == id }) {
                tableView.scrollRowToVisible(row)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row), let model else { return 48 }
            return (rows[row].change.oldPath == nil ? 48 : 62) * model.textScale
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let model else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("CommitFileCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? CommitFileNativeCell
                ?? CommitFileNativeCell()
            cell.identifier = identifier
            let item = rows[row]
            cell.configure(
                row: item,
                textScale: model.textScale,
                showsOpenButton: model.onOpenFile != nil,
                onOpen: { [weak self] in self?.model?.onOpenFile?(item.change) }
            )
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let model else { return }
            let selected = tableView.selectedRowIndexes.compactMap { index in
                rows.indices.contains(index) ? rows[index].change : nil
            }
            let eventType = NSApp.currentEvent?.type
            let isMouseSelection = eventType == .leftMouseDown || eventType == .leftMouseUp
            let primaryRow = isMouseSelection && tableView.clickedRow >= 0
                ? tableView.clickedRow
                : tableView.selectedRow
            let primary = rows.indices.contains(primaryRow) ? rows[primaryRow].change : selected.first
            model.onSelectionChange(selected, primary)
        }

        private func applySelection(_ selectedIDs: Set<UUID>) {
            let indexes = IndexSet(rows.indices.filter { selectedIDs.contains(rows[$0].change.id) })
            guard tableView.selectedRowIndexes != indexes else { return }
            isApplyingSelection = true
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            isApplyingSelection = false
        }

        private func contextMenu(for row: Int) -> NSMenu? {
            guard rows.indices.contains(row), let menu = model?.makeContextMenu?(rows[row].change) else { return nil }
            hostedMenu = menu
            menu.delegate = self
            return menu
        }

        func menuDidClose(_ menu: NSMenu) {
            if hostedMenu === menu { hostedMenu = nil }
        }

        private func viewportAnchor(in source: [Row]) -> (UUID, CGFloat)? {
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.location != NSNotFound, source.indices.contains(visible.location) else { return nil }
            let row = visible.location
            return (source[row].change.id, tableView.visibleRect.minY - tableView.rect(ofRow: row).minY)
        }

        private func restoreViewport(_ anchor: (UUID, CGFloat)?) {
            guard let anchor, let row = rows.firstIndex(where: { $0.change.id == anchor.0 }),
                  let scrollView = tableView.enclosingScrollView else { return }
            let y = tableView.rect(ofRow: row).minY + anchor.1
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

private final class CommitFileTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        return contextMenuProvider?(row)
    }
}

private final class CommitFileNativeCell: NSTableCellView {
    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let oldPathLabel = NSTextField(labelWithString: "")
    private let addedLabel = NSTextField(labelWithString: "")
    private let removedLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let openButton = CommitFilePointingButton()
    private var addedWidth: CGFloat = 0
    private var removedWidth: CGFloat = 0
    private var onOpen: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [icon, nameLabel, pathLabel, oldPathLabel, addedLabel, removedLabel, statusLabel, openButton] {
            addSubview(view)
        }
        icon.imageScaling = .scaleProportionallyDown
        nameLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = .tertiaryLabelColor
        oldPathLabel.lineBreakMode = .byTruncatingMiddle
        oldPathLabel.textColor = .secondaryLabelColor
        addedLabel.textColor = .systemGreen
        removedLabel.textColor = .systemRed
        statusLabel.alignment = .center
        statusLabel.wantsLayer = true
        statusLabel.layer?.cornerRadius = 4
        openButton.isBordered = false
        openButton.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: "Open with application")
        openButton.target = self
        openButton.action = #selector(openFile)
        openButton.toolTip = "Open the working-copy file with your preferred application, or choose an application"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(row: CommitFileNativeList.Row, textScale: CGFloat, showsOpenButton: Bool,
                   onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        let change = row.change
        let name = URL(fileURLWithPath: change.path).lastPathComponent
        let directory = URL(fileURLWithPath: change.path).deletingLastPathComponent().path
        nameLabel.stringValue = name
        nameLabel.font = .systemFont(ofSize: 12 * textScale, weight: .medium)
        pathLabel.stringValue = directory
        pathLabel.font = .systemFont(ofSize: 10 * textScale)
        oldPathLabel.stringValue = change.oldPath.map { "From: \($0)" } ?? ""
        oldPathLabel.font = .systemFont(ofSize: 9 * textScale)
        oldPathLabel.isHidden = change.oldPath == nil

        icon.image = NSImage(systemSymbolName: Self.symbol(for: change.status), accessibilityDescription: change.status.displayText)
        icon.contentTintColor = Self.color(for: change.status)

        let countFont = NSFont.monospacedSystemFont(ofSize: 10 * textScale, weight: .medium)
        if let count = row.count {
            addedLabel.font = countFont
            removedLabel.font = countFont
            addedLabel.stringValue = "+\(count.added)"
            removedLabel.stringValue = "-\(count.removed)"
            addedLabel.setAccessibilityLabel("\(count.added) lines added")
            removedLabel.setAccessibilityLabel("\(count.removed) lines removed")
            addedWidth = ceil(addedLabel.intrinsicContentSize.width) + 3
            removedWidth = ceil(removedLabel.intrinsicContentSize.width) + 3
            addedLabel.isHidden = false
            removedLabel.isHidden = false
        } else {
            addedWidth = 0
            removedWidth = 0
            addedLabel.isHidden = true
            removedLabel.isHidden = true
        }

        openButton.isHidden = !showsOpenButton
        openButton.setAccessibilityLabel("Open \(name) with an application")
        statusLabel.isHidden = showsOpenButton
        statusLabel.stringValue = change.status.displayText
        statusLabel.font = .systemFont(ofSize: 10 * textScale, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.layer?.backgroundColor = Self.color(for: change.status).withAlphaComponent(0.12).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        icon.frame = NSRect(x: 6, y: midY - 9, width: 18, height: 18)
        let trailingWidth: CGFloat
        if !openButton.isHidden {
            openButton.frame = NSRect(x: bounds.maxX - 28, y: midY - 11, width: 24, height: 22)
            trailingWidth = 30
        } else {
            let width = min(70, statusLabel.intrinsicContentSize.width + 12)
            statusLabel.frame = NSRect(x: bounds.maxX - width - 4, y: midY - 10, width: width, height: 20)
            trailingWidth = width + 6
        }
        let textX: CGFloat = 30
        let textRight = bounds.maxX - trailingWidth
        let countWidth = addedWidth + removedWidth + (addedWidth > 0 ? 4 : 0)
        nameLabel.frame = NSRect(x: textX, y: midY + 2, width: max(20, textRight - textX), height: 18)
        pathLabel.frame = NSRect(x: textX, y: midY - 16,
                                 width: max(20, textRight - textX - countWidth - 6), height: 16)
        addedLabel.frame = NSRect(x: pathLabel.frame.maxX + 6, y: midY - 16, width: addedWidth, height: 16)
        removedLabel.frame = NSRect(x: addedLabel.frame.maxX + 4, y: midY - 16, width: removedWidth, height: 16)
        oldPathLabel.frame = NSRect(x: textX, y: midY - 31, width: max(20, textRight - textX), height: 14)
    }

    @objc private func openFile() { onOpen?() }

    private static func symbol(for status: CommitFileStatus) -> String {
        switch status {
        case .added: "plus.circle.fill"
        case .modified: "pencil.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.right.circle.fill"
        case .copied: "doc.on.doc.fill"
        }
    }

    private static func color(for status: CommitFileStatus) -> NSColor {
        switch status {
        case .added: .systemGreen
        case .modified: .systemOrange
        case .deleted: .systemRed
        case .renamed: .systemBlue
        case .copied: .systemPurple
        }
    }
}

private final class CommitFilePointingButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
    }
}
