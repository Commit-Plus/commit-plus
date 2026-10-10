// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileStatusNativeList: NSViewRepresentable {
    struct Row: Equatable {
        let file: StatusFile
        let count: FileLineChangeCount?
        let isLFS: Bool
        let isPotentialConflict: Bool
        let isActionSelected: Bool
        let isPreviewed: Bool
    }

    let rows: [Row]
    let isStaged: Bool
    let textScale: CGFloat
    let onSelect: (StatusFile, NSEvent.ModifierFlags) -> Void
    let onToggleSelection: (StatusFile, Bool) -> Void
    let onQuickAction: (StatusFile) -> Void
    let onDoubleClick: (StatusFile) -> Void
    let onOpenPotentialConflict: (StatusFile) -> Void
    let dragPaths: (StatusFile) -> [String]
    let makeDragPayload: ([String]) -> GitDragPayload
    let makeMoreMenu: (StatusFile) -> NSMenu
    let makeContextMenu: (StatusFile) -> NSMenu
    let onDrop: ([GitDragPayload]) -> Bool
    let onDropTargetChanged: (Bool) -> Void

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
        private let tableView = FileStatusTableView()
        private var model: FileStatusNativeList?
        private var rows: [Row] = []
        private var appliedScale: CGFloat = 0
        private var hostedMenu: NSMenu?
        private var isDropTargeted = false

        func makeScrollView() -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false

            let column = NSTableColumn(identifier: .init("file"))
            column.resizingMask = .autoresizingMask
            tableView.addTableColumn(column)
            tableView.headerView = nil
            tableView.backgroundColor = .clear
            tableView.selectionHighlightStyle = .none
            tableView.allowsEmptySelection = true
            tableView.intercellSpacing = .zero
            tableView.style = .plain
            tableView.dataSource = self
            tableView.delegate = self
            tableView.target = self
            tableView.action = #selector(clickedRow)
            tableView.doubleAction = #selector(doubleClickedRow)
            tableView.contextMenuProvider = { [weak self] row in self?.contextMenu(for: row) }
            tableView.onDraggingExited = { [weak self] in self?.setDropTargeted(false) }
            tableView.registerForDraggedTypes([
                NSPasteboard.PasteboardType(UTType.macgitGitDragPayload.identifier)
            ])
            tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
            tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
            scroll.documentView = tableView
            return scroll
        }

        func stop() {
            tableView.contextMenuProvider = nil
            tableView.onDraggingExited = nil
            hostedMenu = nil
            setDropTargeted(false)
        }

        func apply(_ model: FileStatusNativeList) {
            self.model = model
            let scaleChanged = appliedScale != model.textScale
            if scaleChanged {
                appliedScale = model.textScale
                tableView.rowHeight = 48 * model.textScale
            }

            let oldRows = rows
            let structureChanged = oldRows.map(\.file.id) != model.rows.map(\.file.id)
            rows = model.rows
            if structureChanged || scaleChanged {
                let anchor = viewportAnchor(in: oldRows)
                tableView.reloadData()
                restoreViewport(anchor)
                return
            }

            var changed = IndexSet()
            for index in rows.indices where rows[index] != oldRows[index] {
                changed.insert(index)
            }
            if !changed.isEmpty {
                tableView.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
                for index in changed {
                    (tableView.rowView(atRow: index, makeIfNecessary: false) as? FileStatusNativeRowView)?
                        .configure(with: rows[index])
                }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let model else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("FileStatusCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FileStatusNativeCell
                ?? FileStatusNativeCell()
            cell.identifier = identifier
            let item = rows[row]
            cell.configure(
                row: item,
                isStaged: model.isStaged,
                textScale: model.textScale,
                onToggle: { [weak self] selected in self?.model?.onToggleSelection(item.file, selected) },
                onQuick: { [weak self] in self?.model?.onQuickAction(item.file) },
                onMore: { [weak self, weak cell] in
                    guard let self, let cell else { return }
                    self.showMoreMenu(for: item.file, relativeTo: cell.moreButton)
                },
                onPotentialConflict: { [weak self] in self?.model?.onOpenPotentialConflict(item.file) }
            )
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard rows.indices.contains(row) else { return nil }
            let view = FileStatusNativeRowView()
            view.configure(with: rows[row])
            return view
        }

        @objc private func clickedRow() {
            let row = tableView.clickedRow
            guard rows.indices.contains(row), let event = NSApp.currentEvent else { return }
            model?.onSelect(rows[row].file, event.modifierFlags)
        }

        @objc private func doubleClickedRow() {
            let row = tableView.clickedRow
            guard rows.indices.contains(row) else { return }
            model?.onDoubleClick(rows[row].file)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard NSApp.currentEvent?.type == .keyDown,
                  rows.indices.contains(tableView.selectedRow)
            else { return }
            model?.onSelect(rows[tableView.selectedRow].file, NSApp.currentEvent?.modifierFlags ?? [])
        }

        private func showMoreMenu(for file: StatusFile, relativeTo view: NSView) {
            guard let model else { return }
            let menu = model.makeMoreMenu(file)
            hostedMenu = menu
            menu.delegate = self
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX, y: view.bounds.minY), in: view)
        }

        private func contextMenu(for row: Int) -> NSMenu? {
            guard rows.indices.contains(row), let model else { return nil }
            let menu = model.makeContextMenu(rows[row].file)
            hostedMenu = menu
            menu.delegate = self
            return menu
        }

        func menuDidClose(_ menu: NSMenu) {
            if hostedMenu === menu { hostedMenu = nil }
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard rows.indices.contains(row), let model else { return nil }
            let file = rows[row].file
            let paths = model.dragPaths(file)
            guard !paths.isEmpty else { return nil }
            let payload = model.makeDragPayload(paths)
            guard let data = try? GitDragPayload.encodeTransferData(payload) else { return nil }
            let item = NSPasteboardItem()
            guard item.setData(data, forType: .init(UTType.macgitGitDragPayload.identifier)) else { return nil }
            GitDragPayloadStore.set(payload)
            return item
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                       proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            guard decodePayloads(from: info.draggingPasteboard) != nil else {
                setDropTargeted(false)
                return []
            }
            tableView.setDropRow(-1, dropOperation: .on)
            setDropTargeted(true)
            return .copy
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                       row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            defer { setDropTargeted(false) }
            guard let payloads = decodePayloads(from: info.draggingPasteboard) else { return false }
            return model?.onDrop(payloads) == true
        }

        private func decodePayloads(from pasteboard: NSPasteboard) -> [GitDragPayload]? {
            let type = NSPasteboard.PasteboardType(UTType.macgitGitDragPayload.identifier)
            guard let data = pasteboard.data(forType: type),
                  let payload = try? GitDragPayload.decodeTransferData(data) else { return nil }
            return [payload]
        }

        private func setDropTargeted(_ targeted: Bool) {
            guard isDropTargeted != targeted else { return }
            isDropTargeted = targeted
            model?.onDropTargetChanged(targeted)
        }

        private func viewportAnchor(in source: [Row]) -> (String, CGFloat)? {
            let visible = tableView.rows(in: tableView.visibleRect)
            guard visible.location != NSNotFound, source.indices.contains(visible.location) else { return nil }
            let row = visible.location
            return (source[row].file.id, tableView.visibleRect.minY - tableView.rect(ofRow: row).minY)
        }

        private func restoreViewport(_ anchor: (String, CGFloat)?) {
            guard let anchor, let row = rows.firstIndex(where: { $0.file.id == anchor.0 }),
                  let scroll = tableView.enclosingScrollView else { return }
            let y = tableView.rect(ofRow: row).minY + anchor.1
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

private final class FileStatusTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var onDraggingExited: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        return contextMenuProvider?(row)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        onDraggingExited?()
    }
}

private final class FileStatusNativeRowView: NSTableRowView {
    private var isActionSelected = false
    private var isPreviewed = false

    func configure(with row: FileStatusNativeList.Row) {
        isActionSelected = row.isActionSelected
        isPreviewed = row.isPreviewed
        backgroundColor = isActionSelected ? NSColor.controlAccentColor.withAlphaComponent(0.16) : .clear
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if isPreviewed {
            NSColor.controlAccentColor.setFill()
            NSRect(x: bounds.minX, y: bounds.minY, width: 3, height: bounds.height).fill()
        }
    }
}

private final class FileStatusNativeCell: NSTableCellView {
    let moreButton = FileStatusPointingButton()
    private let checkbox = FileStatusPointingButton(checkboxWithTitle: "", target: nil, action: nil)
    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let addedCountLabel = NSTextField(labelWithString: "")
    private let removedCountLabel = NSTextField(labelWithString: "")
    private let lfsLabel = NSTextField(labelWithString: "LFS")
    private let conflictButton = FileStatusPointingButton()
    private let quickButton = FileStatusPointingButton()
    private var addedCountWidth: CGFloat = 0
    private var removedCountWidth: CGFloat = 0
    private var onToggle: ((Bool) -> Void)?
    private var onQuick: (() -> Void)?
    private var onMore: (() -> Void)?
    private var onPotentialConflict: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [checkbox, icon, nameLabel, pathLabel, addedCountLabel, removedCountLabel,
                     lfsLabel, conflictButton, quickButton, moreButton] {
            addSubview(view)
        }
        checkbox.setButtonType(.switch)
        checkbox.isBordered = false
        checkbox.controlSize = .small
        checkbox.target = self
        checkbox.action = #selector(toggleSelection)
        icon.imageScaling = .scaleProportionallyDown
        nameLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = .tertiaryLabelColor
        for label in [addedCountLabel, removedCountLabel] {
            label.lineBreakMode = .byClipping
            label.maximumNumberOfLines = 1
        }
        addedCountLabel.textColor = .systemGreen
        removedCountLabel.textColor = .systemRed
        lfsLabel.alignment = .center
        lfsLabel.textColor = .secondaryLabelColor
        lfsLabel.wantsLayer = true
        lfsLabel.layer?.borderWidth = 1
        lfsLabel.layer?.cornerRadius = 3
        lfsLabel.setAccessibilityLabel("Tracked by Git LFS")
        lfsLabel.toolTip = "Tracked by Git Large File Storage"
        conflictButton.isBordered = false
        conflictButton.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Potential conflict")
        conflictButton.contentTintColor = .systemOrange
        conflictButton.target = self
        conflictButton.action = #selector(openPotentialConflict)
        quickButton.isBordered = false
        quickButton.target = self
        quickButton.action = #selector(runQuickAction)
        moreButton.isBordered = false
        moreButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More actions")
        moreButton.target = self
        moreButton.action = #selector(openMoreMenu)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(row: FileStatusNativeList.Row, isStaged: Bool, textScale: CGFloat,
                   onToggle: @escaping (Bool) -> Void, onQuick: @escaping () -> Void,
                   onMore: @escaping () -> Void, onPotentialConflict: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onQuick = onQuick
        self.onMore = onMore
        self.onPotentialConflict = onPotentialConflict
        checkbox.state = row.isActionSelected ? .on : .off
        checkbox.setAccessibilityLabel("Select \(row.file.displayName)")
        nameLabel.stringValue = row.file.displayName
        nameLabel.font = .systemFont(ofSize: 13 * textScale, weight: .medium)
        pathLabel.stringValue = row.file.originalPath.map { "\($0) → \(row.file.path)" } ?? row.file.directory
        pathLabel.font = .systemFont(ofSize: 10 * textScale)
        pathLabel.textColor = row.file.originalPath == nil ? .tertiaryLabelColor : .secondaryLabelColor
        icon.image = NSImage(
            systemSymbolName: Self.iconName(for: row.file),
            accessibilityDescription: row.file.status.rawValue.capitalized
        )
        icon.contentTintColor = Self.color(for: row.file)
        if let count = row.count {
            let font = NSFont.monospacedSystemFont(ofSize: 10 * textScale, weight: .medium)
            addedCountLabel.font = font
            removedCountLabel.font = font
            addedCountLabel.stringValue = "+\(count.added)"
            removedCountLabel.stringValue = "-\(count.removed)"
            // AppKit's intrinsic width can end on the final glyph's antialiased edge.
            // Keep a small trailing allowance so the last digit is never clipped.
            addedCountWidth = ceil(addedCountLabel.intrinsicContentSize.width) + 3
            removedCountWidth = ceil(removedCountLabel.intrinsicContentSize.width) + 3
            addedCountLabel.setAccessibilityLabel("\(count.added) lines added")
            removedCountLabel.setAccessibilityLabel("\(count.removed) lines removed")
            addedCountLabel.isHidden = false
            removedCountLabel.isHidden = false
        } else {
            addedCountWidth = 0
            removedCountWidth = 0
            addedCountLabel.isHidden = true
            removedCountLabel.isHidden = true
        }
        lfsLabel.isHidden = !row.isLFS
        lfsLabel.layer?.borderColor = NSColor.separatorColor.cgColor
        conflictButton.isHidden = !row.isPotentialConflict
        conflictButton.toolTip = row.isPotentialConflict ? "View potential conflict details" : nil
        conflictButton.setAccessibilityLabel("View potential conflict details")
        quickButton.image = NSImage(
            systemSymbolName: isStaged ? "minus" : "plus",
            accessibilityDescription: isStaged ? "Unstage" : "Stage"
        )
        quickButton.toolTip = isStaged ? "Unstage" : "Stage"
        quickButton.setAccessibilityLabel(isStaged ? "Unstage" : "Stage")
        // Counts arrive asynchronously and change the manually laid out widths.
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        checkbox.frame = NSRect(x: 5, y: midY - 9, width: 18, height: 18)
        icon.frame = NSRect(x: 29, y: midY - 9, width: 18, height: 18)
        moreButton.frame = NSRect(x: bounds.maxX - 24, y: midY - 11, width: 22, height: 22)
        quickButton.frame = NSRect(x: moreButton.frame.minX - 22, y: midY - 11, width: 22, height: 22)
        var accessoryX = quickButton.frame.minX
        if !conflictButton.isHidden {
            accessoryX -= 24
            conflictButton.frame = NSRect(x: accessoryX, y: midY - 11, width: 22, height: 22)
        }
        if !lfsLabel.isHidden {
            accessoryX -= 34
            lfsLabel.frame = NSRect(x: accessoryX, y: midY - 9, width: 30, height: 18)
        }
        let textX: CGFloat = 53
        let textWidth = max(20, accessoryX - textX - 6)
        nameLabel.frame = NSRect(x: textX, y: midY + 1, width: textWidth, height: 18)
        let countWidth = addedCountWidth + removedCountWidth + (addedCountWidth > 0 ? 4 : 0)
        pathLabel.frame = NSRect(x: textX, y: midY - 17, width: max(20, textWidth - countWidth - 6), height: 16)
        addedCountLabel.frame = NSRect(
            x: pathLabel.frame.maxX + 6,
            y: midY - 17,
            width: addedCountWidth,
            height: 16
        )
        removedCountLabel.frame = NSRect(
            x: addedCountLabel.frame.maxX + 4,
            y: midY - 17,
            width: removedCountWidth,
            height: 16
        )
    }

    @objc private func toggleSelection() { onToggle?(checkbox.state == .on) }
    @objc private func runQuickAction() { onQuick?() }
    @objc private func openMoreMenu() { onMore?() }
    @objc private func openPotentialConflict() { onPotentialConflict?() }

    private static func iconName(for file: StatusFile) -> String {
        switch file.status {
        case .added: "plus.circle.fill"
        case .modified: "pencil.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.right.circle.fill"
        case .untracked: "questionmark.circle.fill"
        case .conflict: "exclamationmark.triangle.fill"
        case .staged: "pencil.circle.fill"
        }
    }

    private static func color(for file: StatusFile) -> NSColor {
        switch file.status {
        case .added: .systemGreen
        case .staged, .modified: .systemOrange
        case .deleted: .systemRed
        case .renamed: .systemBlue
        case .untracked: .systemGray
        case .conflict: .systemPurple
        }
    }
}

private final class FileStatusPointingButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
    }
}
