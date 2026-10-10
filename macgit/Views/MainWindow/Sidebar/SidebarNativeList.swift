// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// IDs include the section and row kind: a folder and a ref may have the same path.
struct SidebarNativeRow {
    struct ID: Hashable {
        let section: SidebarSection
        let kind: String
        let key: String
    }
    struct Appearance: Equatable {
        var title: String
        var subtitle = ""
        var icon = ""
        var badge = ""
        var indent = 0
        var header = false
        var emphasized = false
        var accessory = ""
        var accessoryLabel = ""
        var tint = "secondary"
        var spinning = false
        var italic = false
    }
    let id: ID
    var appearance: Appearance
    var selection: SidebarSelection?
    var select: (() -> Void)?
    var activate: (() -> Void)?
    var menu: (() -> NSMenu)?
    var accessory: ((NSView) -> Void)?
    var payload: (() -> GitDragPayload)?
    var dropTarget: GitDragTarget?
}

/// One scroll view and reusable AppKit cells. Scrolling never writes SwiftUI state.
struct SidebarNativeList: NSViewRepresentable {
    let repositoryURL: URL
    let input: SidebarNativeInput
    let makeRows: () -> [SidebarNativeRow]
    let selection: SidebarSelection?
    let textScale: CGFloat
    let backgroundMenu: () -> NSMenu
    let acceptDrop: (GitDragPayload, GitDragTarget, Bool) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let table = Table()
        table.frame = NSRect(x: 0, y: 0, width: 280, height: 1)
        table.autoresizingMask = [.width]
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .sourceList
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.usesAutomaticRowHeights = false
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        column.minWidth = 0
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.action = #selector(Coordinator.click)
        table.doubleAction = #selector(Coordinator.doubleClick)
        table.owner = context.coordinator
        table.registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.macgitGitDragPayload.identifier)])
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.update(self)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.generation += 1
        coordinator.retainedMenu?.cancelTracking()
        coordinator.retainedMenu = nil
        if let payload = coordinator.dragPayload { GitDragPayloadStore.clear(ifMatching: payload) }
        coordinator.dragPayload = nil
        coordinator.incomingPayload = nil
        coordinator.table?.delegate = nil
        coordinator.table?.dataSource = nil
        coordinator.table?.owner = nil
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: SidebarNativeList
        weak var table: Table?
        var rows: [SidebarNativeRow] = []
        var indices: [SidebarNativeRow.ID: Int] = [:]
        var selectionIndices: [SidebarSelection: Int] = [:]
        var installed = false
        var updating = false
        var mouseSelection = false
        var keyboardFocusID: SidebarNativeRow.ID?
        var dragPayload: GitDragPayload?
        var pasteboardKey: String?
        var incomingPayload: GitDragPayload?
        var retainedMenu: NSMenu?
        var generation = 0
        var dropID: SidebarNativeRow.ID?
        var dropLabel = ""

        init(_ parent: SidebarNativeList) { self.parent = parent }

        func update(_ next: SidebarNativeList) {
            guard let table else { return }
            if parent.selection != next.selection || parent.repositoryURL != next.repositoryURL { keyboardFocusID = nil }
            let repositoryChanged = parent.repositoryURL != next.repositoryURL
            let scaleChanged = parent.textScale != next.textScale
            let contentChanged = !installed || repositoryChanged || parent.input != next.input
            if !contentChanged && !scaleChanged {
                parent = next
                updating = true
                synchronizeSelection()
                updating = false
                return
            }
            installed = true
            SidebarSignpost.event("NativeSnapshotApply")
            generation += 1
            retainedMenu?.cancelTracking()
            retainedMenu = nil
            let oldRows = rows
            let oldIDs = oldRows.map(\.id)
            let nextRows = contentChanged ? SidebarSignpost.interval("NativeSnapshot") { next.makeRows() } : rows
            let newIDs = nextRows.map(\.id)
            let visible = table.rows(in: table.visibleRect)
            let anchor = visible.location < oldRows.count ? oldRows[visible.location].id : nil
            let offset = visible.location < oldRows.count
                ? table.visibleRect.minY - table.rect(ofRow: visible.location).minY : 0
            parent = next
            rows = nextRows
            indices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
            selectionIndices = Dictionary(uniqueKeysWithValues: rows.enumerated().compactMap { index, row in
                row.selection.map { ($0, index) }
            })
            updating = true
            defer { updating = false }
            if repositoryChanged {
                if let payload = dragPayload { GitDragPayloadStore.clear(ifMatching: payload) }
                dragPayload = nil
                incomingPayload = nil
                pasteboardKey = nil
                dropID = nil
                dropLabel = ""
                retainedMenu?.cancelTracking()
                retainedMenu = nil
                table.reloadData()
                table.scroll(.zero)
            } else if oldIDs != newIDs {
                let diff = newIDs.difference(from: oldIDs)
                var removed = IndexSet(), inserted = IndexSet()
                for change in diff {
                    switch change {
                    case .remove(let index, _, _): removed.insert(index)
                    case .insert(let index, _, _): inserted.insert(index)
                    }
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    table.beginUpdates()
                    table.removeRows(at: removed, withAnimation: [])
                    table.insertRows(at: inserted, withAnimation: [])
                    table.endUpdates()
                }
                let survivingAnchor = anchor.flatMap { indices[$0] == nil ? nil : $0 }
                    ?? oldRows.dropFirst(min(visible.location, oldRows.count)).first(where: { indices[$0.id] != nil })?.id
                    ?? oldRows.prefix(min(visible.location, oldRows.count)).last(where: { indices[$0.id] != nil })?.id
                if let anchor = survivingAnchor, let index = indices[anchor] {
                    table.scroll(NSPoint(x: 0, y: max(0, table.rect(ofRow: index).minY + offset)))
                }
            }
            if scaleChanged { table.noteHeightOfRows(withIndexesChanged: IndexSet(rows.indices)) }
            // Update only instantiated cells. No reloadData for selection, badges or hover.
            let range = table.rows(in: table.visibleRect)
            if range.location != NSNotFound {
                for index in range.location..<min(NSMaxRange(range), rows.count) {
                    if let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? Cell {
                        configure(cell, row: index)
                    }
                }
            }
            synchronizeSelection()
        }
        func synchronizeSelection() {
            guard let table else { return }
            if let keyboardFocusID, let index = indices[keyboardFocusID] {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            } else if let selection = parent.selection, let index = selectionIndices[selection] {
                if table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            } else { table.deselectAll(nil) }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            let appearance = rows[row].appearance
            return (appearance.header ? 34 : appearance.subtitle.isEmpty ? 28 : 42) * parent.textScale
        }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            rows[row].select != nil
        }
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            rows[row].select == nil ? nil : rows[row].appearance.title
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("sidebar-cell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? Cell ?? Cell()
            cell.identifier = identifier
            configure(cell, row: row)
            return cell
        }
        func configure(_ cell: Cell, row: Int) {
            var appearance = rows[row].appearance
            if rows[row].id == dropID { appearance.badge = dropLabel }
            cell.configure(appearance, scale: parent.textScale)
            let id = rows[row].id
            cell.onAccessory = { [weak self, weak cell] in
                guard let self, let cell, let index = self.indices[id] else { return }
                self.rows[index].accessory?(cell.button)
            }
            cell.onPress = { [weak self] in
                guard let self, let index = self.indices[id] else { return }
                self.rows[index].select?()
            }
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, !mouseSelection, let table, rows.indices.contains(table.selectedRow) else { return }
            let row = rows[table.selectedRow]
            keyboardFocusID = row.selection == nil ? row.id : nil
            if row.selection != nil { row.select?() }
        }
        func mouseDown(row: Int) {
            keyboardFocusID = nil
            guard rows.indices.contains(row), rows[row].selection != nil else { return }
            table?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if rows[row].selection != parent.selection {
                SidebarSignpost.event("NativeSelection")
                rows[row].select?()
            }
        }
        @objc func click() {
            guard let table, rows.indices.contains(table.clickedRow), rows[table.clickedRow].selection == nil else { return }
            rows[table.clickedRow].select?()
        }
        @objc func doubleClick() {
            guard let table, rows.indices.contains(table.clickedRow) else { return }
            rows[table.clickedRow].activate?()
        }
        func menu(row: Int) -> NSMenu {
            let menu = SidebarSignpost.interval("NativeMenu") {
                rows.indices.contains(row) ? rows[row].menu?() ?? parent.backgroundMenu() : parent.backgroundMenu()
            }
            let generation = generation
            if let menu = menu as? SidebarNativeMenu {
                menu.installGuard { [weak self] in self?.generation == generation }
                menu.onClose = { [weak self] in self?.retainedMenu = nil }
            }
            retainedMenu = menu
            return menu
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard let payload = rows[row].payload?(), let data = try? GitDragPayload.encodeTransferData(payload) else { return nil }
            dragPayload = payload
            SidebarSignpost.event("NativeDragEncode")
            GitDragPayloadStore.set(payload)
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.macgitGitDragPayload.identifier))
            return item
        }
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            if let dragPayload { GitDragPayloadStore.clear(ifMatching: dragPayload) }
            dragPayload = nil
            incomingPayload = nil
            pasteboardKey = nil
        }
        func payload(_ info: NSDraggingInfo) -> GitDragPayload? {
            let board = info.draggingPasteboard
            let key = "\(board.name.rawValue):\(board.changeCount)"
            if pasteboardKey != key {
                SidebarSignpost.event("NativeDragDecode")
                pasteboardKey = key
                incomingPayload = board.data(forType: NSPasteboard.PasteboardType(UTType.macgitGitDragPayload.identifier))
                    .flatMap { try? GitDragPayload.decodeTransferData($0) }
            }
            return incomingPayload
        }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            let hit = tableView.row(at: tableView.convert(info.draggingLocation, from: nil))
            guard rows.indices.contains(hit), let target = rows[hit].dropTarget, let payload = payload(info),
                  case .accept(let request) = GitDragDropPolicy.decision(for: payload, target: target, receivingRepositoryURL: parent.repositoryURL, optionKeyPressed: NSEvent.modifierFlags.contains(.option)) else {
                clearDrop()
                return []
            }
            let label: String
            switch request {
            case .cherryPick: label = "Cherry-pick"
            case .createBranch: label = "Create Branch"
            case .checkoutRemoteBranch: label = "Checkout Remote Branch"
            case .createTagFromBranch, .createTagFromCommit: label = "Create Tag"
            case .moveTag: label = "Move Tag"
            case .pushBranchToRemote: label = "Push Branch"
            case .branchOperation(_, _, let operation): label = operation == .rebase ? "Rebase" : "Merge"
            case .stashFiles: label = "Stash Files"
            case .applyStash: label = "Apply Stash"
            }
            setDrop(id: rows[hit].id, label: label)
            preserveCommitPreview(info)
            tableView.setDropRow(hit, dropOperation: .on)
            return .copy
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            defer { clearDrop() }
            guard rows.indices.contains(row), let target = rows[row].dropTarget, let payload = payload(info) else { return false }
            return parent.acceptDrop(payload, target, NSEvent.modifierFlags.contains(.option))
        }
        func clearDrop() { setDrop(id: nil, label: "") }
        func setDrop(id: SidebarNativeRow.ID?, label: String) {
            guard id != dropID || label != dropLabel else { return }
            let previous = dropID
            dropID = id
            dropLabel = label
            for key in [previous, id].compactMap({ $0 }) {
                if let index = indices[key], let cell = table?.view(atColumn: 0, row: index, makeIfNecessary: false) as? Cell { configure(cell, row: index) }
            }
        }
        func preserveCommitPreview(_ info: NSDraggingInfo) {
            guard let table, let payload = payload(info), case .commits = payload.content else { return }
            info.draggingFormation = .none
            info.enumerateDraggingItems(options: [], for: table, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                let original = item.draggingFrame
                let target = SidebarBranchDropTarget.DropTargetView.commitPreviewFrame(preservingCenterOf: original)
                let components = item.imageComponents?.map { component in
                    component.frame = SidebarBranchDropTarget.DropTargetView.scaledComponentFrame(component.frame, from: original.size, to: target.size)
                    return component
                }
                item.draggingFrame = target
                if let components { item.imageComponentsProvider = { components } }
            }
        }
    }

    final class Table: NSTableView {
        weak var owner: Coordinator?
        override func menu(for event: NSEvent) -> NSMenu? {
            owner?.menu(row: row(at: convert(event.locationInWindow, from: nil)))
        }
        override func draggingExited(_ sender: NSDraggingInfo?) {
            super.draggingExited(sender)
            owner?.clearDrop()
        }
        override func draggingEnded(_ sender: NSDraggingInfo) {
            super.draggingEnded(sender)
            owner?.clearDrop()
        }
        override func updateDraggingItemsForDrag(_ sender: NSDraggingInfo?) {
            if let sender { owner?.preserveCommitPreview(sender) }
        }
        override func mouseDown(with event: NSEvent) {
            let hit = row(at: convert(event.locationInWindow, from: nil))
            if let owner, owner.rows.indices.contains(hit), owner.rows[hit].selection == nil {
                if event.clickCount == 1 { owner.rows[hit].select?() }
                return
            }
            owner?.mouseSelection = true
            owner?.mouseDown(row: hit)
            super.mouseDown(with: event)
            owner?.mouseSelection = false
        }
        override func resetCursorRects() {
            super.resetCursorRects()
            guard let owner else { return }
            let range = rows(in: visibleRect)
            guard range.location != NSNotFound else { return }
            for index in range.location..<min(NSMaxRange(range), owner.rows.count) where owner.rows[index].select != nil {
                addCursorRect(rect(ofRow: index).intersection(visibleRect), cursor: .pointingHand)
            }
        }
        override func keyDown(with event: NSEvent) {
            guard let owner, owner.rows.indices.contains(selectedRow) else { super.keyDown(with: event); return }
            let row = owner.rows[selectedRow]
            if event.keyCode == 123 { // Collapse or focus the nearest parent disclosure.
                if row.id.kind == "folder" && row.appearance.icon == "chevron.down"
                    || row.id.kind == "header" && row.appearance.badge == "⌄" {
                    row.select?()
                    return
                }
                let parent = owner.rows[..<selectedRow].lastIndex { candidate in
                    candidate.id.section == row.id.section && (candidate.id.kind == "header"
                        || (candidate.id.kind == "folder" && row.id.key.hasPrefix(candidate.id.key + "/")))
                }
                if let parent { selectRowIndexes(IndexSet(integer: parent), byExtendingSelection: false) }
            } else if event.keyCode == 124 {
                if row.id.kind == "folder" && row.appearance.icon == "chevron.right"
                    || row.id.kind == "header" && row.appearance.badge == "›" {
                    row.select?()
                } else { super.keyDown(with: event) }
            } else if event.keyCode == 36 || event.keyCode == 49 {
                if row.selection == nil { row.select?() }
                else if event.keyCode == 36 { row.activate?() }
            } else { super.keyDown(with: event) }
        }
    }

    final class Cell: NSTableCellView {
        let icon = NSImageView()
        let title = NSTextField(labelWithString: "")
        let subtitle = NSTextField(labelWithString: "")
        let badge = NSTextField(labelWithString: "")
        let button = NSButton()
        let progress = NSProgressIndicator()
        var onAccessory: (() -> Void)?
        var onPress: (() -> Void)?
        var rowAppearance: SidebarNativeRow.Appearance?
        var scale: CGFloat = 1
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            SidebarSignpost.event("NativeCellCreate")
            for view in [icon, title, subtitle, badge, button, progress] { addSubview(view) }
            progress.style = .spinning
            progress.controlSize = .small
            progress.isDisplayedWhenStopped = false
            title.lineBreakMode = .byTruncatingTail
            subtitle.lineBreakMode = .byTruncatingMiddle
            badge.alignment = .right
            button.isBordered = false
            button.title = ""
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(accessoryClick)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc func accessoryClick() { onAccessory?() }
        override func accessibilityPerformPress() -> Bool {
            guard let onPress else { return false }
            onPress()
            return true
        }
        func configure(_ value: SidebarNativeRow.Appearance, scale: CGFloat) {
            guard rowAppearance != value || self.scale != scale else { return }
            SidebarSignpost.event("NativeCellConfigure")
            rowAppearance = value
            self.scale = scale
            title.stringValue = value.title
            title.font = .systemFont(ofSize: (value.header ? 11 : 12) * scale, weight: value.header || value.emphasized ? .semibold : .regular)
            if value.italic, let font = title.font { title.font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            title.textColor = value.header ? .secondaryLabelColor : .labelColor
            subtitle.stringValue = value.subtitle
            subtitle.font = .systemFont(ofSize: 10 * scale)
            subtitle.textColor = .secondaryLabelColor
            badge.stringValue = value.badge
            badge.font = .systemFont(ofSize: 10 * scale)
            badge.textColor = .secondaryLabelColor
            icon.image = value.icon.isEmpty ? nil : NSImage(systemSymbolName: value.icon, accessibilityDescription: nil)
            icon.contentTintColor = value.emphasized ? .controlAccentColor : tint(value.tint)
            if value.spinning { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
            button.image = value.accessory.isEmpty ? nil : NSImage(systemSymbolName: value.accessory, accessibilityDescription: value.accessoryLabel)
            button.isHidden = value.accessory.isEmpty
            button.toolTip = value.accessoryLabel
            button.setAccessibilityLabel(value.accessoryLabel)
            setAccessibilityLabel([value.title, value.subtitle, value.badge].filter { !$0.isEmpty }.joined(separator: ", "))
            toolTip = value.subtitle.isEmpty ? value.title : "\(value.title)\n\(value.subtitle)"
            needsLayout = true
        }
        override func layout() {
            super.layout()
            guard let appearance = rowAppearance else { return }
            let start = 8 + CGFloat(appearance.indent) * 16 * scale
            let iconSize = 14 * scale
            icon.frame = NSRect(x: start, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
            let progressWidth: CGFloat = appearance.spinning ? 18 : 0
            let accessoryWidth: CGFloat = (button.isHidden ? 0 : 24) + progressWidth
            button.frame = NSRect(x: bounds.width - 28, y: (bounds.height - 22) / 2, width: 22, height: 22)
            progress.frame = NSRect(x: bounds.width - 8 - accessoryWidth, y: (bounds.height - 16) / 2, width: 16, height: 16)
            let badgeWidth = min(badge.intrinsicContentSize.width, bounds.width * 0.45)
            badge.frame = NSRect(x: bounds.width - 8 - accessoryWidth - badgeWidth, y: (bounds.height - 16 * scale) / 2, width: badgeWidth, height: 16 * scale)
            let x = start + iconSize + 6
            let width = max(0, bounds.width - x - badgeWidth - accessoryWidth - 14)
            title.frame = NSRect(x: x, y: appearance.subtitle.isEmpty ? (bounds.height - 18 * scale) / 2 : bounds.height / 2, width: width, height: 18 * scale)
            subtitle.frame = NSRect(x: x, y: bounds.height / 2 - 15 * scale, width: width, height: 15 * scale)
        }
        private func tint(_ value: String) -> NSColor {
            switch value {
            case "WORKSPACE", "blue": .systemBlue
            case "BRANCHES": .systemPurple
            case "WORKTREES", "orange": .systemOrange
            case "TAGS": .systemYellow
            case "REMOTES": .systemCyan
            case "STASHES": .systemBrown
            case "SUBMODULES", "green": .systemGreen
            case "SUBTREES": .systemPink
            case "red": .systemRed
            case "accent": .controlAccentColor
            default: .secondaryLabelColor
            }
        }
    }
}

/// Menu items own their action target; there is no target or menu per rendered row.
final class SidebarNativeMenu: NSMenu, NSMenuDelegate {
    private var populate: ((SidebarNativeMenu) -> Void)?
    private final class Validation {
        var canPerform: () -> Bool = { true }
    }
    private let validation = Validation()
    var onClose: (() -> Void)?
    final class Action: NSObject {
        let perform: () -> Void
        init(_ perform: @escaping () -> Void) { self.perform = perform }
        @objc func invoke() { perform() }
    }
    init() { super.init(title: ""); autoenablesItems = false; delegate = self }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func item(_ title: String, enabled: Bool = true, checked: Bool = false, _ perform: @escaping () -> Void) {
        let validation = validation
        let target = Action {
            guard validation.canPerform() else { return }
            perform()
        }
        let item = NSMenuItem(title: title, action: #selector(Action.invoke), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        item.isEnabled = enabled
        item.state = checked ? .on : .off
        addItem(item)
    }
    func separator() { addItem(.separator()) }
    func installGuard(_ validate: @escaping () -> Bool) {
        validation.canPerform = validate
        for item in items { (item.submenu as? SidebarNativeMenu)?.installGuard(validate) }
    }
    func menuDidClose(_ menu: NSMenu) { onClose?() }
    func lazySubmenu(_ title: String, enabled: Bool, _ build: @escaping (SidebarNativeMenu) -> Void) {
        let menu = SidebarNativeMenu()
        menu.populate = build
        menu.delegate = menu
        menu.item("Loading…", enabled: false) {}
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        item.isEnabled = enabled
        addItem(item)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let populate else { return }
        self.populate = nil
        removeAllItems()
        populate(self)
        installGuard(validation.canPerform)
    }
    func submenu(_ title: String, _ build: (SidebarNativeMenu) -> Void) {
        let menu = SidebarNativeMenu()
        build(menu)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        item.isEnabled = !menu.items.isEmpty
        addItem(item)
    }
    func copy(_ title: String, value: String) {
        item(title) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    }
}
