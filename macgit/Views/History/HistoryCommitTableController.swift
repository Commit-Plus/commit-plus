// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HistoryCommitTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    let tableView = HistoryNSTableView()
    private(set) var listModel: HistoryListModel?
    private(set) var actions: HistoryCommitActionController?
    private(set) var repositoryURL: URL?
    private var customActionStore: CustomActionStore?
    private(set) var textScale: CGFloat = 1
    private(set) var rows = HistoryRows(commits: [], graphModel: nil, hasMore: false, version: -1,
                                      change: .reload(preserveViewport: false), indexByHash: [:])
    private var appliedVersion = -1
    private var appliedTextScale: CGFloat = 1
    private var appliedDragActive: Set<String> = []
    private var lastScrollToken: UUID?
    private var isApplyingModelSelection = false
    private var boundsObserver: NSObjectProtocol?
    private var hostedMenu: NSMenu?
    private var dragPresentation: CommitDragPreviewPresentation?
    private var draggedHashes: Set<String> = []

    func makeScrollView() -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1000, height: 300))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        tableView.frame = scroll.bounds
        tableView.gridStyleMask = .solidVerticalGridLineMask
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 3, height: 0)
        tableView.style = .plain
        tableView.controlSize = .small
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "NSTableView Columns HistoryCommitTable") != nil
        let ratios = defaults.dictionary(forKey: "history.tableColumnRatios") as? [String: Double]
        let columns: [(String, String, CGFloat, CGFloat)] = [
            ("graph", "Graph", 60, 200), ("message", "Message", 120, 400),
            ("author", "Author", 140, 180), ("date", "Date", 100, 140), ("commit", "Commit", 72, 80)
        ]
        for (id, title, minimum, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.minWidth = minimum
            if !saved, let ratio = ratios?[id], ratio.isFinite, ratio > 0 {
                column.width = max(minimum, CGFloat(ratio) * tableView.bounds.width)
            } else { column.width = width }
            tableView.addTableColumn(column)
        }
        tableView.autosaveName = "HistoryCommitTable"
        tableView.autosaveTableColumns = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClick)
        tableView.onReturn = { [weak self] in self?.activatePrimaryCommit() }
        tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu
        let headerMenu = NSMenu()
        for id in ["author", "date", "commit"] {
            let item = NSMenuItem(title: id.capitalized, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            headerMenu.addItem(item)
        }
        headerMenu.delegate = self
        tableView.headerView?.menu = headerMenu
        scroll.documentView = tableView
        scroll.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.loadMoreIfNeeded() } }
        return scroll
    }
    func removeObservers() {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        boundsObserver = nil
        tableView.onReturn = nil
    }

    func apply(listModel: HistoryListModel, actions: HistoryCommitActionController,
               customActionStore: CustomActionStore, repositoryURL: URL, textScale: CGFloat,
               rows: HistoryRows, selection: HistoryCommitSelection,
               scrollRequest: HistoryScrollRequest?, dragActive: Set<String>) {
        self.listModel = listModel
        self.actions = actions
        self.customActionStore = customActionStore
        self.repositoryURL = repositoryURL
        self.textScale = textScale
        let changed = appliedVersion != rows.version
        isApplyingModelSelection = true
        if changed {
            let oldRows = self.rows
            let anchor = viewportAnchor()
            self.rows = rows
            switch rows.change {
            case .appended(let range):
                tableView.beginUpdates()
                if oldRows.hasMore { tableView.removeRows(at: IndexSet(integer: oldRows.commits.count), withAnimation: []) }
                var inserted = IndexSet(integersIn: range)
                if rows.hasMore { inserted.insert(rows.commits.count) }
                tableView.insertRows(at: inserted, withAnimation: [])
                tableView.endUpdates()
            case .reload(let preserveViewport):
                tableView.reloadData()
                if preserveViewport { restoreViewport(anchor) }
            }
            appliedVersion = rows.version
        }
        let selected = IndexSet(selection.selectedHashes.compactMap { rows.indexByHash[$0] })
        if tableView.selectedRowIndexes != selected { tableView.selectRowIndexes(selected, byExtendingSelection: false) }
        isApplyingModelSelection = false
        if let request = scrollRequest, request.token != lastScrollToken {
            lastScrollToken = request.token
            if let row = rows.indexByHash[request.hash], let clip = tableView.enclosingScrollView?.contentView {
                let rect = tableView.rect(ofRow: row)
                scroll(to: rect.midY - clip.bounds.height / 2)
                if request.focus { tableView.window?.makeFirstResponder(tableView) }
            }
            listModel.consumeScrollRequest(request.token)
        }
        if appliedTextScale != textScale {
            let anchor = viewportAnchor()
            isApplyingModelSelection = true
            tableView.reloadData()
            tableView.selectRowIndexes(selected, byExtendingSelection: false)
            isApplyingModelSelection = false
            restoreViewport(anchor)
            appliedTextScale = textScale
        }
        if appliedDragActive != dragActive {
            let affected = appliedDragActive.union(dragActive)
            appliedDragActive = dragActive
            tableView.enumerateAvailableRowViews { view, row in
                guard rows.commits.indices.contains(row), affected.contains(rows.commits[row].hash) else { return }
                view.alphaValue = dragActive.contains(rows.commits[row].hash) ? 0.4 : 1
            }
        }
        if changed { loadMoreIfNeeded() }
    }
    private func viewportAnchor() -> (String, CGFloat)? {
        let row = tableView.rows(in: tableView.visibleRect).location
        guard rows.commits.indices.contains(row) else { return nil }
        return (rows.commits[row].hash, tableView.visibleRect.minY - tableView.rect(ofRow: row).minY)
    }
    private func restoreViewport(_ anchor: (String, CGFloat)?) {
        guard let anchor, let row = rows.indexByHash[anchor.0] else { return }
        scroll(to: tableView.rect(ofRow: row).minY + anchor.1)
    }
    private func scroll(to y: CGFloat) {
        guard let scroll = tableView.enclosingScrollView else { return }
        let clip = scroll.contentView
        let maximum = max(0, tableView.bounds.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(maximum, max(0, y))))
        scroll.reflectScrolledClipView(clip)
    }
    func loadMoreIfNeeded() {
        let range = tableView.rows(in: tableView.visibleRect)
        guard range.location != NSNotFound, range.length > 0 else { return }
        listModel?.loadMoreIfNeeded(lastVisibleRow: range.location + range.length - 1, visibleCount: range.length)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.commits.count + (rows.hasMore ? 1 : 0) }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let column else { return nil }
        let id = column.identifier
        if row == rows.commits.count {
            guard rows.hasMore, id.rawValue == "message" else { return nil }
            let loadingID = NSUserInterfaceItemIdentifier("loading")
            let cell = tableView.makeView(withIdentifier: loadingID, owner: self) as? HistoryLoadingCellView ?? HistoryLoadingCellView()
            cell.identifier = loadingID
            cell.configure(textScale: textScale)
            return cell
        }
        guard rows.commits.indices.contains(row) else { return nil }
        let commit = rows.commits[row]
        switch id.rawValue {
        case "graph":
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? HistoryGraphCellView ?? HistoryGraphCellView()
            cell.identifier = id
            cell.configure(model: rows.graphModel, rowIndex: row)
            return cell
        case "message":
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? HistoryMessageCellView ?? HistoryMessageCellView()
            cell.identifier = id
            cell.configure(commit: commit, colorIndex: rows.graphModel?.commitMetadata[commit.hash]?.colorIndex, textScale: textScale)
            return cell
        default:
            let cell = tableView.makeView(withIdentifier: id, owner: self) as? HistoryTextCellView ?? HistoryTextCellView()
            cell.identifier = id
            cell.configure(commit: commit, column: id.rawValue, textScale: textScale)
            return cell
        }
    }
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        rowView.alphaValue = rows.commits.indices.contains(row) && appliedDragActive.contains(rows.commits[row].hash) ? 0.4 : 1
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingModelSelection else { return }
        listModel?.applyTableSelection(orderedHashes: tableView.selectedRowIndexes.compactMap {
            rows.commits.indices.contains($0) ? rows.commits[$0].hash : nil
        }, debounceDetail: tableView.isHandlingKeyboardSelection)
    }
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection indexes: IndexSet) -> IndexSet {
        indexes.intersection(IndexSet(integersIn: 0..<rows.commits.count))
    }
    func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
        columnIndex >= 2 && newColumnIndex >= 2
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row == self.tableView.dragOriginRow, rows.commits.indices.contains(row),
              let listModel, let repositoryURL else { return nil }
        let commit = rows.commits[row]
        let commits = HistoryLoadPolicy.draggedCommits(
            startingAt: commit.hash, commits: rows.commits, selection: listModel.selection
        )
        guard !commits.isEmpty else { return nil }
        let payload = GitDragPayload.commits(commits, repositoryURL: repositoryURL)
        guard let data = try? GitDragPayload.encodeTransferData(payload) else { return nil }
        let item = NSPasteboardItem()
        guard item.setData(data, forType: NSPasteboard.PasteboardType(UTType.macgitGitDragPayload.identifier)) else { return nil }
        GitDragPayloadStore.set(payload)
        dragPresentation = CommitDragPreviewPresentation(commit: commit, commitCount: commits.count)
        draggedHashes = Set(commits.map(\.hash))
        return item
    }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        session.draggingFormation = .none
        listModel?.setDragActive(draggedHashes)
        if let presentation = dragPresentation {
            let preview = CommitDragPreview(presentation: presentation, onDragStateChange: { _ in })
                .environment(\.colorScheme, tableView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
            let renderer = ImageRenderer(content: preview)
            renderer.scale = tableView.window?.backingScaleFactor ?? 2
            if let image = renderer.nsImage {
                let point = tableView.convert(tableView.window?.convertPoint(fromScreen: screenPoint) ?? .zero, from: nil)
                session.enumerateDraggingItems(
                    options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]
                ) { item, _, _ in
                    item.setDraggingFrame(
                        NSRect(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2,
                               width: image.size.width, height: image.size.height), contents: image
                    )
                }
            }
        }
        dragPresentation = nil
    }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        listModel?.setDragActive([])
        draggedHashes = []
        dragPresentation = nil
        self.tableView.suppressDoubleClickUntil = Date().addingTimeInterval(NSEvent.doubleClickInterval)
        // The destination owns payload cleanup; it may still be decoding the drop.
    }
    @objc private func toggleColumn(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              let column = tableView.tableColumns.first(where: { $0.identifier.rawValue == id }) else { return }
        column.isHidden.toggle()
        item.state = column.isHidden ? .off : .on
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === tableView.headerView?.menu {
            for item in menu.items {
                let column = tableView.tableColumns.first { $0.identifier.rawValue == item.representedObject as? String }
                item.state = column?.isHidden == false ? .on : .off
            }
            return
        }
        menu.removeAllItems()
        hostedMenu = nil
        let row = tableView.clickedRow
        guard rows.commits.indices.contains(row), let actions, let customActionStore, let repositoryURL else { return }
        if !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            listModel?.applyTableSelection(orderedHashes: [rows.commits[row].hash])
        }
        let commits = tableView.selectedRowIndexes.compactMap { rows.commits.indices.contains($0) ? rows.commits[$0] : nil }
        let primary = commits.first { $0.hash == listModel?.selection.primaryHash } ?? commits.first
        let hosting = NSHostingMenu(rootView: HistoryCommitContextMenu(
            contextCommits: commits, primaryCommit: primary, headHash: listModel?.headHash,
            repositoryURL: repositoryURL, controller: actions
        ).environmentObject(customActionStore))
        hostedMenu = hosting
        for item in hosting.items { hosting.removeItem(item); menu.addItem(item) }
    }
    @objc private func doubleClick() {
        guard Date() >= tableView.suppressDoubleClickUntil, rows.commits.indices.contains(tableView.clickedRow) else { return }
        actions?.handleDoubleClick(rows.commits[tableView.clickedRow])
    }
    private func activatePrimaryCommit() {
        guard let hash = listModel?.selection.primaryHash, let row = rows.indexByHash[hash] else { return }
        actions?.handleDoubleClick(rows.commits[row])
    }
}
