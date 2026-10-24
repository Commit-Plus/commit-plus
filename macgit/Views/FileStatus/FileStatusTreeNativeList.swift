// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileStatusTreeNativeList: NSViewRepresentable {
    struct Row: Equatable, Identifiable {
        enum Content: Equatable {
            case folder(path: String, name: String, files: [StatusFile], isExpanded: Bool, checkState: NSControl.StateValue)
            case file(FileStatusNativeList.Row, name: String)
        }
        let id: String
        let depth: Int
        let content: Content
    }

    let rows: [Row]
    let isStaged: Bool
    let textScale: CGFloat
    let onToggleFolder: (String) -> Void
    let onToggleFolderSelection: ([StatusFile], Bool) -> Void
    let onFolderQuickAction: ([StatusFile]) -> Void
    let onSelect: (StatusFile, NSEvent.ModifierFlags) -> Void
    let onToggleSelection: (StatusFile, Bool) -> Void
    let onQuickAction: (StatusFile) -> Void
    let onOpenPotentialConflict: (StatusFile) -> Void
    let makeMoreMenu: (StatusFile) -> NSMenu
    let makeContextMenu: (StatusFile) -> NSMenu
    let dragPaths: (StatusFile) -> [String]
    let makeDragPayload: ([String]) -> GitDragPayload
    let onDrop: ([GitDragPayload]) -> Bool
    let onDropTargetChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.apply(self) }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        private let table = StatusTreeTableView()
        private var model: FileStatusTreeNativeList?
        private var rows: [Row] = []
        private var scale: CGFloat = 0
        private var hostedMenu: NSMenu?
        private var isDropTargeted = false

        func makeScrollView() -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
            let column = NSTableColumn(identifier: .init("status-tree")); column.resizingMask = .autoresizingMask
            table.addTableColumn(column); table.headerView = nil; table.backgroundColor = .clear
            table.style = .plain; table.rowHeight = 28; table.intercellSpacing = .zero; table.selectionHighlightStyle = .none
            table.dataSource = self; table.delegate = self; table.target = self; table.action = #selector(clickedRow)
            table.doubleAction = #selector(doubleClickedRow)
            table.contextMenuProvider = { [weak self] row in self?.contextMenu(row) }
            table.onDraggingExited = { [weak self] in self?.setDropTargeted(false) }
            table.registerForDraggedTypes([.init(UTType.macgitGitDragPayload.identifier)])
            table.setDraggingSourceOperationMask(.copy, forLocal: true)
            table.setDraggingSourceOperationMask(.copy, forLocal: false)
            scroll.documentView = table
            return scroll
        }

        func apply(_ model: FileStatusTreeNativeList) {
            let old = rows
            let structureChanged = old.map(\.id) != model.rows.map(\.id)
            let scaleChanged = scale != model.textScale
            self.model = model; rows = model.rows; scale = model.textScale
            if structureChanged || scaleChanged {
                let anchor = viewportAnchor(old)
                table.reloadData(); restore(anchor)
            } else {
                var changed = IndexSet()
                for index in rows.indices where rows[index] != old[index] { changed.insert(index) }
                if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0)) }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let model else { return nil }
            let item = rows[row]
            let identifier = NSUserInterfaceItemIdentifier("StatusTreeCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? StatusTreeCell ?? StatusTreeCell()
            cell.identifier = identifier
            switch item.content {
            case .folder(let path, let name, let files, let expanded, let state):
                cell.configureFolder(name: name, depth: item.depth, expanded: expanded, checkState: state,
                                     isStaged: model.isStaged, textScale: model.textScale,
                                     onToggleSelection: { [weak self] selected in self?.model?.onToggleFolderSelection(files, selected) },
                                     onQuick: { [weak self] in self?.model?.onFolderQuickAction(files) })
                cell.toolTip = path
            case .file(let fileRow, let name):
                cell.configureFile(row: fileRow, name: name, depth: item.depth, isStaged: model.isStaged,
                                   textScale: model.textScale,
                                   onToggleSelection: { [weak self] selected in self?.model?.onToggleSelection(fileRow.file, selected) },
                                   onQuick: { [weak self] in self?.model?.onQuickAction(fileRow.file) },
                                   onMore: { [weak self, weak cell] in
                                       guard let self, let cell else { return }
                                       self.showMenu(self.model?.makeMoreMenu(fileRow.file), at: cell.moreButton)
                                   },
                                   onConflict: { [weak self] in self?.model?.onOpenPotentialConflict(fileRow.file) })
            }
            return cell
        }

        @objc private func clickedRow() {
            let index = table.clickedRow
            guard rows.indices.contains(index), let model else { return }
            switch rows[index].content {
            case .folder(let path, _, _, _, _): model.onToggleFolder(path)
            case .file(let row, _): model.onSelect(row.file, NSApp.currentEvent?.modifierFlags ?? [])
            }
        }

        @objc private func doubleClickedRow() {
            let index = table.clickedRow
            guard rows.indices.contains(index), case .file(let row, _) = rows[index].content else { return }
            model?.onQuickAction(row.file)
        }

        private func contextMenu(_ index: Int) -> NSMenu? {
            guard rows.indices.contains(index), case .file(let row, _) = rows[index].content, let model else { return nil }
            let menu = model.makeContextMenu(row.file); hostedMenu = menu; menu.delegate = self; return menu
        }
        private func showMenu(_ menu: NSMenu?, at view: NSView) {
            guard let menu else { return }; hostedMenu = menu; menu.delegate = self
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX, y: view.bounds.minY), in: view)
        }
        func menuDidClose(_ menu: NSMenu) { if hostedMenu === menu { hostedMenu = nil } }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow index: Int) -> (any NSPasteboardWriting)? {
            guard rows.indices.contains(index), case .file(let row, _) = rows[index].content, let model else { return nil }
            let paths = model.dragPaths(row.file)
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

        private func viewportAnchor(_ source: [Row]) -> (String, CGFloat)? {
            // At the top, stay there so rows inserted above the first visible row are shown.
            guard table.visibleRect.minY > 0 else { return nil }
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound, source.indices.contains(visible.location) else { return nil }
            return (source[visible.location].id, table.visibleRect.minY - table.rect(ofRow: visible.location).minY)
        }
        private func restore(_ anchor: (String, CGFloat)?) {
            guard let anchor, let row = rows.firstIndex(where: { $0.id == anchor.0 }), let scroll = table.enclosingScrollView else { return }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, table.rect(ofRow: row).minY + anchor.1)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

private final class StatusTreeTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var onDraggingExited: (() -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil)); return index < 0 ? nil : contextMenuProvider?(index)
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        onDraggingExited?()
    }
}

private final class StatusTreeCell: NSTableCellView {
    let moreButton = NSButton()
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let chevron = NSImageView(), icon = FileTypeIconView()
    private let name = NSTextField(labelWithString: ""), added = NSTextField(labelWithString: ""), removed = NSTextField(labelWithString: "")
    private let lfs = NSTextField(labelWithString: "LFS"), conflict = NSButton(), quick = NSButton()
    private var onToggle: ((Bool) -> Void)?, onQuick: (() -> Void)?, onMore: (() -> Void)?, onConflict: (() -> Void)?
    private var depth = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        [checkbox, chevron, icon, name, added, removed, lfs, conflict, quick, moreButton].forEach(addSubview)
        checkbox.setButtonType(.switch); checkbox.isBordered = false; checkbox.controlSize = .small; checkbox.target = self; checkbox.action = #selector(toggle)
        chevron.imageScaling = .scaleProportionallyDown
        name.lineBreakMode = .byTruncatingMiddle; added.textColor = .systemGreen; removed.textColor = .systemRed
        lfs.textColor = .secondaryLabelColor; lfs.alignment = .center; lfs.wantsLayer = true; lfs.layer?.borderWidth = 1; lfs.layer?.cornerRadius = 3
        [conflict, quick, moreButton].forEach { $0.isBordered = false }
        conflict.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Potential conflict"); conflict.contentTintColor = .systemOrange
        moreButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More actions")
        conflict.target = self; conflict.action = #selector(openConflict); quick.target = self; quick.action = #selector(runQuick); moreButton.target = self; moreButton.action = #selector(openMore)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configureFolder(name title: String, depth: Int, expanded: Bool, checkState: NSControl.StateValue,
                         isStaged: Bool, textScale: CGFloat, onToggleSelection: @escaping (Bool) -> Void,
                         onQuick: @escaping () -> Void) {
        self.depth = depth; self.onToggle = onToggleSelection; self.onQuick = onQuick
        checkbox.state = checkState; checkbox.allowsMixedState = true
        chevron.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        icon.configure(path: title, isDirectory: true, isExpanded: expanded)
        name.stringValue = title; name.font = .systemFont(ofSize: 13 * textScale, weight: .medium)
        quick.image = NSImage(systemSymbolName: isStaged ? "minus" : "plus", accessibilityDescription: isStaged ? "Unstage folder" : "Stage folder")
        chevron.isHidden = false; added.isHidden = true; removed.isHidden = true; lfs.isHidden = true; conflict.isHidden = true; moreButton.isHidden = true; quick.isHidden = false
        needsLayout = true
    }

    func configureFile(row: FileStatusNativeList.Row, name title: String, depth: Int, isStaged: Bool, textScale: CGFloat,
                       onToggleSelection: @escaping (Bool) -> Void, onQuick: @escaping () -> Void,
                       onMore: @escaping () -> Void, onConflict: @escaping () -> Void) {
        self.depth = depth; self.onToggle = onToggleSelection; self.onQuick = onQuick; self.onMore = onMore; self.onConflict = onConflict
        checkbox.state = row.isActionSelected ? .on : .off; checkbox.allowsMixedState = false; chevron.isHidden = true
        icon.configure(path: row.file.path, isDirectory: false, statusSymbol: Self.symbol(row.file.status), statusColor: Self.color(row.file.status), statusLabel: row.file.status.rawValue.capitalized)
        name.stringValue = title; name.font = .systemFont(ofSize: 13 * textScale, weight: .medium)
        if let count = row.count { added.stringValue = "+\(count.added)"; removed.stringValue = "−\(count.removed)"; added.isHidden = false; removed.isHidden = false } else { added.isHidden = true; removed.isHidden = true }
        let countFont = NSFont.monospacedSystemFont(ofSize: 10 * textScale, weight: .medium); added.font = countFont; removed.font = countFont
        lfs.isHidden = !row.isLFS; lfs.font = .systemFont(ofSize: 9 * textScale); conflict.isHidden = !row.isPotentialConflict; moreButton.isHidden = false
        quick.isHidden = false; quick.image = NSImage(systemSymbolName: isStaged ? "minus" : "plus", accessibilityDescription: isStaged ? "Unstage" : "Stage")
        layer?.backgroundColor = row.isActionSelected ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
        wantsLayer = true; needsLayout = true
    }

    override func layout() {
        super.layout(); let y = bounds.midY; let x = CGFloat(depth) * 12 + 6
        checkbox.frame = .init(x: x, y: y - 9, width: 18, height: 18)
        chevron.frame = .init(x: x + 20, y: y - 6, width: 10, height: 12)
        icon.frame = .init(x: x + (chevron.isHidden ? 20 : 33), y: y - 8, width: 16, height: 16)
        var right = bounds.maxX - 4
        moreButton.frame = .init(x: right - 22, y: y - 11, width: 22, height: 22); if !moreButton.isHidden { right -= 24 }
        quick.frame = .init(x: right - 22, y: y - 11, width: 22, height: 22); right -= 24
        conflict.frame = .init(x: right - 22, y: y - 11, width: 22, height: 22); if !conflict.isHidden { right -= 24 }
        if !lfs.isHidden { lfs.frame = .init(x: right - 30, y: y - 9, width: 28, height: 18); right -= 34 }
        if !removed.isHidden { let w = ceil(removed.intrinsicContentSize.width) + 4; removed.frame = .init(x: right - w, y: y - 8, width: w, height: 16); right -= w + 4 }
        if !added.isHidden { let w = ceil(added.intrinsicContentSize.width) + 4; added.frame = .init(x: right - w, y: y - 8, width: w, height: 16); right -= w + 6 }
        name.frame = .init(x: icon.frame.maxX + 5, y: y - 9, width: max(20, right - icon.frame.maxX - 7), height: 18)
    }
    @objc private func toggle() { onToggle?(checkbox.state == .on) }
    @objc private func runQuick() { onQuick?() }
    @objc private func openMore() { onMore?() }
    @objc private func openConflict() { onConflict?() }
    private static func symbol(_ status: FileStatus) -> String { switch status { case .added: "plus.circle.fill"; case .staged, .modified: "pencil.circle.fill"; case .deleted: "minus.circle.fill"; case .renamed: "arrow.right.circle.fill"; case .untracked: "questionmark.circle.fill"; case .conflict: "exclamationmark.triangle.fill" } }
    private static func color(_ status: FileStatus) -> NSColor { switch status { case .added: .systemGreen; case .staged, .modified: .systemOrange; case .deleted: .systemRed; case .renamed: .systemBlue; case .untracked: .systemGray; case .conflict: .systemPurple } }
}
